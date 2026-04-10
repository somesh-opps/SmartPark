# SmartPark

SmartPark is an end-to-end smart parking system built from three parts:

- an ESP32 firmware layer that reads parking hardware and syncs slot state to Firebase
- a FastAPI backend in `server/` that exposes parking data through a simple REST API
- a Flutter app in `smartpark/` that displays live availability and lets you point the app at your backend

The project is designed for real-time parking visibility with a lightweight mobile dashboard.

## What it does

- shows live parking slot availability
- refreshes data automatically from the backend
- lets you configure the API base URL inside the app
- reads parking data from Firebase Realtime Database
- supports ESP32-based hardware that publishes slot, gate, and safety telemetry

## Repository layout

```text
SmartPark/
├── Hardware/
│   └── smaerparking/
│       └── smartparking.ino
├── server/
│   ├── main.py
│   ├── requirements.txt
│   └── firebase_credentials.json
└── smartpark/
    ├── lib/
    ├── android/
    ├── ios/
    ├── web/
    └── pubspec.yaml
```

## Architecture

The hardware layer publishes slot occupancy and safety data to Firebase. The FastAPI server reads that Firebase data and exposes it through endpoints used by the Flutter dashboard. The Flutter app polls the backend on a timer and renders the current parking state.

## Features

### Flutter dashboard

- live parking status cards
- free vs occupied counts
- automatic refresh every few seconds
- configurable backend URL for local network testing
- persistence of the selected API endpoint with `shared_preferences`

### FastAPI backend

- health check endpoint
- slot list endpoint with pagination
- latest slot endpoint
- individual slot lookup
- availability summary endpoint

### ESP32 firmware

- ultrasonic slot sensing
- IR-assisted gate logic
- servo gate control
- temperature and gas safety telemetry
- Firebase sync for slot and analytics updates

## Prerequisites

- Flutter SDK 3.10 or newer
- Python 3.10 or newer
- ESP32 development environment if you want to flash the hardware firmware
- A Firebase Realtime Database project

## Backend setup

1. Open the `server/` folder.
2. Create a virtual environment and install dependencies:

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

3. Make sure Firebase credentials are available locally. The server looks for:

- `server/firebase_credentials.json`
- or Firebase values in environment variables

4. Start the server:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### Backend endpoints

- `GET /health` - checks whether Firebase is connected
- `GET /sensors?limit=100&skip=0` - returns parking slot data
- `GET /sensors/latest` - returns the newest slot record
- `GET /sensors/{slot_id}` - returns a single slot record
- `GET /sensors/availability/summary` - returns total, free, occupied, and availability rate

## Flutter app setup

1. Open the `smartpark/` folder.
2. Get dependencies:

```bash
flutter pub get
```

3. Run the app and point it at your backend if needed:

```bash
flutter run --dart-define=API_BASE_URL=http://localhost:8000
```

If you are running the backend on another machine, replace `localhost` with that machine's LAN IP.

## ESP32 firmware

The hardware sketch lives at `Hardware/smaerparking/smartparking.ino`.

It is configured for:

- multiple ultrasonic slot sensors
- one IR sensor for gate logic
- a servo motor for the barrier
- DHT11 and MQ-2 safety monitoring

Before flashing, update the Wi-Fi credentials and Firebase database URL in the sketch to match your environment.

## Configuration notes

- Keep Firebase credential files out of Git. The repository `.gitignore` already excludes the local credential files used by the server.
- The Flutter app stores the API base URL locally so you do not need to re-enter it on every launch.
- For Android devices, use a reachable LAN IP for the backend instead of `localhost`.

## Development tips

- Run the backend first, then launch the Flutter app.
- If the app shows a connection error, verify the API base URL and that port `8000` is reachable.
- If Firebase data is missing, confirm the database path matches the firmware output under `slots/`.

## License

No license has been specified yet.