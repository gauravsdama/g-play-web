from __future__ import annotations

import os
from pathlib import Path

APP_NAME = "vantabeat"

BASE_DIR = Path(__file__).resolve().parents[3]


def _env_path(name: str, default: Path) -> Path:
    return Path(os.environ.get(name) or default)


LIBRARY_DIR = _env_path("VANTABEAT_LIBRARY_DIR", BASE_DIR / "library")
EDITS_DIR = _env_path("VANTABEAT_EDITED_DIR", BASE_DIR / "edited")
PLAYLISTS_DIR = _env_path("VANTABEAT_PLAYLISTS_DIR", BASE_DIR / "playlists")
LOGS_DIR = _env_path("VANTABEAT_LOGS_DIR", BASE_DIR / "logs")

API_TOKEN = os.environ.get("VANTABEAT_API_TOKEN")
YTDLP_COOKIES = os.environ.get("VANTABEAT_YTDLP_COOKIES")
YTDLP_COOKIES_FROM_BROWSER = os.environ.get("VANTABEAT_YTDLP_COOKIES_FROM_BROWSER")
PROCESSING_THREADS = max(1, int(os.environ.get("VANTABEAT_PROCESSING_THREADS") or (os.cpu_count() or 1)))
DOWNLOAD_FRAGMENT_WORKERS = max(1, int(os.environ.get("VANTABEAT_DOWNLOAD_FRAGMENT_WORKERS") or (PROCESSING_THREADS * 2)))

AUDIO_EXTENSIONS = {".aac", ".flac", ".m4a", ".mp3", ".ogg", ".opus", ".wav", ".webm"}


def ensure_runtime_dirs() -> None:
    for path in [LIBRARY_DIR, EDITS_DIR, PLAYLISTS_DIR, LOGS_DIR]:
        path.mkdir(parents=True, exist_ok=True)
