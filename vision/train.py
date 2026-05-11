"""Train a YOLOv8n sidewalk object detector with Ultralytics.

Run from the repository root:
    python -m vision.train --data datasets/yolo_sidewalk/data.yaml
"""

from __future__ import annotations

import argparse
from pathlib import Path

from ultralytics import YOLO


DEFAULT_DATA = Path("datasets/yolo_sidewalk/data.yaml")
DEFAULT_PROJECT = Path("runs/sidewalk")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train YOLOv8n on the sidewalk dataset.")
    parser.add_argument("--data", type=Path, default=DEFAULT_DATA, help="Path to YOLO data.yaml.")
    parser.add_argument("--model", default="yolov8n.pt", help="Base Ultralytics model checkpoint.")
    parser.add_argument("--epochs", type=int, default=80, help="Training epochs.")
    parser.add_argument("--imgsz", type=int, default=640, help="Square training image size.")
    parser.add_argument("--batch", type=int, default=16, help="Batch size. Lower this if RAM is limited.")
    parser.add_argument("--workers", type=int, default=4, help="Dataloader workers.")
    parser.add_argument("--project", type=Path, default=DEFAULT_PROJECT, help="Output directory.")
    parser.add_argument("--name", default="yolov8n_sidewalk", help="Run name under project.")
    parser.add_argument("--patience", type=int, default=20, help="Early stopping patience.")
    parser.add_argument("--seed", type=int, default=42, help="Reproducibility seed.")
    return parser.parse_args()


def train() -> None:
    args = parse_args()
    data_path = args.data.resolve()

    if not data_path.exists():
        raise FileNotFoundError(f"Dataset config not found: {data_path}")

    model = YOLO(args.model)

    # CPU training is slower than GPU training, so the defaults keep the model small
    # and enable early stopping. If a CUDA GPU is later available, change device to 0.
    model.train(
        data=str(data_path),
        epochs=args.epochs,
        imgsz=args.imgsz,
        batch=args.batch,
        workers=args.workers,
        device="cpu",
        project=str(args.project),
        name=args.name,
        patience=args.patience,
        seed=args.seed,
        pretrained=True,
        cache=False,
        plots=True,
        val=True,
        amp=False,
    )

    best_path = args.project / args.name / "weights" / "best.pt"
    print(f"Training complete. Best checkpoint should be at: {best_path}")


if __name__ == "__main__":
    train()

