from __future__ import annotations

from typing import Any

from services.vision_service import VisionModelUnavailableError, detect_objects


_VEHICLE_LABELS = {"car", "truck", "bus", "motorcycle", "bicycle", "scooter"}
_PEDESTRIAN_LABELS = {"person", "wheelchair", "stroller"}
_OBSTACLE_LABELS = {"pole", "bollard", "bench", "movable_signage"}

_POSITION_KO = {
    "left": "왼쪽",
    "center": "정면",
    "right": "오른쪽",
}

_OBJECT_KO = {
    "person": "사람",
    "wheelchair": "휠체어",
    "stroller": "유모차",
}


def _priority_group(label: str) -> int:
    if label in _VEHICLE_LABELS:
        return 0
    if label in _PEDESTRIAN_LABELS:
        return 1
    if label in _OBSTACLE_LABELS:
        return 2
    return 3


def _position_priority(position: str) -> int:
    if position == "center":
        return 0
    if position == "right":
        return 1
    if position == "left":
        return 2
    return 3


def _sort_detection_key(detection: dict[str, Any]) -> tuple[int, int, float, float]:
    return (
        _priority_group(str(detection.get("label", ""))),
        _position_priority(str(detection.get("position", ""))),
        -float(detection.get("area_ratio", 0.0)),
        -float(detection.get("confidence", 0.0)),
    )


def prioritize_detections(detections: list[dict]) -> list[dict]:
    """Sort detections by safety priority, position risk, size, then confidence."""

    return sorted(detections, key=_sort_detection_key)


def build_guidance_message(detections: list[dict]) -> str:
    prioritized = prioritize_detections(detections)
    if not prioritized:
        return "전방에 감지된 위험 요소가 없습니다."

    primary = prioritized[0]
    label = str(primary.get("label", ""))
    position = _POSITION_KO.get(str(primary.get("position", "center")), "정면")

    if label in _VEHICLE_LABELS:
        return f"{position}에 차량이 있습니다."

    if label in _PEDESTRIAN_LABELS:
        object_name = _OBJECT_KO.get(label, "사람")
        return f"{position}에 {object_name}이 있습니다."

    if label in _OBSTACLE_LABELS:
        return f"{position}에 장애물이 있습니다. 조심하세요."

    return f"{position}에 장애물이 있습니다. 조심하세요."


def analyze_safety_scene(image: bytes | bytearray | memoryview | Any) -> dict:
    try:
        detections = detect_objects(image)
    except (VisionModelUnavailableError, ValueError, TypeError) as exc:
        return {
            "status": "error",
            "mode": "live",
            "detected_objects": [],
            "voice_guide": "비전 모델을 사용할 수 없습니다.",
            "detail": str(exc),
        }

    prioritized = prioritize_detections(detections)

    return {
        "status": "success",
        "mode": "live",
        "detected_objects": prioritized,
        "voice_guide": build_guidance_message(prioritized),
    }
