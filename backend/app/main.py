from __future__ import annotations

import json
import logging
import os
import re
import secrets
import shutil
import subprocess
import threading
import time
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
import sys

from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field
from yt_dlp import YoutubeDL

BASE_DIR = Path(__file__).resolve().parents[2]
LIBRARY_DIR = Path(os.environ.get("GPLAY_LIBRARY_DIR", BASE_DIR / "library"))
EDITS_DIR = Path(os.environ.get("GPLAY_EDITED_DIR", BASE_DIR / "edited"))
PLAYLISTS_DIR = Path(os.environ.get("GPLAY_PLAYLISTS_DIR", BASE_DIR / "playlists"))
LOGS_DIR = Path(os.environ.get("GPLAY_LOGS_DIR", BASE_DIR / "logs"))
PARTY_STATE: Dict[str, Any] = {"code": None, "queue": []}
PARTY_LOCK = threading.Lock()
PARTY_SEQ = 0


def generate_party_code() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "".join(secrets.choice(alphabet) for _ in range(6))


def add_party_item(track: Dict[str, Any]) -> Dict[str, Any]:
    global PARTY_SEQ
    with PARTY_LOCK:
        PARTY_SEQ += 1
        item = {"id": str(PARTY_SEQ), "track": track}
        PARTY_STATE["queue"].append(item)
        return item

for path in [LIBRARY_DIR, EDITS_DIR, PLAYLISTS_DIR, LOGS_DIR]:
    path.mkdir(parents=True, exist_ok=True)

LOG_FILE = LOGS_DIR / "g-play-api.log"

logger = logging.getLogger("gplay.api")
logger.setLevel(logging.INFO)

if not logger.handlers:
    formatter = logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")
    file_handler = RotatingFileHandler(LOG_FILE, maxBytes=1_000_000, backupCount=5)
    file_handler.setFormatter(formatter)
    stream_handler = logging.StreamHandler()
    stream_handler.setFormatter(formatter)
    logger.addHandler(file_handler)
    logger.addHandler(stream_handler)

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"] ,
    allow_headers=["*"],
)


class DownloadRequest(BaseModel):
    url: str
    playlist: Optional[str] = None
    quality_kbps: int = 320


class TuneRequest(BaseModel):
    root: str
    path: str
    preamp_db: float = 0.0
    eq_gains: List[float] = Field(default_factory=list)
    spatial_width: float = 0.0
    drc_mode: str = "Off"
    balance: float = 0.0
    limiter_on: bool = True
    preset_name: Optional[str] = None
    output_name: Optional[str] = None


class PlaylistCreateRequest(BaseModel):
    name: str


class PlaylistAddRequest(BaseModel):
    playlist: str
    root: str
    path: str


class RenameRequest(BaseModel):
    root: str
    path: str
    new_name: str


class SaveToLibraryRequest(BaseModel):
    root: str
    path: str


class DeleteRequest(BaseModel):
    root: str
    path: str


class OpenFolderRequest(BaseModel):
    root: str
    path: Optional[str] = None


class InfoRequest(BaseModel):
    url: str


class AudioProfileRequest(BaseModel):
    root: str
    path: str
    min_coverage: float = 0.02


class TrackMetaRequest(BaseModel):
    root: str
    path: str


class CutRange(BaseModel):
    start: float
    end: float


class EditCutsRequest(BaseModel):
    root: str
    path: str
    cuts: List[CutRange]
    output_name: Optional[str] = None


class PartyEnqueueRequest(BaseModel):
    code: str
    url: str
    quality_kbps: int = 320


class PartyQueueRequest(BaseModel):
    code: str


class YtdlpLogger:
    def debug(self, message: str) -> None:
        logger.debug(message)

    def warning(self, message: str) -> None:
        logger.warning(message)

    def error(self, message: str) -> None:
        logger.error(message)


def log_event(message: str, **fields: Any) -> None:
    if fields:
        extra = " ".join([f"{k}={v}" for k, v in fields.items()])
        logger.info(f"{message} | {extra}")
    else:
        logger.info(message)


def log_error(message: str, **fields: Any) -> None:
    if fields:
        extra = " ".join([f"{k}={v}" for k, v in fields.items()])
        logger.error(f"{message} | {extra}")
    else:
        logger.error(message)


@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = time.time()
    try:
        response = await call_next(request)
        elapsed_ms = int((time.time() - start) * 1000)
        if response.status_code >= 400:
            log_error(
                "request_error",
                method=request.method,
                path=request.url.path,
                status=response.status_code,
                ms=elapsed_ms,
            )
        return response
    except Exception as exc:
        elapsed_ms = int((time.time() - start) * 1000)
        log_error(
            "request_error",
            method=request.method,
            path=request.url.path,
            ms=elapsed_ms,
            error=str(exc),
        )
        raise


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


def require_party_code(code: str) -> None:
    active = PARTY_STATE.get("code")
    if not active or code.strip().upper() != active:
        raise HTTPException(status_code=403, detail="Invalid party code")


