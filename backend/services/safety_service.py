from __future__ import annotations

import time
import threading
from typing import Any

from services.vision_service import KOREAN_LABELS, VisionModelUnavailableError, detect_objects


_HIGHEST_RISK = {"car", "truck", "bus"}
_HIGH_RISK = {"motorcycle", "scooter", "bicycle"}
_MEDIUM_HIGH_RISK = {"bollard", "pole", "movable_signage", "tree_trunk"}
_MEDIUM_RISK = {"person", "wheelchair", "stroller"}
_LOWER_RISK = {"bench", "potted_plant", "traffic_sign", "traffic_light"}
_OBSTACLE_LABELS = _MEDIUM_HIGH_RISK | {"bench", "potted_plant", "parking_meter", "stop", "table"}
_APPROACHING_COOLDOWN_SECONDS = 2.5
_MESSAGE_COOLDOWN_SECONDS = 3.0
_LAST_MESSAGE_AT: dict[str, float] = {}
_MESSAGE_LOCK = threading.Lock()

_POSITION_KO = {
    "left": "왼쪽",
    "center": "정면",
    "right": "오른쪽",
}


def _base_risk(label: str) -> int:
    if label in _HIGHEST_RISK:
        return 72
    if label in _HIGH_RISK:
        return 60
    if label in _MEDIUM_HIGH_RISK:
        return 48
    if label in _MEDIUM_RISK:
        return 38
    if label in _LOWER_RISK:
        return 24
    return 30


def _position_bonus(position: str) -> int:
    if position == "center":
        return 16
    if position == "right":
        return 7
    if position == "left":
        return 6
    return 0


def _calculate_risk_score(detection: dict[str, Any]) -> int:
    """Score sidewalk risk from class danger, walking-path position, and closeness.

    Monocular camera frames do not provide true depth. Bounding-box area is used
    as a closeness proxy, and a low box bottom suggests the object is near the
    user's feet or walking path. Center objects get extra weight because they are
    directly ahead of the user.
    """

    label = str(detection.get("label", ""))
    position = str(detection.get("position", ""))
    area_ratio = max(0.0, min(1.0, float(detection.get("area_ratio", 0.0))))
    vertical_ratio = max(0.0, min(1.0, float(detection.get("vertical_ratio", 0.0))))

    score = _base_risk(label)
    score += _position_bonus(position)
    score += min(22, int(area_ratio * 180))
    score += min(12, int(vertical_ratio * 12))

    if detection.get("approaching"):
        score += 22 if position == "center" else 10

    return max(0, min(100, score))


def _sort_detection_key(detection: dict[str, Any]) -> tuple[int, int, float, float]:
    return (
        -int(detection.get("risk_score", 0)),
        0 if detection.get("position") == "center" else 1,
        -float(detection.get("area_ratio", 0.0)),
        -float(detection.get("confidence", 0.0)),
    )


def prioritize_detections(detections: list[dict]) -> list[dict]:
    """Attach risk scores and sort by Korean sidewalk safety priority."""

    scored = []
    for detection in detections:
        normalized = dict(detection)
        normalized["korean_label"] = KOREAN_LABELS.get(
            str(normalized.get("label", "")),
            str(normalized.get("korean_label", normalized.get("label", "장애물"))),
        )
        normalized["risk_score"] = _calculate_risk_score(normalized)
        scored.append(normalized)

    return sorted(scored, key=_sort_detection_key)


def _particle_for(label: str) -> str:
    if not label:
        return "이"

    code = ord(label[-1])
    if 0xAC00 <= code <= 0xD7A3:
        return "이" if (code - 0xAC00) % 28 else "가"

    return "이"


def _build_detection_message(detection: dict[str, Any]) -> str:
    label = str(detection.get("label", ""))
    korean_label = str(detection.get("korean_label") or KOREAN_LABELS.get(label, "장애물"))
    position = str(detection.get("position", "center"))
    position_ko = _POSITION_KO.get(position, "정면")

    if detection.get("approaching") and position == "center":
        return f"정면의 {korean_label}{_particle_for(korean_label)} 가까워지고 있습니다. 조심하세요."

    if label in _HIGHEST_RISK and position == "center":
        return f"정면에 {korean_label}{_particle_for(korean_label)} 있습니다. 주의하세요."

    if label in _OBSTACLE_LABELS and position == "center":
        return f"정면에 {korean_label}{_particle_for(korean_label)} 있습니다."

    return f"{position_ko}에 {korean_label}{_particle_for(korean_label)} 있습니다."


def _dedupe_messages(messages: list[str]) -> list[str]:
    now = time.monotonic()
    filtered: list[str] = []
    with _MESSAGE_LOCK:
        for message in messages:
            cooldown = (
                _APPROACHING_COOLDOWN_SECONDS
                if "가까워지고 있습니다" in message
                else _MESSAGE_COOLDOWN_SECONDS
            )
            if now - _LAST_MESSAGE_AT.get(message, 0.0) < cooldown:
                continue
            _LAST_MESSAGE_AT[message] = now
            filtered.append(message)
    return filtered


def build_guidance_message(detections: list[dict]) -> str:
    prioritized = prioritize_detections(detections)
    if not prioritized:
        return "전방에 감지된 위험 요소가 없습니다."

    messages = [_build_detection_message(detection) for detection in prioritized[:2]]
    messages = _dedupe_messages(messages)
    if messages:
        return " ".join(messages[:2])

    return ""


def analyze_safety_scene(image: bytes | bytearray | memoryview | Any) -> dict:
    try:
        detections = detect_objects(image)
    except (VisionModelUnavailableError, ValueError, TypeError) as exc:
        return {
            "status": "error",
            "mode": "live",
            "detections": [],
            "detected_objects": [],
            "warnings": ["vision_model_unavailable"],
            "voice_guide": "비전 모델을 사용할 수 없습니다.",
            "detail": str(exc),
        }

    prioritized = prioritize_detections(detections)
    warnings = [
        _build_detection_message(detection)
        for detection in prioritized[:2]
        if int(detection.get("risk_score", 0)) >= 55
    ]

    return {
        "status": "success",
        "mode": "live",
        "detections": prioritized,
        "detected_objects": prioritized,
        "warnings": warnings,
        "voice_guide": build_guidance_message(prioritized),
    }
