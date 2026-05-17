from __future__ import annotations

import os
from pathlib import Path


BACKEND_DIR = Path(__file__).resolve().parent
PADDLEX_CACHE_DIR = BACKEND_DIR / ".paddlex"
MPLCONFIG_DIR = BACKEND_DIR / ".matplotlib"


def configure_ocr_environment() -> None:
    """Configure writable runtime paths before PaddleOCR/PaddleX import."""
    os.environ.setdefault("PADDLE_PDX_CACHE_HOME", str(PADDLEX_CACHE_DIR))
    os.environ.setdefault("PADDLE_PDX_ENABLE_MKLDNN_BYDEFAULT", "False")
    os.environ.setdefault("MPLCONFIGDIR", str(MPLCONFIG_DIR))

    PADDLEX_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    MPLCONFIG_DIR.mkdir(parents=True, exist_ok=True)
