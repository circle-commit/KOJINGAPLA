from services.safety_service import analyze_safety_scene


def analyze_live_scene(image_bytes: bytes) -> dict:
    return analyze_safety_scene(image_bytes)
