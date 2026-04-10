import os
from pathlib import Path
from datetime import datetime
from typing import Any, Optional
import logging

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query
import firebase_admin
from firebase_admin import credentials, db

# Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / '.env')
load_dotenv(BASE_DIR / '.env.firebase')

# Firebase initialization
FIREBASE_DB_URL = "https://parking-bc5fe-default-rtdb.firebaseio.com"
FIREBASE_CREDENTIALS_PATH = BASE_DIR / "firebase_credentials.json"

# Try to initialize Firebase
firebase_initialized = False
try:
    # First try: Load from firebase_credentials.json file
    if FIREBASE_CREDENTIALS_PATH.exists():
        logger.info(f"Loading Firebase from file: {FIREBASE_CREDENTIALS_PATH}")
        cred = credentials.Certificate(str(FIREBASE_CREDENTIALS_PATH))
        try:
            firebase_admin.initialize_app(cred, {
                'databaseURL': FIREBASE_DB_URL
            })
        except ValueError as e:
            if "already exists" in str(e):
                logger.info("✅ Firebase already initialized (from previous load)")
            else:
                raise
        firebase_initialized = True
        logger.info("✅ Firebase initialized from credentials file")
    
    # Second try: Load from environment variables
    elif os.getenv('FIREBASE_PROJECT_ID'):
        logger.info("Loading Firebase from environment variables")
        firebase_config = {
            "type": "service_account",
            "project_id": os.getenv('FIREBASE_PROJECT_ID', 'parking-bc5fe'),
            "private_key_id": os.getenv('FIREBASE_PRIVATE_KEY_ID', ''),
            "private_key": os.getenv('FIREBASE_PRIVATE_KEY', '').replace('\\n', '\n'),
            "client_email": os.getenv('FIREBASE_CLIENT_EMAIL', ''),
            "client_id": os.getenv('FIREBASE_CLIENT_ID', ''),
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
        }
        cred = credentials.Certificate(firebase_config)
        try:
            firebase_admin.initialize_app(cred, {
                'databaseURL': FIREBASE_DB_URL
            })
        except ValueError as e:
            if "already exists" in str(e):
                logger.info("✅ Firebase already initialized (from previous load)")
            else:
                raise
        firebase_initialized = True
        logger.info("✅ Firebase initialized from environment variables")
    
    else:
        logger.warning(f"⚠️  Firebase credentials file not found at {FIREBASE_CREDENTIALS_PATH}")
        logger.warning("⚠️  No FIREBASE_PROJECT_ID in environment variables")
        logger.info("Firebase is NOT initialized - will get 503 error")
        
except Exception as e:
    logger.error(f"❌ Firebase initialization error: {e}")
    logger.info("Continuing without Firebase support - API will return 503 errors")
    import traceback
    traceback.print_exc()

app = FastAPI(title="SmartPark Sensor Server", version="1.0.0")