def list_playlists() -> List[Path]:
    return sorted([p for p in PLAYLISTS_DIR.iterdir() if p.is_dir()], key=lambda p: p.name.lower())


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
    stem = re.sub(r"(_gplay_tuned|_cut)(_\d+)?$", "", stem, flags=re.IGNORECASE)
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


def safe_filename(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9 _-]", "", value).strip()
    cleaned = re.sub(r"\s+", " ", cleaned)
    return cleaned or "track"


def unique_path(base_dir: Path, name: str, suffix: str) -> Path:
    candidate = base_dir / f"{name}{suffix}"
    if not candidate.exists():
        return candidate
    idx = 2
    while True:
        candidate = base_dir / f"{name}_{idx}{suffix}"
        if not candidate.exists():
            return candidate
        idx += 1


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


def decode_audio_mono(path: Path, sample_rate: int) -> np.ndarray:
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        str(path),
        "-vn",
        "-ac",
        "1",
        "-ar",
        str(sample_rate),
        "-f",
        "f32le",
        "pipe:1",
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", errors="replace"))
    data = np.frombuffer(proc.stdout, dtype=np.float32)
    return data


def read_duration_seconds(path: Path) -> float:
    if not shutil.which("ffprobe"):
        raise RuntimeError("ffprobe is required")
    cmd = [
        "ffprobe",
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "json",
        str(path),
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", errors="replace"))
    data = json.loads(proc.stdout.decode("utf-8", errors="replace"))
    duration = float(data.get("format", {}).get("duration") or 0)
    return max(0.0, duration)


def normalize_cuts(cuts: List[CutRange], duration: float) -> List[Tuple[float, float]]:
    normalized: List[Tuple[float, float]] = []
    for cut in cuts:
        start = max(0.0, min(duration, float(cut.start)))
        end = max(0.0, min(duration, float(cut.end)))
        if end <= start:
            continue
        normalized.append((start, end))
    normalized.sort(key=lambda item: item[0])
    merged: List[Tuple[float, float]] = []
    for start, end in normalized:
        if not merged or start > merged[-1][1]:
            merged.append((start, end))
        else:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
    return merged


def build_keep_segments(cuts: List[Tuple[float, float]], duration: float) -> List[Tuple[float, float]]:
    keep: List[Tuple[float, float]] = []
    cursor = 0.0
    for start, end in cuts:
        if start > cursor:
            keep.append((cursor, start))
        cursor = max(cursor, end)
    if cursor < duration:
        keep.append((cursor, duration))
    return [(s, e) for s, e in keep if e > s]


def render_cut_audio(source: Path, dest: Path, segments: List[Tuple[float, float]]) -> None:
    filters: List[str] = []
    labels: List[str] = []
    for idx, (start, end) in enumerate(segments):
        label = f"a{idx}"
        filters.append(
            f"[0:a]atrim=start={start:.3f}:end={end:.3f},asetpts=PTS-STARTPTS[{label}]"
        )
        labels.append(f"[{label}]")
    concat = f"{''.join(labels)}concat=n={len(labels)}:v=0:a=1[out]"
    filter_chain = ";".join(filters + [concat])
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-i",
        str(source),
        "-filter_complex",
        filter_chain,
        "-map",
        "[out]",
        "-f",
        "mp3",
        "-ar",
        "48000",
        "-codec:a",
        "libmp3lame",
        "-b:a",
        "320k",
        str(dest),
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", errors="replace"))


def open_folder(target: Path) -> None:
    if sys.platform == "darwin":
        cmd = ["open", str(target)]
    elif sys.platform.startswith("win"):
        cmd = ["explorer", str(target)]
    else:
        cmd = ["xdg-open", str(target)]
    subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def compute_max_frequency(
    path: Path,
    min_coverage: float = 0.02,
    sample_rate: int = 22050,
    window: int = 2048,
    hop: int = 1024,
) -> Tuple[float, int]:
    samples = decode_audio_mono(path, sample_rate)
    if samples.size < window:
        return float(sample_rate / 2), sample_rate

    window_fn = np.hanning(window).astype(np.float32)
    counts = np.zeros(window // 2 + 1, dtype=np.int32)
    frames = 0

    for idx in range(0, samples.size - window + 1, hop):
        frame = samples[idx : idx + window] * window_fn
        spectrum = np.abs(np.fft.rfft(frame))
        max_mag = spectrum.max()
        if max_mag <= 0:
            continue
        threshold = max_mag * 0.05
        active = spectrum >= threshold
        counts[active] += 1
        frames += 1

    if frames == 0:
        return float(sample_rate / 2), sample_rate

    required = max(1, int(frames * min_coverage))
    valid_bins = np.where(counts >= required)[0]
    if valid_bins.size == 0:
        max_bin = int(window / 2)
    else:
        max_bin = int(valid_bins.max())
    max_freq = max_bin * sample_rate / window
    return float(max_freq), sample_rate


def build_filter_chain(
    preamp_db: float,
    eq_gains: List[float],
    spatial_width: float,
    drc_mode: str,
    balance: float,
    limiter_on: bool,
) -> str:
    filters: List[str] = []
    eq_bands = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    for freq, gain in zip(eq_bands, eq_gains or [0.0] * len(eq_bands)):
        if abs(gain) >= 0.1:
            filters.append(f"equalizer=f={freq}:t=q:w=1:g={gain:.2f}")

    if drc_mode != "Off":
        settings = {
            "Medium": {"threshold": -20, "ratio": 2.5, "attack": 20, "release": 250, "makeup": 3},
            "High": {"threshold": -28, "ratio": 4.0, "attack": 12, "release": 300, "makeup": 6},
        }[drc_mode]
        filters.append(
            "acompressor="
            f"threshold={settings['threshold']}dB:"
            f"ratio={settings['ratio']}:"
            f"attack={settings['attack']}:"
            f"release={settings['release']}:"
            f"makeup={settings['makeup']}"
        )

    if spatial_width > 0:
        crossfeed = min(0.8, 0.1 + spatial_width * 0.7)
        feedback = min(0.9, 0.1 + spatial_width * 0.6)
        drymix = max(0.6, 1.0 - spatial_width * 0.3)
        filters.append(
            "stereowiden="
            f"delay=20:feedback={feedback:.2f}:crossfeed={crossfeed:.2f}:drymix={drymix:.2f}"
        )

    if abs(balance) > 0.01:
        if balance < 0:
            left = 1.0
            right = 1.0 + balance
        else:
            left = 1.0 - balance
            right = 1.0
        filters.append(f"pan=stereo|c0={left:.3f}*c0|c1={right:.3f}*c1")

    if abs(preamp_db) > 0.01:
        filters.append(f"volume={preamp_db:.2f}dB")

    if limiter_on:
        filters.append("alimiter=limit=0.95")

    return ",".join(filters) if filters else "anull"


def process_audio(input_path: Path, output_path: Path, filter_chain: str) -> None:
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-i",
        str(input_path),
        "-af",
        filter_chain,
        "-f",
        "mp3",
        "-ar",
        "48000",
        "-codec:a",
        "libmp3lame",
        "-b:a",
        "320k",
        str(output_path),
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", errors="replace"))


def build_ydl_opts(
    format_value: str,
    cookies_path: Optional[str],
    player_clients: Optional[List[str]] = None,
    use_cookies: bool = True,
    quality_kbps: int = 320,
) -> Dict[str, Any]:
    opts: Dict[str, Any] = {
        "format": format_value,
        "outtmpl": str(LIBRARY_DIR / "%(id)s.%(ext)s"),
        "noplaylist": True,
        "quiet": True,
        "no_warnings": True,
        "retries": 3,
        "fragment_retries": 3,
        "force_ipv4": True,
        "postprocessors": [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": "mp3",
                "preferredquality": str(quality_kbps),
            }
        ],
        "logger": YtdlpLogger(),
    }
    cookies_from_browser = os.environ.get("GPLAY_YTDLP_COOKIES_FROM_BROWSER")
    if use_cookies and cookies_from_browser:
        opts["cookiesfrombrowser"] = cookies_from_browser
    elif cookies_path:
        cookie_path = Path(cookies_path)
        if use_cookies and cookie_path.exists() and cookie_path.is_file():
            opts["cookiefile"] = str(cookie_path)
        else:
            log_error("cookies_invalid", path=cookies_path)
    if not player_clients:
        player_clients = ["web"]
    opts["extractor_args"] = {"youtube": {"player_client": player_clients}}
    if shutil.which("node"):
        opts["js_interpreter"] = "node"
    return opts


def run_download(
    url: str,
    format_value: str,
    cookies_path: Optional[str],
    player_clients: List[str],
    use_cookies: bool,
    quality_kbps: int,
) -> Dict[str, Any]:
    ydl_opts = build_ydl_opts(
        format_value,
        cookies_path,
        player_clients,
        use_cookies,
        quality_kbps,
    )
    with YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url, download=True)
    video_id = info.get("id") or "download"
    path = LIBRARY_DIR / f"{video_id}.mp3"
    if not path.exists() or path.stat().st_size == 0:
        raise RuntimeError("Downloaded file is empty")
    info["__download_path"] = str(path)
    return info


