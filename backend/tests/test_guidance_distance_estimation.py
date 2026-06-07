import sys
import unittest
from pathlib import Path


BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.append(str(BACKEND_ROOT))

from services.guidance_message_service import (  # noqa: E402
    _distance_level,
    enrich_and_prioritize_detections,
)


class GuidanceDistanceEstimationTest(unittest.TestCase):
    def test_large_vehicles_need_stronger_evidence_before_close(self) -> None:
        self.assertEqual(_distance_level("car", area_ratio=0.05, vertical_ratio=0.65), "near")
        self.assertEqual(_distance_level("car", area_ratio=0.08, vertical_ratio=0.65), "close")

    def test_small_ground_obstacles_use_lower_frame_position_more_strongly(self) -> None:
        self.assertEqual(_distance_level("bollard", area_ratio=0.011, vertical_ratio=0.61), "close")
        self.assertEqual(_distance_level("bollard", area_ratio=0.011, vertical_ratio=0.43), "near")

    def test_sign_like_objects_are_not_near_until_lower_in_frame(self) -> None:
        self.assertEqual(_distance_level("traffic_sign", area_ratio=0.02, vertical_ratio=0.55), "near")
        self.assertEqual(_distance_level("traffic_sign", area_ratio=0.01, vertical_ratio=0.55), "far")

    def test_front_danger_zone_uses_class_aware_distance(self) -> None:
        detections = enrich_and_prioritize_detections(
            [
                {
                    "label": "car",
                    "confidence": 0.8,
                    "bbox_xyxy": [100, 100, 300, 400],
                    "position": "center",
                    "area_ratio": 0.05,
                    "vertical_ratio": 0.65,
                    "approaching": False,
                },
                {
                    "label": "bollard",
                    "confidence": 0.8,
                    "bbox_xyxy": [100, 100, 300, 400],
                    "position": "center",
                    "area_ratio": 0.011,
                    "vertical_ratio": 0.61,
                    "approaching": False,
                },
            ],
            {},
        )

        danger_by_label = {detection["label"]: detection["front_danger_zone"] for detection in detections}
        self.assertFalse(danger_by_label["car"])
        self.assertTrue(danger_by_label["bollard"])


if __name__ == "__main__":
    unittest.main()