def _serialize(value: Any) -> Any:
    """Serialize values to JSON-compatible types"""
    if isinstance(value, dict):
        return {k: _serialize(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_serialize(item) for item in value]
    if isinstance(value, datetime):
        return value.isoformat()
    return value


def _parse_slot_data(slot_id: str, slot_data: Any) -> Optional[dict[str, Any]]:
    """Parse Firebase slot data into standard format"""
    if not isinstance(slot_data, dict):
        return None
    
    try:
        # Extract slot number
        import re
        match = re.search(r'(\d+)', slot_id)
        slot_number = int(match.group(1)) if match else 0
        
        # Extract occupied status - handle both formats
        # Format 1: has 'is_free' field (from your Firebase data)
        if 'is_free' in slot_data:
            is_free = slot_data.get('is_free', False)
            if isinstance(is_free, str):
                is_free = is_free.lower() in ['true', '1', 'free']
            occupied = not is_free
        # Format 2: has 'occupied' field (legacy format)
        else:
            occupied = slot_data.get('occupied', False)
            if isinstance(occupied, str):
                occupied = occupied.lower() in ['true', '1', 'occupied']
        
        # Extract status if available
        status = slot_data.get('status', 'unknown')
        
        # Extract duration if available
        duration_sec = slot_data.get('duration_sec')
        
        return {
            'id': slot_id,
            'number': slot_number,
            'occupied': occupied,
            'isFree': not occupied,
            'area': slot_data.get('area', 'Unknown'),
            'timestamp': slot_data.get('timestamp', datetime.now().isoformat()),
            'signal_strength': slot_data.get('signal_strength'),
            'status': status,
            'duration_sec': duration_sec,
        }
    except Exception as e:
        logger.error(f"Error parsing slot {slot_id}: {e}")
        return None


@app.get("/health")
def health() -> dict[str, Any]:
    """Health check endpoint"""
    return {
        "status": "ok",
        "firebase": "connected" if firebase_initialized else "unavailable",
        "database": "parking-bc5fe",
    }


@app.get("/sensors")
def get_sensors(
    limit: int = Query(default=100, ge=1, le=500),
    skip: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    """
    Fetch all sensor data from Firebase
    
    Response format:
    {
        "count": 5,
        "items": [
            {
                "id": "slot_1",
                "number": 1,
                "occupied": false,
                "isFree": true,
                "area": "A1",
                "timestamp": "2025-03-28T10:30:45Z"
            }
        ]
    }
    """
    if not firebase_initialized:
        raise HTTPException(
            status_code=503,
            detail="Firebase is not initialized. Check logs for details."
        )
    
    try:
        # Fetch data from Firebase
        logger.info("Fetching from Firebase path: 'slots'")
        ref = db.reference('slots')
        data = ref.get()
        
        logger.info(f"Firebase returned: {type(data).__name__} = {data}")
        
        if not data:
            logger.info("No sensor data found in Firebase at /slots path")
            return {"count": 0, "items": []}
        
        if not isinstance(data, dict):
            logger.warning(f"Unexpected data type from Firebase: {type(data)}")
            logger.warning(f"Data value: {data}")
            return {"count": 0, "items": []}
        
        # Parse all slots
        slots = []
        logger.info(f"Parsing {len(data)} slots from Firebase")
        for slot_id, slot_data in data.items():
            logger.debug(f"Parsing slot {slot_id}: {slot_data}")
            parsed = _parse_slot_data(slot_id, slot_data)
            if parsed:
                slots.append(parsed)
                logger.debug(f"✅ Parsed {slot_id}")
            else:
                logger.debug(f"❌ Failed to parse {slot_id}")
        
        # Sort by slot number
        slots.sort(key=lambda x: x['number'])
        
        # Apply pagination
        paginated_slots = slots[skip:skip + limit]
        
        logger.info(f"✅ Fetched {len(paginated_slots)} slots from Firebase (total: {len(slots)})")
        
        return {
            "count": len(paginated_slots),
            "total": len(slots),
            "items": paginated_slots
        }
    
    except Exception as e:
        logger.error(f"❌ Firebase fetch error: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Failed to fetch sensors from Firebase: {e}"
        )


@app.get("/sensors/latest")
def get_latest_sensor() -> dict[str, Any]:
    """
    Get the most recently updated sensor data
    
    Returns the slot with the newest timestamp
    """
    if not firebase_initialized:
        raise HTTPException(
            status_code=503,
            detail="Firebase is not initialized"
        )
    
    try:
        ref = db.reference('slots')
        data = ref.get()
        
        if not data or not isinstance(data, dict):
            raise HTTPException(status_code=404, detail="No sensor data found")
        
        # Find slot with latest timestamp
        latest_slot = None
        latest_timestamp = None
        
        for slot_id, slot_data in data.items():
            if not isinstance(slot_data, dict):
                continue
            
            timestamp_str = slot_data.get('timestamp', '')
            if timestamp_str:
                try:
                    timestamp = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
                    if latest_timestamp is None or timestamp > latest_timestamp:
                        latest_timestamp = timestamp
                        latest_slot = (slot_id, slot_data)
                except ValueError:
                    continue
        
        if not latest_slot:
            raise HTTPException(status_code=404, detail="No valid sensor data found")
        
        slot_id, slot_data = latest_slot
        parsed = _parse_slot_data(slot_id, slot_data)
        
        if not parsed:
            raise HTTPException(status_code=500, detail="Error parsing sensor data")
        
        logger.info(f"Latest sensor: {slot_id}")
        return parsed
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching latest sensor: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to fetch latest sensor: {e}"
        )


@app.get("/sensors/{slot_id}")
def get_sensor_by_id(slot_id: str) -> dict[str, Any]:
    """Get specific sensor data by slot ID"""
    if not firebase_initialized:
        raise HTTPException(status_code=503, detail="Firebase is not initialized")
    
    try:
        ref = db.reference(f'sensors/{slot_id}')
        data = ref.get()
        
        if not data:
            raise HTTPException(
                status_code=404,
                detail=f"No data found for slot {slot_id}"
            )
        
        parsed = _parse_slot_data(slot_id, data)
        if not parsed:
            raise HTTPException(status_code=500, detail="Error parsing sensor data")
        
        return parsed
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching sensor {slot_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch sensor: {e}")


@app.get("/sensors/availability/summary")
def get_availability_summary() -> dict[str, Any]:
    """Get parking availability summary"""
    if not firebase_initialized:
        raise HTTPException(status_code=503, detail="Firebase is not initialized")
    
    try:
        ref = db.reference('slots')
        data = ref.get()
        
        if not data or not isinstance(data, dict):
            return {
                "total": 0,
                "free": 0,
                "occupied": 0,
                "availability_rate": 0.0
            }
        
        total = 0
        free = 0
        
        for slot_id, slot_data in data.items():
            if isinstance(slot_data, dict):
                occupied = slot_data.get('occupied', False)
                if isinstance(occupied, str):
                    occupied = occupied.lower() in ['true', '1']
                
                total += 1
                if not occupied:
                    free += 1
        
        occupied = total - free
        availability_rate = (free / total * 100) if total > 0 else 0
        
        return {
            "total": total,
            "free": free,
            "occupied": occupied,
            "availability_rate": round(availability_rate, 2)
        }
    
    except Exception as e:
        logger.error(f"Error calculating availability: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to calculate availability: {e}"
        )


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", "8000"))
    logger.info(f"Starting server on port {port}")
    logger.info(f"Firebase DB URL: {FIREBASE_DB_URL}")
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=port,
        reload=True
    )