def log_available_formats(
    url: str,
    cookies_path: Optional[str],
    player_clients: List[str],
    use_cookies: bool,
) -> None:
    opts = build_ydl_opts("best", cookies_path, player_clients, use_cookies)
    opts["skip_download"] = True
    opts["quiet"] = True
    try:
        with YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)
    except Exception as exc:
        log_error("format_list_error", url=url, error=str(exc))
        return

    formats = info.get("formats") or []
    audio_only = [
        fmt
        for fmt in formats
        if fmt.get("acodec") not in (None, "none") and fmt.get("vcodec") == "none"
    ]
    summary = []
    for fmt in audio_only[:12]:
        summary.append(
            {
                "id": fmt.get("format_id"),
                "ext": fmt.get("ext"),
                "acodec": fmt.get("acodec"),
                "abr": fmt.get("abr"),
                "tbr": fmt.get("tbr"),
            }
        )
    log_event(
        "format_list",
        url=url,
        total=len(formats),
        audio_only=len(audio_only),
        sample=json.dumps(summary, ensure_ascii=True),
    )


def log_format_list_cli(
    url: str,
    cookies_path: Optional[str],
    player_clients: List[str],
    use_cookies: bool,
) -> None:
    cmd = [
        "yt-dlp",
        "--list-formats",
        "--skip-download",
        "--no-warnings",
        "-q",
        "--extractor-args",
        f"youtube:player_client={','.join(player_clients)}",
    ]
    if use_cookies and cookies_path and Path(cookies_path).is_file():
        cmd += ["--cookies", cookies_path]
    cmd.append(url)
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        log_error(
            "format_list_cli_error",
            url=url,
            error=proc.stderr.decode("utf-8", errors="replace") or "unknown",
        )
        return
    lines = proc.stdout.decode("utf-8", errors="replace").splitlines()
    sample = "\n".join(lines[:30])
    log_event(
        "format_list_cli",
        url=url,
        player_clients=",".join(player_clients),
        sample=sample,
    )


