<div align="center">

<h1>🅿️ SmartPark</h1>

<p><strong>Real-time smart parking — from hardware to your pocket.</strong></p>

[![Flutter](https://img.shields.io/badge/Flutter-3.10+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.100+-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Firebase](https://img.shields.io/badge/Firebase-Realtime_DB-FFCA28?logo=firebase&logoColor=black)](https://firebase.google.com)
[![ESP32](https://img.shields.io/badge/ESP32-Firmware-E7352C?logo=espressif&logoColor=white)](https://www.espressif.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

## ✨ Overview

SmartPark is a full-stack IoT parking system that gives you **live slot availability** across three tightly integrated layers:

```
ESP32 Sensors  ──▶  Firebase Realtime DB  ──▶  FastAPI Server  ──▶  Flutter App
```

| Layer | What it does | Location |
|---|---|---|
| 🔌 **Hardware** | Reads sensors, controls gate, sends telemetry | `Hardware/smaerparking/smartparking.ino` |
| ⚡ **Backend** | Serves Firebase data via REST API | `server/main.py` |
| 📱 **App** | Live dashboard with auto-refresh | `smartpark/lib/main.dart` |

---

## 🚀 Quick Start

**Prerequisites:** Flutter SDK ≥ 3.10 · Python ≥ 3.10 · Firebase project · *(optional)* ESP32 toolchain

### 1 — Backend
```bash
cd server
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```
> Place your `firebase_credentials.json` in `server/` or export Firebase values as env vars.

### 2 — Flutter App
```bash
cd smartpark
flutter pub get
flutter run --dart-define=API_BASE_URL=http://<YOUR_LAN_IP>:8000
```

### 3 — ESP32 *(optional)*
Update Wi-Fi credentials and Firebase URL in the `.ino` sketch, then flash.

---

## 🛠 API Endpoints

| Method | Route | Description |
|---|---|---|
| `GET` | `/health` | Firebase connection status |
| `GET` | `/sensors` | All slot records *(paginated)* |
| `GET` | `/sensors/latest` | Newest slot record |
| `GET` | `/sensors/{id}` | Single slot lookup |
| `GET` | `/sensors/availability/summary` | Free / occupied counts |

---

## ⚙️ Hardware Capabilities

- **Ultrasonic** slot occupancy sensing
- **IR** gate trigger logic + **servo** barrier control
- **DHT11** temperature & **MQ-2** gas safety monitoring
- Firebase sync for real-time analytics

---

## 📝 Notes

- 🔒 Never commit `firebase_credentials.json` — it's already in `.gitignore`
- 📡 On Android devices, use your machine's **LAN IP**, not `localhost`
- 🗂 Firebase slot data lives under the `slots/` path in your Realtime DB

---

## 📄 License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for details.