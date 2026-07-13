from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional
from urllib.error import URLError
from urllib.parse import urlparse
from urllib.request import Request as UrlRequest, urlopen

from .config import AUDIO_EXTENSIONS
from .logging_config import log_error

FEATURE_RE = re.compile(
    r"(?:\(|\[|\s)(?:feat\.?|ft\.?|featuring)\s+([^\)\]\-]+)",
    re.IGNORECASE,
)
REMIX_RE = re.compile(r"[\(\[]([^\)\]]+?)\s+remix[\)\]]", re.IGNORECASE)
BRACKET_SUFFIX_RE = re.compile(
    r"\s*[\[\(](?:free download|download|official audio)[^\]\)]*[\]\)]\s*$",
    re.IGNORECASE,
)
MAX_ARTWORK_BYTES = 15_000_000


def read_sidecar_meta(path: Path) -> Dict[str, Any]:
    meta_path = path.with_suffix(path.suffix + ".meta.json")
    if not meta_path.exists():
        return {}
    try:
        return json.loads(meta_path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def read_full_meta(path: Path) -> Dict[str, Any]:
    meta = read_sidecar_meta(path)
    if not meta:
        return get_track_meta(path)
    inferred = infer_title_artist_from_name(path)
    if not meta.get("title"):
        meta["title"] = inferred.get("title")
    if not meta.get("artist"):
        meta["artist"] = inferred.get("artist")
    meta.setdefault("thumbnail", None)
    meta.setdefault("source", None)
    return meta


def infer_title_artist_from_name(path: Path) -> Dict[str, Optional[str]]:
    stem = path.stem
    stem = re.sub(r"(_gplay_tuned|_vantabeat_tuned|_cut)(_\d+)?$", "", stem, flags=re.IGNORECASE)
    if " - " in stem:
        artist, title = stem.split(" - ", 1)
        return {"title": title.strip(), "artist": artist.strip()}
    return {"title": stem, "artist": None}


def get_track_meta_fast(path: Path) -> Dict[str, Optional[str]]:
    sidecar = read_sidecar_meta(path)
    if sidecar:
        return {
            "title": sidecar.get("title"),
            "artist": sidecar.get("artist"),
            "thumbnail": sidecar.get("thumbnail"),
            "source": sidecar.get("source"),
        }
    inferred = infer_title_artist_from_name(path)
    return {
        "title": inferred.get("title"),
        "artist": inferred.get("artist"),
        "thumbnail": None,
        "source": None,
    }


def read_tags_ffprobe(path: Path) -> Dict[str, Optional[str]]:
    if not shutil.which("ffprobe"):
        return {}
    cmd = [
        "ffprobe",
        "-v",
        "error",
        "-show_entries",
        "format_tags=title,artist",
        "-of",
        "json",
        str(path),
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        return {}
    try:
        data = json.loads(proc.stdout.decode("utf-8", errors="replace"))
    except json.JSONDecodeError:
        return {}
    tags = data.get("format", {}).get("tags", {}) or {}
    return {"title": tags.get("title"), "artist": tags.get("artist")}


def get_track_meta(path: Path) -> Dict[str, Optional[str]]:
    sidecar = read_sidecar_meta(path)
    if sidecar:
        return {
            "title": sidecar.get("title"),
            "artist": sidecar.get("artist"),
            "thumbnail": sidecar.get("thumbnail"),
            "source": sidecar.get("source"),
        }
    tags = read_tags_ffprobe(path)
    if tags.get("title"):
        return {
            "title": tags.get("title"),
            "artist": tags.get("artist"),
            "thumbnail": None,
            "source": None,
        }
    inferred = infer_title_artist_from_name(path)
    return {
        "title": inferred.get("title"),
        "artist": inferred.get("artist"),
        "thumbnail": None,
        "source": None,
    }


def split_people(value: str) -> List[str]:
    return [
        item.strip()
        for item in re.split(r"\s*(?:,|&|\band\b| x |\+)\s*", value, flags=re.IGNORECASE)
        if item.strip()
    ]


def parse_featured_artists(title: str, description: Optional[str] = None) -> List[str]:
    haystack = "\n".join(part for part in [title, description] if part)
    features: List[str] = []
    for match in FEATURE_RE.finditer(haystack):
        for person in split_people(match.group(1)):
            if person not in features:
                features.append(person)
    return features


def parse_remixers(title: str) -> List[str]:
    remixers: List[str] = []
    for match in REMIX_RE.finditer(title):
        for person in split_people(match.group(1)):
            if person not in remixers:
                remixers.append(person)
    return remixers


def clean_track_title(title: str) -> str:
    title = BRACKET_SUFFIX_RE.sub("", title).strip()
    title = FEATURE_RE.sub("", title).strip()
    return re.sub(r"\s{2,}", " ", title)


def best_thumbnail_url(info: Dict[str, Any]) -> Optional[str]:
    thumbnails = [thumb for thumb in info.get("thumbnails", []) if thumb.get("url")]
    if thumbnails:
        preferred = sorted(
            thumbnails,
            key=lambda thumb: (
                thumb.get("preference") or 0,
                thumb.get("width") or 0,
                thumb.get("height") or 0,
            ),
        )
        return preferred[-1]["url"]
    return info.get("thumbnail")


def title_parts(info: Dict[str, Any], fallback_name: str) -> Dict[str, Any]:
    raw_title = info.get("track") or info.get("title") or fallback_name
    uploader = info.get("uploader") or info.get("creator")
    artist = info.get("artist") or info.get("creator")
    track_title = raw_title

    if not artist and " - " in raw_title:
        possible_artist, possible_title = raw_title.split(" - ", 1)
        artist = possible_artist.strip()
        track_title = possible_title.strip()

    return {
        "raw_title": raw_title,
        "title": clean_track_title(track_title),
        "artist": artist or uploader,
        "uploader": uploader,
        "featured_artists": parse_featured_artists(raw_title, info.get("description")),
        "remixers": parse_remixers(raw_title),
    }


def artwork_extension(url: str, content_type: Optional[str]) -> str:
    suffix = Path(url.split("?", 1)[0]).suffix.lower()
    if suffix in {".jpg", ".jpeg", ".png", ".webp"}:
        return ".jpg" if suffix == ".jpeg" else suffix
    if content_type:
        if "png" in content_type:
            return ".png"
        if "webp" in content_type:
            return ".webp"
    return ".jpg"


def download_artwork(info: Dict[str, Any], audio_path: Path) -> Optional[Path]:
    thumbnail_url = best_thumbnail_url(info)
    if not thumbnail_url:
        return None
    parsed = urlparse(thumbnail_url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        log_error("artwork_url_rejected", url=thumbnail_url)
        return None

    request = UrlRequest(thumbnail_url, headers={"User-Agent": "vantabeat/1.0"})
    try:
        # Scheme is restricted before opening the URL.
        with urlopen(request, timeout=20) as response:  # nosec B310
            content_type = response.headers.get("content-type")
            artwork = response.read(MAX_ARTWORK_BYTES + 1)
    except (OSError, URLError) as exc:
        log_error("artwork_download_failed", url=thumbnail_url, error=str(exc))
        return None

    if len(artwork) > MAX_ARTWORK_BYTES:
        log_error("artwork_too_large", url=thumbnail_url, max_bytes=MAX_ARTWORK_BYTES)
        return None

    artwork_path = audio_path.with_suffix(audio_path.suffix + f".artwork{artwork_extension(thumbnail_url, content_type)}")
    try:
        artwork_path.write_bytes(artwork)
    except Exception as exc:
        log_error("artwork_write_failed", path=str(artwork_path), error=str(exc))
        return None
    return artwork_path


def selected_download_path(output_dir: Path, info: Dict[str, Any]) -> Path:
    for item in info.get("requested_downloads") or []:
        filepath = item.get("filepath")
        if filepath:
            path = Path(filepath)
            if path.exists() and path.suffix.lower() in AUDIO_EXTENSIONS:
                return path

    download_id = info.get("id") or "download"
    extractor = info.get("extractor_key") or "*"
    candidates = [
        path
        for path in output_dir.glob(f"{extractor}_{download_id}.*")
        if path.is_file() and path.suffix.lower() in AUDIO_EXTENSIONS
    ]
    if not candidates:
        candidates = [
            path
            for path in output_dir.iterdir()
            if path.is_file() and path.suffix.lower() in AUDIO_EXTENSIONS
        ]
    if candidates:
        return max(candidates, key=lambda path: path.stat().st_mtime)
    raise RuntimeError("Downloaded audio file is missing")