def run_info(
    url: str,
    cookies_path: Optional[str],
    player_clients: List[str],
    use_cookies: bool,
) -> Dict[str, Any]:
    opts = build_ydl_opts("bestaudio/best", cookies_path, player_clients, use_cookies)
    opts["skip_download"] = True
    opts["quiet"] = True
    with YoutubeDL(opts) as ydl:
        return ydl.extract_info(url, download=False)


@app.get("/api/health")
async def health() -> Dict[str, str]:
    return {"status": "ok"}


@app.get("/api/roots")
async def roots() -> Dict[str, List[str]]:
    return {"roots": list(roots_map().keys())}


@app.get("/api/tree")
async def tree(root: str, path: str = "") -> Dict[str, Any]:
    base = safe_root(root)
    target = safe_resolve(base, path)
    if not target.exists() or not target.is_dir():
        raise HTTPException(status_code=404, detail="Folder not found")

    entries = []
    for entry in sorted(target.iterdir(), key=lambda p: (p.is_file(), p.name.lower())):
        if entry.is_dir():
            stats = entry.stat()
            entries.append({
                "name": entry.name,
                "type": "dir",
                "path": str(entry.relative_to(base)),
                "added_at": stats.st_mtime,
            })
        elif entry.is_file() and entry.suffix.lower() in [".mp3", ".wav", ".flac", ".m4a", ".ogg"]:
            stats = entry.stat()
            meta = get_track_meta_fast(entry)
            entries.append({
                "name": entry.name,
                "type": "file",
                "path": str(entry.relative_to(base)),
                "title": meta.get("title"),
                "artist": meta.get("artist"),
                "thumbnail": meta.get("thumbnail"),
                "source": meta.get("source"),
                "added_at": stats.st_mtime,
            })

    return {
        "root": root,
        "path": str(Path(path)),
        "entries": entries,
    }


@app.get("/api/file")
async def file(root: str, path: str) -> FileResponse:
    base = safe_root(root)
    target = safe_resolve(base, path)
    if not target.exists() or not target.is_file():
        raise HTTPException(status_code=404, detail="File not found")
    return FileResponse(target)


