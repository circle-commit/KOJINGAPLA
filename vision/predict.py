"""Fast CPU inference helpers and CLI for a trained YOLOv8n model.

Run from the repository root:
    python -m vision.predict --source path/to/image_or_folder
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from ultralytics import YOLO

from vision.tracker_logic import ApproachTracker, Detection


DEFAULT_WEIGHTS = Path("runs/sidewalk/yolov8n_sidewalk/weights/best.pt")


@dataclass(frozen=True)
class Prediction:
    label: str
    confidence: float
    bbox_xyxy: tuple[float, float, float, float]


@dataclass(frozen=True)
class FramePrediction:
    predictions: list[Prediction]
    width: int
    height: int


class SidewalkYoloDetector:
    """Reusable detector for CLI scripts and the FastAPI backend."""

    def __init__(
        self,
        weights_path: str | Path = DEFAULT_WEIGHTS,
        *,
        imgsz: int = 416,
        conf: float = 0.35,
        iou: float = 0.5,
        max_det: int = 20,
    ) -> None:
        weights = Path(weights_path)
        if not weights.exists():
            raise FileNotFoundError(f"YOLO checkpoint not found: {weights}")

        self.model = YOLO(str(weights))
        self.imgsz = imgsz
        self.conf = conf
        self.iou = iou
        self.max_det = max_det

        # OpenCV CPU optimizations help most on Ubuntu CPU-only inference.
        cv2.setUseOptimized(True)
        cv2.setNumThreads(2)

        # Fusing Conv+BatchNorm layers can reduce inference overhead.
        try:
            self.model.fuse()
        except Exception:
            pass

    def predict_array(self, image_bgr: np.ndarray) -> list[Prediction]:
        """Run inference on an OpenCV BGR image."""

        results = self.model.predict(
            source=image_bgr,
            imgsz=self.imgsz,
            conf=self.conf,
            iou=self.iou,
            max_det=self.max_det,
            device="cpu",
            half=False,
            verbose=False,
        )
        return self._parse_result(results[0])

    def predict_bytes(self, image_bytes: bytes) -> list[Prediction]:
        """Decode an uploaded JPEG/PNG payload and run inference."""

        image_bgr = self.decode_image_bytes(image_bytes)
        return self.predict_array(image_bgr)

    def predict_bytes_with_shape(self, image_bytes: bytes) -> FramePrediction:
        """Run inference and return frame dimensions for downstream tracking."""

        image_bgr = self.decode_image_bytes(image_bytes)
        height, width = image_bgr.shape[:2]
        return FramePrediction(
            predictions=self.predict_array(image_bgr),
            width=int(width),
            height=int(height),
        )

    @staticmethod
    def decode_image_bytes(image_bytes: bytes) -> np.ndarray:
        """Decode uploaded image bytes into an OpenCV BGR frame."""

        if not image_bytes:
            raise ValueError("Image payload is empty.")
        encoded = np.frombuffer(image_bytes, dtype=np.uint8)
        image_bgr = cv2.imdecode(encoded, cv2.IMREAD_COLOR)
        if image_bgr is None:
            raise ValueError("Could not decode image bytes.")
        return image_bgr

    def _parse_result(self, result: Any) -> list[Prediction]:
        names = result.names
        predictions: list[Prediction] = []

        if result.boxes is None:
            return predictions

        for box in result.boxes:
            class_id = int(box.cls[0].item())
            confidence = float(box.conf[0].item())
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            predictions.append(
                Prediction(
                    label=str(names[class_id]),
                    confidence=round(confidence, 4),
                    bbox_xyxy=(float(x1), float(y1), float(x2), float(y2)),
                )
            )
        return predictions


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run CPU YOLOv8n sidewalk inference.")
    parser.add_argument("--weights", type=Path, default=DEFAULT_WEIGHTS, help="Path to best.pt.")
    parser.add_argument("--source", required=True, help="Image, video, webcam index, or folder.")
    parser.add_argument("--imgsz", type=int, default=416, help="Smaller values are faster on CPU.")
    parser.add_argument("--conf", type=float, default=0.35, help="Default alert threshold.")
    parser.add_argument("--iou", type=float, default=0.5, help="NMS IoU threshold.")
    parser.add_argument("--max-det", type=int, default=20, help="Limit detections per frame.")
    parser.add_argument("--save", action="store_true", help="Save annotated outputs.")
    parser.add_argument("--track-approach", action="store_true", help="Print approach alerts for video/webcam.")
    return parser.parse_args()


def predict_cli() -> None:
    args = parse_args()
    detector = SidewalkYoloDetector(
        args.weights,
        imgsz=args.imgsz,
        conf=args.conf,
        iou=args.iou,
        max_det=args.max_det,
    )

    if args.track_approach:
        run_video_with_approach_alerts(detector, args.source)
        return

    # The direct Ultralytics call is convenient for files/folders and supports saving
    # annotated images without reimplementing rendering.
    results = detector.model.predict(
        source=args.source,
        imgsz=args.imgsz,
        conf=args.conf,
        iou=args.iou,
        max_det=args.max_det,
        device="cpu",
        half=False,
        save=args.save,
        verbose=True,
    )
    for result in results:
        parsed = detector._parse_result(result)
        print([asdict(prediction) for prediction in parsed])


def run_video_with_approach_alerts(detector: SidewalkYoloDetector, source: str) -> None:
    """Read frames with OpenCV and print approach alerts.

    Use this for webcam/video streams. For still images, approach cannot be inferred
    because there is no history.
    """

    capture_source: int | str = int(source) if source.isdigit() else source
    cap = cv2.VideoCapture(capture_source)
    if not cap.isOpened():
        raise RuntimeError(f"Could not open video source: {source}")

    tracker = ApproachTracker(min_growth_ratio=1.35, center_band_only=False)

    while True:
        ok, frame = cap.read()
        if not ok:
            break

        predictions = detector.predict_array(frame)
        detections = [
            Detection(pred.label, pred.confidence, pred.bbox_xyxy)
            for pred in predictions
        ]
        alerts = tracker.update(detections, frame_width=frame.shape[1])
        for alert in alerts:
            print(asdict(alert))

    cap.release()


if __name__ == "__main__":
    predict_cli()
