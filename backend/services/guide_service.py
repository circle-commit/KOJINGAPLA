from core.detector import detect_objects


def analyze_live_scene(image_bytes: bytes) -> dict:
    detected_objects = detect_objects(image_bytes)

    if detected_objects:
        primary_object = detected_objects[0]
        voice_guide = (
            "Live Analyzing mode. "
            f"There is a {primary_object['label']} "
            f"{primary_object['distance']} ahead. "
            f"It is {primary_object['direction']}."
        )
    else:
        voice_guide = (
            "Live Analyzing mode. "
            "I do not detect any immediate obstacles ahead."
        )

    return {
        "status": "success",
        "mode": "live",
        "detected_objects": detected_objects,
        "voice_guide": voice_guide,
    }