@app.post("/api/download")
async def download(req: DownloadRequest) -> Dict[str, Any]:
    url = req.url.strip()
    if not url:
        raise HTTPException(status_code=400, detail="Missing URL")
    quality_kbps = req.quality_kbps
    valid_qualities = {96, 128, 160, 192, 256, 320}
    if quality_kbps not in valid_qualities:
        raise HTTPException(status_code=400, detail="Invalid quality")

    log_event("download_start", url=url, quality=quality_kbps)
    formats = [
        "bestaudio/best",
        "bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio",
    ]
    cookies_path = os.environ.get("GPLAY_YTDLP_COOKIES")
    attempts: List[Dict[str, Any]] = []
    if cookies_path:
        attempts.extend(
            [
                {"format": formats[0], "player_clients": ["web"], "use_cookies": True},
                {"format": formats[1], "player_clients": ["web"], "use_cookies": True},
            ]
        )
        attempts.extend(
            [
                {"format": formats[0], "player_clients": ["android", "web"], "use_cookies": False},
                {"format": formats[1], "player_clients": ["android", "web"], "use_cookies": False},
            ]
        )
    else:
        attempts.extend(
            [
                {"format": formats[0], "player_clients": ["android", "web"], "use_cookies": False},
                {"format": formats[1], "player_clients": ["android", "web"], "use_cookies": False},
            ]
        )
    info: Optional[Dict[str, Any]] = None
    last_error: Optional[str] = None
    for attempt in attempts:
        try:
            info = run_download(
                url,
                attempt["format"],
                cookies_path,
                attempt["player_clients"],
                attempt["use_cookies"],
                quality_kbps,
            )
            break
        except Exception as exc:
            last_error = str(exc)
            log_error(
                "download_retry",
                url=url,
                format=attempt["format"],
                clients=",".join(attempt["player_clients"]),
                cookies=attempt["use_cookies"],
                error=last_error,
            )

    if not info:
        detail = "Download failed."
        if last_error and "empty" in last_error.lower():
            detail = (
                "Download failed: empty file. Try a different upload or provide "
                "cookies via GPLAY_YTDLP_COOKIES."
            )
        if last_error and "format is not available" in last_error.lower():
            log_available_formats(url, cookies_path, ["web"], bool(cookies_path))
            log_format_list_cli(url, cookies_path, ["web"], bool(cookies_path))
            log_available_formats(url, cookies_path, ["android", "web"], False)
            log_format_list_cli(url, cookies_path, ["android", "web"], False)
        log_error("download_error", url=url, error=last_error or "unknown")
        raise HTTPException(status_code=500, detail=detail)

    video_id = info.get("id") or "download"
    temp_path = Path(info.get("__download_path", str(LIBRARY_DIR / f"{video_id}.mp3")))

    title = info.get("track") or info.get("title") or video_id
    artist = info.get("artist")
    thumbnail = info.get("thumbnail")
    base_name = title
    if artist:
        base_name = f"{artist} - {title}"
    safe_name = safe_filename(base_name)
    path = LIBRARY_DIR / f"{safe_name}.mp3"
    if path.exists():
        if temp_path.exists():
            temp_path.unlink(missing_ok=True)
        raise HTTPException(
            status_code=409,
            detail="A track with this name already exists. Rename it first.",
        )
    if temp_path.exists():
        temp_path.rename(path)
    else:
        path = temp_path
    meta_path = path.with_suffix(path.suffix + ".meta.json")
    try:
        meta_path.write_text(
            json.dumps(
                {"title": title, "artist": artist, "thumbnail": thumbnail, "source": "youtube"},
                ensure_ascii=True,
            ),
            encoding="utf-8",
        )
    except Exception:
        log_event("meta_write_failed", path=str(meta_path))

    warning = None
    lower_title = (info.get("title") or "").lower()
    if "official video" in lower_title or "music video" in lower_title or re.search(r"\bmv\b", lower_title):
        warning = "This looks like a music video. For best quality, use official audio uploads."

    if req.playlist:
        playlist_path = PLAYLISTS_DIR / req.playlist
        if playlist_path.exists() and playlist_path.is_dir():
            try:
                dest = playlist_path / path.name
                shutil.copy2(path, dest)
                if meta_path.exists():
                    shutil.copy2(meta_path, dest.with_suffix(dest.suffix + ".meta.json"))
            except Exception as exc:
                log_error("playlist_add_error", error=str(exc))

    log_event("download_done", url=url, file=path.name)
    return {
        "root": "Library",
        "path": str(path.relative_to(LIBRARY_DIR)),
        "title": title,
        "artist": artist,
        "thumbnail": thumbnail,
        "source": "youtube",
        "quality_kbps": quality_kbps,
        "warning": warning,
    }


@app.post("/api/party/start")
async def party_start() -> Dict[str, Any]:
    code = generate_party_code()
    global PARTY_SEQ
    with PARTY_LOCK:
        PARTY_STATE["code"] = code
        PARTY_STATE["queue"] = []
        PARTY_SEQ = 0
    log_event("party_start", code=code)
    return {"code": code}


@app.post("/api/party/stop")
async def party_stop() -> Dict[str, Any]:
    with PARTY_LOCK:
        PARTY_STATE["code"] = None
        PARTY_STATE["queue"] = []
    log_event("party_stop")
    return {"active": False}


@app.post("/api/party/queue")
async def party_queue(req: PartyQueueRequest) -> Dict[str, Any]:
    require_party_code(req.code)
    with PARTY_LOCK:
        queue = list(PARTY_STATE.get("queue", []))
    return {"queue": queue}


@app.post("/api/party/enqueue")
async def party_enqueue(req: PartyEnqueueRequest) -> Dict[str, Any]:
    require_party_code(req.code)
    track = await download(DownloadRequest(url=req.url, quality_kbps=req.quality_kbps))
    item = add_party_item(track)
    log_event("party_enqueue", code=req.code, file=track.get("path"))
    return item


