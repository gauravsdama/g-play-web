from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional

from fastapi import HTTPException

from .config import AUDIO_EXTENSIONS, EDITS_DIR, LIBRARY_DIR, PLAYLISTS_DIR


def roots_map() -> Dict[str, Path]:
    return {
        "Library": LIBRARY_DIR,
        "Edited": EDITS_DIR,
        "Playlists": PLAYLISTS_DIR,
    }


def safe_root(root_name: str) -> Path:
    root = roots_map().get(root_name)
    if not root:
        raise HTTPException(status_code=400, detail="Invalid root")
    return root


def safe_resolve(root: Path, rel_path: str) -> Path:
    rel = rel_path.strip("/")
    if not rel:
        return root
    candidate = (root / rel).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid path")
    return candidate


def rel_to_root(path: Path, root: Path) -> str:
    return str(path.resolve().relative_to(root.resolve()))


def list_playlists() -> List[Path]:
    return sorted([path for path in PLAYLISTS_DIR.iterdir() if path.is_dir()], key=lambda path: path.name.lower())


def safe_filename(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9 _-]", "", value).strip()
    cleaned = re.sub(r"\s+", " ", cleaned)
    return cleaned or "track"


def unique_path(base_dir: Path, name: str, suffix: str) -> Path:
    candidate = base_dir / f"{name}{suffix}"
    if not candidate.exists():
        return candidate
    index = 2
    while True:
        candidate = base_dir / f"{name}_{index}{suffix}"
        if not candidate.exists():
            return candidate
        index += 1


def safe_output_audio_path(base_dir: Path, output_name: Optional[str], default_name: str) -> Path:
    incoming = Path(output_name or default_name).name
    suffix = Path(incoming).suffix.lower() or ".mp3"
    if suffix not in AUDIO_EXTENSIONS:
        raise HTTPException(status_code=400, detail="Output file type is not supported")

    stem = safe_filename(Path(incoming).stem)
    candidate = (base_dir / f"{stem}{suffix}").resolve()
    try:
        candidate.relative_to(base_dir.resolve())
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid output name")
    return candidate


def open_folder(target: Path) -> None:
    if sys.platform == "darwin":
        cmd = ["open", str(target)]
    elif sys.platform.startswith("win"):
        cmd = ["explorer", str(target)]
    else:
        cmd = ["xdg-open", str(target)]
    subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
