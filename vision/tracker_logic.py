"""Lightweight object approach tracking for monocular camera detections.

This module intentionally avoids heavy trackers. For assistive alerts, the core
signal is often enough: if an object's bounding box area grows consistently near
the center of the frame, it is likely getting closer.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from time import monotonic
from typing import Iterable


@dataclass(frozen=True)
class Detection:
    """A normalized detector output used by the tracker.

    bbox_xyxy is in pixel coordinates: [x1, y1, x2, y2].
    """

    label: str
    confidence: float
    bbox_xyxy: tuple[float, float, float, float]


@dataclass
class TrackState:
    """State for one approximate object track."""

    track_id: int
    label: str
    bbox_xyxy: tuple[float, float, float, float]
    confidence: float
    last_seen: float
    area_history: list[float] = field(default_factory=list)
    center_history: list[tuple[float, float]] = field(default_factory=list)


@dataclass(frozen=True)
class ApproachAlert:
    """A high-level alert emitted when an object appears to be approaching."""

    track_id: int
    label: str
    confidence: float
    growth_ratio: float
    direction: str
    message: str


def bbox_area(bbox_xyxy: tuple[float, float, float, float]) -> float:
    x1, y1, x2, y2 = bbox_xyxy
    return max(0.0, x2 - x1) * max(0.0, y2 - y1)


def bbox_center(bbox_xyxy: tuple[float, float, float, float]) -> tuple[float, float]:
    x1, y1, x2, y2 = bbox_xyxy
    return ((x1 + x2) / 2.0, (y1 + y2) / 2.0)


def iou(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> float:
    ax1, ay1, ax2, ay2 = a
    bx1, by1, bx2, by2 = b
    ix1, iy1 = max(ax1, bx1), max(ay1, by1)
    ix2, iy2 = min(ax2, bx2), min(ay2, by2)
    intersection = max(0.0, ix2 - ix1) * max(0.0, iy2 - iy1)
    union = bbox_area(a) + bbox_area(b) - intersection
    return intersection / union if union > 0 else 0.0


def horizontal_direction(center_x: float, frame_width: int) -> str:
    """Convert an x position into left/center/right guidance."""

    if center_x < frame_width * 0.35:
        return "left"
    if center_x > frame_width * 0.65:
        return "right"
    return "center"


class ApproachTracker:
    """Track boxes by IoU and alert when a track's box area grows over time."""

    def __init__(
        self,
        *,
        min_iou: float = 0.25,
        max_track_age_seconds: float = 1.0,
        history_size: int = 5,
        min_growth_ratio: float = 1.35,
        center_band_only: bool = False,
    ) -> None:
        self.min_iou = min_iou
        self.max_track_age_seconds = max_track_age_seconds
        self.history_size = history_size
        self.min_growth_ratio = min_growth_ratio
        self.center_band_only = center_band_only
        self._tracks: dict[int, TrackState] = {}
        self._next_track_id = 1

    def update(
        self,
        detections: Iterable[Detection],
        *,
        frame_width: int,
        now: float | None = None,
    ) -> list[ApproachAlert]:
        """Update tracks with a new frame and return approach alerts."""

        timestamp = monotonic() if now is None else now
        self._expire_old_tracks(timestamp)

        alerts: list[ApproachAlert] = []
        for detection in detections:
            track = self._match_or_create_track(detection, timestamp)
            area = bbox_area(detection.bbox_xyxy)
            center = bbox_center(detection.bbox_xyxy)

            track.bbox_xyxy = detection.bbox_xyxy
            track.confidence = detection.confidence
            track.last_seen = timestamp
            track.area_history.append(area)
            track.center_history.append(center)
            del track.area_history[:-self.history_size]
            del track.center_history[:-self.history_size]

            alert = self._build_alert_if_approaching(track, frame_width)
            if alert:
                alerts.append(alert)

        return alerts

    def _match_or_create_track(self, detection: Detection, timestamp: float) -> TrackState:
        best_track: TrackState | None = None
        best_iou = 0.0

        for track in self._tracks.values():
            if track.label != detection.label:
                continue
            score = iou(track.bbox_xyxy, detection.bbox_xyxy)
            if score > best_iou:
                best_iou = score
                best_track = track

        if best_track and best_iou >= self.min_iou:
            return best_track

        track_id = self._next_track_id
        self._next_track_id += 1
        track = TrackState(
            track_id=track_id,
            label=detection.label,
            bbox_xyxy=detection.bbox_xyxy,
            confidence=detection.confidence,
            last_seen=timestamp,
        )
        self._tracks[track_id] = track
        return track

    def _build_alert_if_approaching(
        self,
        track: TrackState,
        frame_width: int,
    ) -> ApproachAlert | None:
        if len(track.area_history) < 3:
            return None

        first_area = max(track.area_history[0], 1.0)
        latest_area = track.area_history[-1]
        growth_ratio = latest_area / first_area
        center_x, _ = track.center_history[-1]
        direction = horizontal_direction(center_x, frame_width)

        # For very noisy scenes, center_band_only reduces alerts to the walking path.
        if self.center_band_only and direction != "center":
            return None

        is_monotonic_enough = track.area_history[-1] > track.area_history[-2] > track.area_history[-3]
        if growth_ratio < self.min_growth_ratio or not is_monotonic_enough:
            return None

        return ApproachAlert(
            track_id=track.track_id,
            label=track.label,
            confidence=track.confidence,
            growth_ratio=round(growth_ratio, 2),
            direction=direction,
            message=f"{track.label} approaching from {direction}",
        )

    def _expire_old_tracks(self, timestamp: float) -> None:
        expired = [
            track_id
            for track_id, track in self._tracks.items()
            if timestamp - track.last_seen > self.max_track_age_seconds
        ]
        for track_id in expired:
            del self._tracks[track_id]

