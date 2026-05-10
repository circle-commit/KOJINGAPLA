import threading

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
import uvicorn

from services.guide_service import analyze_live_scene
from services.text_service import analyze_text_scene, warm_text_ocr_model

app = FastAPI()


@app.on_event("startup")
async def warm_ocr_model_on_startup():
    def warm_model():
        try:
            warm_text_ocr_model()
        except Exception as exc:
            print(f"OCR warm-up skipped: {exc}")

    threading.Thread(target=warm_model, daemon=True).start()


@app.get("/health")
async def health_check():
    return {"status": "ok"}


@app.post("/analyze")
async def analyze_image(
    image: UploadFile = File(...),
    mode: str = Form("live"),
):
    image_bytes = await image.read()

    if not image_bytes:
        raise HTTPException(status_code=400, detail="Image payload is empty.")

    if mode == "text":
        return analyze_text_scene(image_bytes)

    if mode == "live":
        return analyze_live_scene(image_bytes)

    raise HTTPException(status_code=400, detail=f"Unsupported mode: {mode}")


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