@app.post("/api/yt-info")
async def yt_info(req: InfoRequest) -> Dict[str, Any]:
    url = req.url.strip()
    if not url:
        raise HTTPException(status_code=400, detail="Missing URL")

    cookies_path = os.environ.get("GPLAY_YTDLP_COOKIES")
    attempts = [
        {"player_clients": ["web"], "use_cookies": bool(cookies_path)},
        {"player_clients": ["android", "web"], "use_cookies": False},
    ]
    info: Optional[Dict[str, Any]] = None
    last_error: Optional[str] = None
    for attempt in attempts:
        try:
            info = run_info(
                url,
                cookies_path,
                attempt["player_clients"],
                attempt["use_cookies"],
            )
            break
        except Exception as exc:
            last_error = str(exc)
            log_error(
                "info_retry",
                url=url,
                clients=",".join(attempt["player_clients"]),
                cookies=attempt["use_cookies"],
                error=last_error,
            )

    if not info:
        log_error("info_error", url=url, error=last_error or "unknown")
        raise HTTPException(status_code=500, detail="Info fetch failed")

    return {
        "id": info.get("id"),
        "title": info.get("track") or info.get("title"),
        "artist": info.get("artist"),
        "thumbnail": info.get("thumbnail"),
        "duration": info.get("duration"),
    }


@app.post("/api/audio-profile")
async def audio_profile(req: AudioProfileRequest) -> Dict[str, Any]:
    base = safe_root(req.root)
    source = safe_resolve(base, req.path)
    if not source.exists() or not source.is_file():
        raise HTTPException(status_code=404, detail="Source file not found")

    min_coverage = max(0.0, min(req.min_coverage, 0.2))
    meta = read_sidecar_meta(source)
    cached = meta.get("max_frequency_hz")
    if cached:
        return {
            "root": req.root,
            "path": str(source.relative_to(base)),
            "max_frequency_hz": cached,
            "sample_rate": meta.get("analysis_sample_rate"),
            "min_coverage": meta.get("analysis_min_coverage"),
            "cached": True,
        }

    log_event("audio_profile_start", root=req.root, path=req.path)
    try:
        max_freq, sample_rate = compute_max_frequency(source, min_coverage=min_coverage)
    except Exception as exc:
        log_error("audio_profile_error", error=str(exc))
        raise HTTPException(status_code=500, detail="Audio analysis failed")

    meta["max_frequency_hz"] = max_freq
    meta["analysis_sample_rate"] = sample_rate
    meta["analysis_min_coverage"] = min_coverage
    meta_path = source.with_suffix(source.suffix + ".meta.json")
    try:
        meta_path.write_text(json.dumps(meta, ensure_ascii=True), encoding="utf-8")
    except Exception:
        log_event("meta_write_failed", path=str(meta_path))

    log_event("audio_profile_done", root=req.root, path=req.path, max_hz=max_freq)
    return {
        "root": req.root,
        "path": str(source.relative_to(base)),
        "max_frequency_hz": max_freq,
        "sample_rate": sample_rate,
        "min_coverage": min_coverage,
        "cached": False,
    }


@app.post("/api/track-meta")
async def track_meta(req: TrackMetaRequest) -> Dict[str, Any]:
    base = safe_root(req.root)
    target = safe_resolve(base, req.path)
    if not target.exists() or not target.is_file():
        raise HTTPException(status_code=404, detail="File not found")
    meta = read_full_meta(target)
    return {
        "root": req.root,
        "path": str(target.relative_to(base)),
        "meta": meta,
    }


@app.post("/api/upload")
async def upload_file(file: UploadFile = File(...), root: str = "Library") -> Dict[str, Any]:
    base = safe_root(root)
    filename = safe_filename(Path(file.filename).stem)
    suffix = Path(file.filename).suffix or ".mp3"
    dest = base / f"{filename}{suffix}"
    if dest.exists():
        raise HTTPException(status_code=409, detail="A file with this name already exists")
    log_event("upload_start", root=root, file=file.filename)
    try:
        with dest.open("wb") as target:
            shutil.copyfileobj(file.file, target)
    except Exception as exc:
        log_error("upload_error", error=str(exc))
        raise HTTPException(status_code=500, detail="Upload failed")

    meta = get_track_meta(dest)
    meta_path = dest.with_suffix(dest.suffix + ".meta.json")
    try:
        meta["source"] = meta.get("source") or "local"
        meta_path.write_text(json.dumps(meta, ensure_ascii=True), encoding="utf-8")
    except Exception:
        log_event("meta_write_failed", path=str(meta_path))

    log_event("upload_done", root=root, file=dest.name)
    return {
        "root": root,
        "path": str(dest.relative_to(base)),
        "title": meta.get("title") or dest.stem,
        "artist": meta.get("artist"),
        "thumbnail": meta.get("thumbnail"),
        "source": meta.get("source"),
    }


