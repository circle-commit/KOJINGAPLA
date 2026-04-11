from fastapi import FastAPI, File, UploadFile
import uvicorn

app = FastAPI()

@app.post("/analyze")
async def analyze_image(file: UploadFile = File(...)):
    contents = await file.read()

    result = {
        "status": "success",
        "detected_objects": [
            {"label": "볼라드", "distance": "1.5m", "direction": "center"},
            {"label": "전동 킥보드", "distance": "2.0m", "direction": "left"}
        ],
        "voice_guide": "전방 1.5미터에 볼라드가 있습니다. 왼쪽으로 우회하세요."
    }

    return result

if __name__ == "__main__":
    uvicorn.run(app, host='0.0.0.0', port=8000)