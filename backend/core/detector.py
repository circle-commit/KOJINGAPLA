def detect_objects(image_bytes: bytes) -> list[dict]:
    # Replace this placeholder with the real object detection pipeline.
    if not image_bytes:
        return []

    return [
        {"label": "bollard", "distance": "1.5 meters", "direction": "center"},
        {"label": "electric scooter", "distance": "2.0 meters", "direction": "left"},
    ]