@app.post("/api/tune")
async def tune(req: TuneRequest) -> Dict[str, Any]:
    base = safe_root(req.root)
    source = safe_resolve(base, req.path)
    if not source.exists() or not source.is_file():
        raise HTTPException(status_code=404, detail="Source file not found")

    output_name = req.output_name or f"{source.stem}_gplay_tuned.mp3"
    output = EDITS_DIR / output_name

    filter_chain = build_filter_chain(
        req.preamp_db,
        req.eq_gains,
        req.spatial_width,
        req.drc_mode,
        req.balance,
        req.limiter_on,
    )

    log_event("tune_start", source=str(source), output=str(output))
    try:
        process_audio(source, output, filter_chain)
    except Exception as exc:
        log_error("tune_error", error=str(exc))
        raise HTTPException(status_code=500, detail="Tune failed")

    meta = read_full_meta(source)
    meta["tuning"] = {
        "preamp_db": req.preamp_db,
        "eq_gains": req.eq_gains,
        "spatial_width": req.spatial_width,
        "drc_mode": req.drc_mode,
        "balance": req.balance,
        "limiter_on": req.limiter_on,
        "preset_name": req.preset_name,
    }
    meta_path = output.with_suffix(output.suffix + ".meta.json")
    try:
        meta_path.write_text(json.dumps(meta, ensure_ascii=True), encoding="utf-8")
    except Exception:
        log_event("meta_write_failed", path=str(meta_path))

    log_event("tune_done", output=str(output))
    return {
        "root": "Edited",
        "path": str(output.relative_to(EDITS_DIR)),
        "title": meta.get("title"),
        "artist": meta.get("artist"),
        "thumbnail": meta.get("thumbnail"),
    }


@app.post("/api/playlists")
async def create_playlist(req: PlaylistCreateRequest) -> Dict[str, str]:
    name = re.sub(r"[^A-Za-z0-9 _-]", "", req.name).strip()
    if not name:
        raise HTTPException(status_code=400, detail="Invalid playlist name")
    path = PLAYLISTS_DIR / name
    path.mkdir(parents=True, exist_ok=True)
    log_event("playlist_create", name=name)
    return {"name": name}


@app.post("/api/playlists/add")
async def add_playlist_item(req: PlaylistAddRequest) -> Dict[str, str]:
    base = safe_root(req.root)
    source = safe_resolve(base, req.path)
    playlist = PLAYLISTS_DIR / req.playlist
    if not source.exists() or not source.is_file():
        raise HTTPException(status_code=404, detail="Source file not found")
    if not playlist.exists() or not playlist.is_dir():
        raise HTTPException(status_code=404, detail="Playlist not found")

    dest = playlist / source.name
    if dest.exists():
        raise HTTPException(status_code=409, detail="Track already exists in playlist")
    shutil.copy2(source, dest)
    meta_src = source.with_suffix(source.suffix + ".meta.json")
    if meta_src.exists():
        shutil.copy2(meta_src, dest.with_suffix(dest.suffix + ".meta.json"))
    log_event("playlist_add", playlist=req.playlist, file=dest.name)
    return {"path": str(dest.relative_to(playlist))}


@app.post("/api/edit-cuts")
async def edit_cuts(req: EditCutsRequest) -> Dict[str, Any]:
    base = safe_root(req.root)
    source = safe_resolve(base, req.path)
    if not source.exists() or not source.is_file():
        raise HTTPException(status_code=404, detail="Source file not found")

    duration = read_duration_seconds(source)
    if duration <= 0:
        raise HTTPException(status_code=400, detail="Unable to read duration")

    normalized = normalize_cuts(req.cuts, duration)
    keep_segments = build_keep_segments(normalized, duration)
    if not keep_segments:
        raise HTTPException(status_code=400, detail="Cuts remove the entire track")

    output_name = req.output_name or f"{source.stem}_cut.mp3"
    output = EDITS_DIR / output_name
    if output.exists():
        raise HTTPException(status_code=409, detail="A file with this name already exists")

    log_event("edit_cuts_start", source=str(source), output=str(output))
    try:
        render_cut_audio(source, output, keep_segments)
    except Exception as exc:
        log_error("edit_cuts_error", error=str(exc))
        raise HTTPException(status_code=500, detail="Edit failed")

    meta = read_full_meta(source)
    meta_path = output.with_suffix(output.suffix + ".meta.json")
    try:
        meta_path.write_text(json.dumps(meta, ensure_ascii=True), encoding="utf-8")
    except Exception:
        log_event("meta_write_failed", path=str(meta_path))

    log_event("edit_cuts_done", output=str(output))
    return {
        "root": "Edited",
        "path": str(output.relative_to(EDITS_DIR)),
        "title": meta.get("title"),
        "artist": meta.get("artist"),
        "thumbnail": meta.get("thumbnail"),
    }


