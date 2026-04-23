from core.ocr_engine import extract_text


def analyze_text_scene(image_bytes: bytes) -> dict:
    detected_text = extract_text(image_bytes).strip()

    if detected_text:
        voice_guide = (
            "Text Description mode. "
            f"I found text that says: {detected_text}"
        )
    else:
        voice_guide = (
            "Text Description mode. "
            "I could not find readable text in the current frame."
        )

    return {
        "status": "success",
        "mode": "text",
        "detected_text": detected_text,
        "voice_guide": voice_guide,
    }
