from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from yt_dlp import YoutubeDL

from .config import DOWNLOAD_FRAGMENT_WORKERS, LIBRARY_DIR, YTDLP_COOKIES_FROM_BROWSER
from .logging_config import YtdlpLogger, log_error, log_event
from .metadata import selected_download_path

ORIGINAL_AUDIO_EXTENSIONS = {"m4a", "aac", "flac", "wav", "aiff", "alac"}
CONTAINER_TIE_BREAKERS = {
    "flac": 8,
    "wav": 7,
    "aiff": 7,
    "alac": 7,
    "m4a": 6,
    "aac": 5,
    "opus": 4,
    "webm": 3,
    "ogg": 2,
    "mp3": 1,
}

def build_ydl_opts(
    format_value: str,
    cookies_path: Optional[str],
    player_clients: Optional[List[str]] = None,
    use_cookies: bool = True,
) -> Dict[str, Any]:
    opts: Dict[str, Any] = {
        "format": format_value,
        "outtmpl": str(LIBRARY_DIR / "%(extractor_key)s_%(id)s.%(ext)s"),
        "noplaylist": True,
        "quiet": True,
        "no_warnings": True,
        "retries": 3,
        "fragment_retries": 3,
        "concurrent_fragment_downloads": DOWNLOAD_FRAGMENT_WORKERS,
        "force_ipv4": True,
        "logger": YtdlpLogger(),
    }
    if use_cookies and YTDLP_COOKIES_FROM_BROWSER:
        opts["cookiesfrombrowser"] = YTDLP_COOKIES_FROM_BROWSER
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


def is_audio_only_format(fmt: Dict[str, Any]) -> bool:
    acodec = fmt.get("acodec")
    vcodec = fmt.get("vcodec")
    return acodec not in (None, "none") and vcodec in (None, "none")


def numeric_field(fmt: Dict[str, Any], *keys: str) -> float:
    for key in keys:
        value = fmt.get(key)
        if value is None:
            continue
        try:
            return float(value)
        except (TypeError, ValueError):
            continue
    return 0.0


def audio_quality_score(fmt: Dict[str, Any]) -> Tuple[int, int, float, float, float, int]:
    ext = str(fmt.get("ext") or "").lower()
    descriptor = " ".join(
        str(value or "")
        for value in [
            fmt.get("format_id"),
            fmt.get("format"),
            fmt.get("format_note"),
            fmt.get("audio_ext"),
            fmt.get("acodec"),
        ]
    ).lower()
    is_original = int(ext in ORIGINAL_AUDIO_EXTENSIONS and any(term in descriptor for term in ["original", "source"]))
    is_lossless = int(ext in {"flac", "wav", "aiff", "alac"} or "lossless" in descriptor)
    bitrate = numeric_field(fmt, "abr", "tbr")
    filesize = numeric_field(fmt, "filesize", "filesize_approx")
    sample_rate = numeric_field(fmt, "asr")
    container_score = CONTAINER_TIE_BREAKERS.get(ext, 0)
    return (is_original, is_lossless, bitrate, filesize, sample_rate, container_score)


def best_audio_format_id(info: Dict[str, Any]) -> Optional[str]:
    audio_formats = [
        fmt
        for fmt in info.get("formats") or []
        if is_audio_only_format(fmt)
    ]
    if not audio_formats:
        return None
    best = max(audio_formats, key=audio_quality_score)
    format_id = best.get("format_id")
    if not format_id:
        return None
    log_event(
        "download_format_selected",
        format_id=format_id,
        ext=best.get("ext"),
        acodec=best.get("acodec"),
        abr=best.get("abr"),
        tbr=best.get("tbr"),
        filesize=best.get("filesize") or best.get("filesize_approx"),
        score=audio_quality_score(best),
    )
    return str(format_id)


def run_download(
    url: str,
    format_value: str,
    cookies_path: Optional[str],
    player_clients: List[str],
    use_cookies: bool,
) -> Dict[str, Any]:
    ydl_opts = build_ydl_opts(
        format_value,
        cookies_path,
        player_clients,
        use_cookies,
    )
    probe_opts = dict(ydl_opts)
    probe_opts["skip_download"] = True
    with YoutubeDL(probe_opts) as ydl:
        probe_info = ydl.extract_info(url, download=False)
        selected_format = best_audio_format_id(probe_info)

    if selected_format:
        ydl_opts["format"] = selected_format

    with YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url, download=True)
        info = ydl.sanitize_info(info)
    path = selected_download_path(LIBRARY_DIR, info)
    if not path.exists() or path.stat().st_size == 0:
        raise RuntimeError("Downloaded file is empty")
    info["__download_path"] = str(path)
    if selected_format:
        info["__selected_format_id"] = selected_format
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
