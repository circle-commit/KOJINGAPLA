from __future__ import annotations

from typing import Any

from services.guidance_message_service import build_guidance, enrich_and_prioritize_detections
from services.vision_service import KOREAN_LABELS, VisionModelUnavailableError, detect_objects


def prioritize_detections(detections: list[dict]) -> list[dict]:
    """Attach safety metadata and sort by live-guidance priority."""

    return enrich_and_prioritize_detections(detections, KOREAN_LABELS)


def build_guidance_message(detections: list[dict]) -> str:
    """Backward-compatible helper for callers that only need speech text."""

    prioritized = prioritize_detections(detections)
    return str(build_guidance(prioritized)["voice_guide"])


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
            "risk_level": "low",
            "selected_detection": None,
            "voice_guide": "비전 모델을 사용할 수 없습니다.",
            "detail": str(exc),
        }

    prioritized = prioritize_detections(detections)
    guidance = build_guidance(prioritized)

    return {
        "status": "success",
        "mode": "live",
        "voice_guide": guidance["voice_guide"],
        "warnings": guidance["warnings"],
        "risk_level": guidance["risk_level"],
        "selected_detection": guidance["selected_detection"],
        "detections": prioritized,
        "detected_objects": prioritized,
    }
