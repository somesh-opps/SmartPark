# smartpark

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Python Sensor Server (MongoDB Atlas)

This workspace now includes a Python API server in `server/` that reads sensor data from MongoDB Atlas.

### 1. Configure environment

Copy `server/.env.example` to `server/.env`, then set your values:

- `MONGODB_URI`
- `MONGODB_DB`
- `MONGODB_COLLECTION`

### 2. Install dependencies

```bash
cd server
pip install -r requirements.txt
```

### 3. Start the server

```bash
cd server
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### 3.1 Run Flutter app against backend

The app polls the backend every 3 seconds. Set the API URL with a dart define:

```bash
flutter run --dart-define=API_BASE_URL=http://localhost:8000
```

For Android emulator, use:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

### 4. API endpoints

- `GET /health` - checks MongoDB connectivity
- `GET /sensors?limit=100&skip=0&device_id=<optional>` - reads sensor documents
- `GET /sensors/latest?device_id=<optional>` - latest sensor document
