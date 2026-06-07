import sys
import unittest
from pathlib import Path


BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.append(str(BACKEND_ROOT))

from services.guidance_message_service import (  # noqa: E402
    GuidanceEventTracker,
    enrich_and_prioritize_detections,
)


def detection(label: str, confidence: float = 0.8) -> list[dict]:
    return enrich_and_prioritize_detections(
        [
            {
                "label": label,
                "confidence": confidence,
                "bbox_xyxy": [100, 100, 300, 400],
                "position": "center",
                "area_ratio": 0.05,
                "vertical_ratio": 0.7,
                "approaching": False,
            }
        ],
        {},
    )


def tracker() -> GuidanceEventTracker:
    return GuidanceEventTracker(
        global_cooldown_seconds=0,
        object_cooldown_seconds=0,
        situation_cooldown_seconds=0,
        signature_cooldown_seconds=0,
    )


class GuidanceTemporalConfidenceTest(unittest.TestCase):
    def test_default_objects_require_two_speech_eligible_frames(self) -> None:
        subject = tracker()

        self.assertEqual(subject.choose_events(detection("person")), [])
        self.assertEqual(len(subject.choose_events(detection("person"))), 1)

    def test_noisy_objects_require_three_speech_eligible_frames(self) -> None:
        subject = tracker()

        self.assertEqual(subject.choose_events(detection("pole")), [])
        self.assertEqual(subject.choose_events(detection("pole")), [])
        self.assertEqual(len(subject.choose_events(detection("pole"))), 1)

    def test_low_confidence_noisy_objects_do_not_count_toward_confirmation(self) -> None:
        subject = tracker()

        for _ in range(3):
            self.assertEqual(subject.choose_events(detection("pole", confidence=0.4)), [])

        self.assertEqual(subject.choose_events(detection("pole", confidence=0.8)), [])
        self.assertEqual(subject.choose_events(detection("pole", confidence=0.8)), [])
        self.assertEqual(len(subject.choose_events(detection("pole", confidence=0.8))), 1)

    def test_immediate_risk_objects_can_speak_on_first_frame(self) -> None:
        subject = tracker()

        self.assertEqual(len(subject.choose_events(detection("car"))), 1)


if __name__ == "__main__":
    unittest.main()
