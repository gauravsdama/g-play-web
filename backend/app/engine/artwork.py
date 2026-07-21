from __future__ import annotations

import json
import os
import shutil
import subprocess
import uuid
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, Optional

from .config import AUDIO_EXTENSIONS
from .logging_config import log_error, log_event
from .metadata import download_artwork, read_sidecar_meta

EMBEDDABLE_AUDIO_EXTENSIONS = {".flac", ".m4a", ".mp3"}
ARTWORK_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
ARTWORK_EXTENSION_ORDER = {".jpg": 0, ".jpeg": 1, ".png": 2, ".webp": 3}


@dataclass(frozen=True)
class ArtworkEmbedResult:
    audio_path: str
    artwork_path: Optional[str]
    embedded: bool
    skipped_reason: Optional[str] = None
    error: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


def sidecar_meta_path(audio_path: Path) -> Path:
    return audio_path.with_suffix(audio_path.suffix + ".meta.json")


def sidecar_artwork_candidates(audio_path: Path) -> Iterable[Path]:
    for candidate in audio_path.parent.iterdir():
        if candidate.name.startswith(audio_path.name + ".artwork.") and candidate.suffix.lower() in ARTWORK_EXTENSIONS:
            yield candidate


def meta_artwork_candidate(audio_path: Path) -> Optional[Path]:
    meta_path = sidecar_meta_path(audio_path)
    if not meta_path.exists():
        return None
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except Exception:
        return None
    artwork = meta.get("artwork")
    if not artwork:
        return None
    path = Path(artwork)
    if path.exists() and path.is_file() and path.suffix.lower() in ARTWORK_EXTENSIONS:
        return path
    return None


def find_artwork_sidecar(audio_path: Path) -> Optional[Path]:
    candidates = list(sidecar_artwork_candidates(audio_path))
    meta_candidate = meta_artwork_candidate(audio_path)
    if meta_candidate:
        candidates.append(meta_candidate)
    if not candidates:
        return None
    return sorted(
        set(candidates),
        key=lambda path: (
            ARTWORK_EXTENSION_ORDER.get(path.suffix.lower(), 99),
            -path.stat().st_mtime,
            path.name,
        ),
    )[0]


def copy_artwork_sidecar(source: Path, dest: Path) -> Optional[Path]:
    artwork_path = find_artwork_sidecar(source)
    if not artwork_path:
        return None
    dest_artwork = dest.with_suffix(dest.suffix + f".artwork{artwork_path.suffix.lower()}")
    shutil.copy2(artwork_path, dest_artwork)
    return dest_artwork


def update_meta_artwork(audio_path: Path, artwork_path: Optional[Path], embedded: bool) -> None:
    meta_path = sidecar_meta_path(audio_path)
    meta = read_sidecar_meta(audio_path)
    if artwork_path:
        meta["artwork"] = str(artwork_path)
    meta["artwork_embedded"] = embedded
    try:
        meta_path.write_text(json.dumps(meta, ensure_ascii=True), encoding="utf-8")
    except Exception as exc:
        log_error("meta_write_failed", path=str(meta_path), error=str(exc))


def ensure_artwork_sidecar(audio_path: Path, download_missing: bool = False) -> Optional[Path]:
    artwork_path = find_artwork_sidecar(audio_path)
    if artwork_path or not download_missing:
        return artwork_path

    meta = read_sidecar_meta(audio_path)
    if not meta.get("thumbnail"):
        return None
    artwork_path = download_artwork(meta, audio_path)
    if artwork_path:
        update_meta_artwork(audio_path, artwork_path, False)
    return artwork_path


