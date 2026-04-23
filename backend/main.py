from fastapi import FastAPI, File, Form, UploadFile
import uvicorn

app = FastAPI()


@app.post("/analyze")
async def analyze_image(
    image: UploadFile = File(...),
    mode: str = Form("live"),
):
    await image.read()

    if mode == "text":
        result = {
            "status": "success",
            "mode": mode,
            "detected_text": "Emergency exit on the left. Keep door closed.",
            "voice_guide": "Text Description mode. I found text that says, Emergency exit on the left. Keep door closed.",
        }
    else:
        result = {
            "status": "success",
            "mode": mode,
            "detected_objects": [
                {"label": "bollard", "distance": "1.5m", "direction": "center"},
                {"label": "electric scooter", "distance": "2.0m", "direction": "left"},
            ],
            "voice_guide": "Live Analyzing mode. There is a bollard 1.5 meters ahead. Move slightly to the right.",
        }

    return result


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