@app.post("/api/rename")
async def rename_file(req: RenameRequest) -> Dict[str, Any]:
    base = safe_root(req.root)
    source = safe_resolve(base, req.path)
    if not source.exists() or not source.is_file():
        raise HTTPException(status_code=404, detail="Source file not found")

    new_name = req.new_name.strip()
    if not new_name:
        raise HTTPException(status_code=400, detail="New name is required")

    incoming = Path(new_name).name
    new_stem = safe_filename(Path(incoming).stem)
    new_suffix = Path(incoming).suffix
    if new_suffix and new_suffix.lower() != source.suffix.lower():
        raise HTTPException(status_code=400, detail="Changing extensions is not allowed")

    dest = source.parent / f"{new_stem}{source.suffix}"
    if dest == source:
        return {
            "root": req.root,
            "path": str(source.relative_to(base)),
            "title": get_track_meta(source).get("title"),
            "artist": get_track_meta(source).get("artist"),
            "thumbnail": get_track_meta(source).get("thumbnail"),
        }
    if dest.exists():
        raise HTTPException(status_code=409, detail="A file with this name already exists")

    source.rename(dest)
    meta_src = source.with_suffix(source.suffix + ".meta.json")
    meta_dest = dest.with_suffix(dest.suffix + ".meta.json")
    meta: Dict[str, Any] = {}
    if meta_src.exists():
        try:
            meta = json.loads(meta_src.read_text(encoding="utf-8"))
        except Exception:
            meta = {}
        meta_src.rename(meta_dest)

    inferred = infer_title_artist_from_name(dest)
    meta["title"] = inferred.get("title")
    meta["artist"] = inferred.get("artist")
    meta.setdefault("thumbnail", None)
    try:
        meta_dest.write_text(json.dumps(meta, ensure_ascii=True), encoding="utf-8")
    except Exception:
        log_event("meta_write_failed", path=str(meta_dest))

    log_event("rename_file", root=req.root, src=str(source), dest=str(dest))
    return {
        "root": req.root,
        "path": str(dest.relative_to(base)),
        "title": meta.get("title"),
        "artist": meta.get("artist"),
        "thumbnail": meta.get("thumbnail"),
    }


@app.post("/api/save-to-library")
async def save_to_library(req: SaveToLibraryRequest) -> Dict[str, Any]:
    if req.root != "Edited":
        raise HTTPException(status_code=400, detail="Only edited tracks can be saved")
    source_root = safe_root(req.root)
    source = safe_resolve(source_root, req.path)
    if not source.exists() or not source.is_file():
        raise HTTPException(status_code=404, detail="Source file not found")

    dest = LIBRARY_DIR / source.name
    if dest.exists():
        raise HTTPException(
            status_code=409,
            detail="A track with this name already exists. Rename it first.",
        )

    shutil.copy2(source, dest)
    meta_src = source.with_suffix(source.suffix + ".meta.json")
    meta_dest = dest.with_suffix(dest.suffix + ".meta.json")
    if meta_src.exists():
        shutil.copy2(meta_src, meta_dest)
    else:
        meta = get_track_meta(source)
        try:
            meta_dest.write_text(json.dumps(meta, ensure_ascii=True), encoding="utf-8")
        except Exception:
            log_event("meta_write_failed", path=str(meta_dest))

    meta = get_track_meta(dest)
    log_event("save_to_library", src=str(source), dest=str(dest))
    return {
        "root": "Library",
        "path": str(dest.relative_to(LIBRARY_DIR)),
        "title": meta.get("title"),
        "artist": meta.get("artist"),
        "thumbnail": meta.get("thumbnail"),
    }


@app.post("/api/delete")
async def delete_file(req: DeleteRequest) -> Dict[str, Any]:
    if req.root not in ("Edited", "Library"):
        raise HTTPException(status_code=400, detail="Only library or edited tracks can be deleted")
    base = safe_root(req.root)
    target = safe_resolve(base, req.path)
    if not target.exists() or not target.is_file():
        raise HTTPException(status_code=404, detail="File not found")
    meta_path = target.with_suffix(target.suffix + ".meta.json")
    try:
        target.unlink()
        if meta_path.exists():
            meta_path.unlink()
    except Exception as exc:
        log_error("delete_error", error=str(exc))
        raise HTTPException(status_code=500, detail="Delete failed")
    log_event("delete_file", root=req.root, path=req.path)
    return {"deleted": True}


@app.post("/api/open-folder")
async def open_folder_endpoint(req: OpenFolderRequest) -> Dict[str, Any]:
    base = safe_root(req.root)
    target = base
    if req.path:
        resolved = safe_resolve(base, req.path)
        if resolved.is_file():
            target = resolved.parent
        else:
            target = resolved
    if not target.exists():
        raise HTTPException(status_code=404, detail="Folder not found")
    try:
        open_folder(target)
    except Exception as exc:
        log_error("open_folder_error", error=str(exc))
        raise HTTPException(status_code=500, detail="Open folder failed")
    log_event("open_folder", root=req.root, path=str(target))
    return {"opened": True}


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    log_error("unhandled_exception", path=request.url.path, error=str(exc))
    return JSONResponse(status_code=500, content={"detail": "Server error"})
