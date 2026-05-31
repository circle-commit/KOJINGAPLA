from __future__ import annotations

import os
import tempfile
import threading
from functools import lru_cache
from pathlib import Path
from typing import Any

from ocr_runtime import configure_ocr_environment


_OCR_MODEL_LOCK = threading.Lock()


class OCRUnavailableError(RuntimeError):
    """Raised when the configured OCR backend cannot be used."""


def _env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default

    return value.strip().lower() in {"1", "true", "yes", "on"}


@lru_cache(maxsize=1)
def _load_ocr_model_cached() -> Any:
    configure_ocr_environment()

    try:
        from paddleocr import PaddleOCR
    except ImportError as exc:
        raise OCRUnavailableError(
            "PaddleOCR is not installed. Install paddleocr and paddlepaddle "
            "to enable Text Description mode."
        ) from exc
    except Exception as exc:
        raise OCRUnavailableError(
            "PaddleOCR could not be imported. Make sure the backend is started "
            "from the project virtual environment and the OCR cache path is writable."
        ) from exc

    try:
        # PP-OCRv5 is PaddleOCR's current general OCR generation. PaddleOCR picks
        # the matching detector/recognizer for the installed package version.
        return PaddleOCR(
            lang=os.getenv("OCR_LANG", "korean"),
            use_doc_orientation_classify=_env_bool("OCR_USE_DOC_ORIENTATION", False),
            use_doc_unwarping=_env_bool("OCR_USE_DOC_UNWARPING", False),
            use_textline_orientation=_env_bool("OCR_USE_TEXTLINE_ORIENTATION", False),
        )
    except Exception as exc:
        raise OCRUnavailableError(
            "PaddleOCR could not be initialized. Install the OCR dependencies "
            "and make sure the server can download or read the OCR model files."
        ) from exc


def _load_ocr_model() -> Any:
    with _OCR_MODEL_LOCK:
        return _load_ocr_model_cached()


def _score_to_float(score: Any) -> float:
    try:
        return float(score)
    except (TypeError, ValueError):
        return 0.0


def _first_present(payload: dict[str, Any], keys: tuple[str, ...]) -> Any:
    for key in keys:
        value = payload.get(key)
        if value is not None:
            return value

    return []


def _collect_result_lines(result: Any, min_confidence: float) -> list[tuple[str, float]]:
    lines: list[tuple[str, float]] = []

    if isinstance(result, dict):
        payload = result.get("res", result)
        texts = _first_present(payload, ("rec_texts", "texts"))
        scores = _first_present(payload, ("rec_scores", "scores"))

        for text, score in zip(texts, scores):
            cleaned = str(text).strip()
            confidence = _score_to_float(score)
            if cleaned and confidence >= min_confidence:
                lines.append((cleaned, confidence))

        return lines

    if hasattr(result, "json"):
        json_result = result.json() if callable(result.json) else result.json
        return _collect_result_lines(json_result, min_confidence)

    if hasattr(result, "res"):
        return _collect_result_lines(result.res, min_confidence)

    # PaddleOCR 2.x returns nested entries like:
    # [[box, ("recognized text", confidence)], ...]
    if isinstance(result, (list, tuple)):
        for item in result:
            if isinstance(item, (list, tuple)) and len(item) >= 2:
                candidate = item[1]
                if isinstance(candidate, (list, tuple)) and len(candidate) >= 2:
                    cleaned = str(candidate[0]).strip()
                    confidence = _score_to_float(candidate[1])
                    if cleaned and confidence >= min_confidence:
                        lines.append((cleaned, confidence))
                    continue

            lines.extend(_collect_result_lines(item, min_confidence))

    return lines


def _extract_text(image_bytes: bytes) -> str:
    if not image_bytes:
        return ""

    min_confidence = float(os.getenv("OCR_MIN_CONFIDENCE", "0.50"))
    ocr_model = _load_ocr_model()
    temp_path = ""

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as image_file:
            image_file.write(image_bytes)
            temp_path = image_file.name

        if hasattr(ocr_model, "predict"):
            raw_results = ocr_model.predict(temp_path)
        else:
            raw_results = ocr_model.ocr(temp_path, cls=True)

        lines = _collect_result_lines(raw_results, min_confidence)
        return " ".join(text for text, _confidence in lines)
    finally:
        if temp_path:
            Path(temp_path).unlink(missing_ok=True)


def warm_text_ocr_model() -> None:
    _load_ocr_model()


def get_text_ocr_status() -> dict[str, str | bool]:
    try:
        _load_ocr_model()
    except OCRUnavailableError as exc:
        return {
            "available": False,
            "detail": str(exc),
            "cache_dir": os.environ.get("PADDLE_PDX_CACHE_HOME", ""),
        }

    return {
        "available": True,
        "detail": "PaddleOCR is ready.",
        "cache_dir": os.environ.get("PADDLE_PDX_CACHE_HOME", ""),
    }


def analyze_text_scene(image_bytes: bytes) -> dict:
    try:
        detected_text = _extract_text(image_bytes).strip()
    except OCRUnavailableError as exc:
        return {
            "status": "error",
            "mode": "text",
            "detected_text": "",
            "voice_guide": (
                "문자 읽기 모드입니다. "
                "서버에서 OCR 모델을 사용할 수 없습니다."
            ),
            "detail": str(exc),
        }

    if detected_text:
        voice_guide = (
            "문자 읽기 모드입니다. "
            f"인식된 문자는 다음과 같습니다. {detected_text}"
        )
    else:
        voice_guide = (
            "문자 읽기 모드입니다. "
            "현재 화면에서 읽을 수 있는 문자를 찾지 못했습니다."
        )

    return {
        "status": "success",
        "mode": "text",
        "detected_text": detected_text,
        "voice_guide": voice_guide,
    }
