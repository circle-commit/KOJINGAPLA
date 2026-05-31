# KOJINGAPLA Android

Native Android version of the iOS `Glass` app. It uses CameraX for the camera preview and frame stream, ML Kit Korean text recognition for local OCR target stability checks, Android TextToSpeech for spoken guidance, and the existing FastAPI `/analyze` backend for live guidance and full OCR.

## Run

1. Open `frontend/Android` in Android Studio.
2. Let Android Studio sync Gradle dependencies.
3. Start the backend:

```bash
cd backend
source venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8000
```

4. Update `SERVER_URL` in `app/src/main/java/com/kojingapla/glass/MainActivity.kt` if the backend is not reachable at `http://100.64.174.44:8000/analyze`.
5. Run the `app` configuration on a physical Android device. Camera and vibration features require device hardware.

## Modes

- `Live`: sends a camera frame to the backend every two seconds and speaks the returned navigation guidance.
- `OCR`: uses local text detection to wait for centered, stable text before sending a full OCR request to the backend, then speaks non-duplicate text.