def has_embedded_artwork(audio_path: Path) -> bool:
    if not shutil.which("ffprobe"):
        return False
    cmd = [
        "ffprobe",
        "-v",
        "error",
        "-select_streams",
        "v",
        "-show_entries",
        "stream=codec_type,disposition",
        "-of",
        "json",
        str(audio_path),
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        return False
    try:
        data = json.loads(proc.stdout.decode("utf-8", errors="replace"))
    except json.JSONDecodeError:
        return False
    for stream in data.get("streams", []) or []:
        if stream.get("codec_type") == "video":
            return True
    return False


def embed_artwork(audio_path: Path, artwork_path: Optional[Path] = None, force: bool = True) -> ArtworkEmbedResult:
    audio_path = audio_path.resolve()
    artwork_path = (artwork_path or find_artwork_sidecar(audio_path))
    if audio_path.suffix.lower() not in EMBEDDABLE_AUDIO_EXTENSIONS:
        return ArtworkEmbedResult(str(audio_path), str(artwork_path) if artwork_path else None, False, "unsupported_format")
    if not audio_path.exists() or not audio_path.is_file():
        return ArtworkEmbedResult(str(audio_path), str(artwork_path) if artwork_path else None, False, "audio_missing")
    if not artwork_path or not artwork_path.exists() or not artwork_path.is_file():
        return ArtworkEmbedResult(str(audio_path), None, False, "artwork_missing")
    if artwork_path.suffix.lower() not in ARTWORK_EXTENSIONS:
        return ArtworkEmbedResult(str(audio_path), str(artwork_path), False, "unsupported_artwork_format")
    if not force and has_embedded_artwork(audio_path):
        return ArtworkEmbedResult(str(audio_path), str(artwork_path), False, "already_embedded")
    if not shutil.which("ffmpeg"):
        return ArtworkEmbedResult(str(audio_path), str(artwork_path), False, "ffmpeg_missing")

    temp_path = audio_path.with_name(f".{audio_path.name}.artwork-{uuid.uuid4().hex}{audio_path.suffix.lower()}")
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-i",
        str(audio_path),
        "-i",
        str(artwork_path),
        "-map",
        "0:a",
        "-map",
        "1:v:0",
        "-map_metadata",
        "0",
        "-c:a",
        "copy",
        "-c:v",
        "mjpeg",
        "-disposition:v:0",
        "attached_pic",
        "-metadata:s:v",
        "title=Album cover",
        "-metadata:s:v",
        "comment=Cover (front)",
    ]
    if audio_path.suffix.lower() == ".mp3":
        cmd.extend(["-id3v2_version", "3"])
    cmd.append(str(temp_path))

    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if proc.returncode != 0:
            error = proc.stderr.decode("utf-8", errors="replace") or "ffmpeg failed"
            log_error("artwork_embed_failed", file=str(audio_path), artwork=str(artwork_path), error=error)
            return ArtworkEmbedResult(str(audio_path), str(artwork_path), False, error=error)
        if not temp_path.exists() or temp_path.stat().st_size == 0:
            log_error("artwork_embed_failed", file=str(audio_path), artwork=str(artwork_path), error="empty output")
            return ArtworkEmbedResult(str(audio_path), str(artwork_path), False, error="empty output")
        shutil.copystat(audio_path, temp_path, follow_symlinks=False)
        os.replace(temp_path, audio_path)
    finally:
        temp_path.unlink(missing_ok=True)

    log_event("artwork_embedded", file=str(audio_path), artwork=str(artwork_path))
    return ArtworkEmbedResult(str(audio_path), str(artwork_path), True)


def embed_library_artwork(
    library_dir: Path,
    force: bool = True,
    dry_run: bool = False,
    download_missing: bool = False,
) -> Dict[str, Any]:
    results = []
    for audio_path in sorted(library_dir.rglob("*")):
        if not audio_path.is_file() or audio_path.name.startswith("."):
            continue
        if audio_path.suffix.lower() not in AUDIO_EXTENSIONS:
            continue
        artwork_path = find_artwork_sidecar(audio_path)
        if not artwork_path and download_missing and dry_run:
            meta = read_sidecar_meta(audio_path)
            thumbnail = meta.get("thumbnail")
            if thumbnail:
                results.append(
                    ArtworkEmbedResult(str(audio_path), str(thumbnail), False, "dry_run_download_missing").to_dict()
                )
            continue
        if not artwork_path and download_missing:
            artwork_path = ensure_artwork_sidecar(audio_path, download_missing=True)
        if not artwork_path:
            continue
        if dry_run:
            result = ArtworkEmbedResult(str(audio_path), str(artwork_path), False, "dry_run")
        else:
            result = embed_artwork(audio_path, artwork_path, force=force)
            if result.embedded:
                update_meta_artwork(audio_path, artwork_path, True)
        results.append(result.to_dict())

    return {
        "library": str(library_dir),
        "matched": len(results),
        "embedded": sum(1 for item in results if item["embedded"]),
        "skipped": sum(1 for item in results if item["skipped_reason"]),
        "failed": sum(1 for item in results if item["error"]),
        "results": results,
    }
