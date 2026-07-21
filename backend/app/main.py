from __future__ import annotations

import json
import re
import shutil
import time
from pathlib import Path
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse

from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from starlette.concurrency import run_in_threadpool

from .engine.audio import (
    build_filter_chain,
    build_keep_segments,
    compute_max_frequency,
    normalize_cuts,
    process_audio,
    read_duration_seconds,
    render_cut_audio,
)
from .engine.artwork import copy_artwork_sidecar, embed_artwork
from .engine.config import (
    API_TOKEN,
    APP_NAME,
    AUDIO_EXTENSIONS,
    EDITS_DIR,
    LIBRARY_DIR,
    PLAYLISTS_DIR,
    YTDLP_COOKIES,
    ensure_runtime_dirs,
)
from .engine.downloads import (
    log_available_formats,
    log_format_list_cli,
    run_download,
    run_info,
)
from .engine.logging_config import log_error, log_event
from .engine.metadata import (
    best_thumbnail_url,
    download_artwork,
    get_track_meta,
    get_track_meta_fast,
    infer_title_artist_from_name,
    read_full_meta,
    read_sidecar_meta,
    title_parts,
)
from .engine.party import (
    add_party_item,
    party_queue_snapshot,
    require_party_code,
    start_party,
    stop_party,
)
from .engine.schemas import (
    AudioProfileRequest,
    DeleteRequest,
    DownloadRequest,
    EditCutsRequest,
    InfoRequest,
    OpenFolderRequest,
    PartyEnqueueRequest,
    PartyQueueRequest,
    PlaylistAddRequest,
    PlaylistCreateRequest,
    RenameRequest,
    SaveToLibraryRequest,
    TrackMetaRequest,
    TuneRequest,
)
from .engine.storage import (
    list_playlists,
    open_folder,
    rel_to_root,
    roots_map,
    safe_filename,
    safe_output_audio_path,
    safe_resolve,
    safe_root,
)

ensure_runtime_dirs()

app = FastAPI(title=f"{APP_NAME} Local Media Engine")

PUBLIC_PATHS = {"/api/health"}
# Header name only; the per-launch token value comes from VANTABEAT_API_TOKEN.
TOKEN_HEADER = "x-vantabeat-token"  # nosec B105
SUPPORTED_DOWNLOAD_HOSTS = {
    "soundcloud": ("soundcloud.com",),
    "youtube": ("youtube.com", "youtu.be"),
}


def request_token(request: Request) -> Optional[str]:
    return request.headers.get(TOKEN_HEADER)


def supported_host(host: str, allowed_roots: tuple[str, ...]) -> bool:
    return any(host == root or host.endswith(f".{root}") for root in allowed_roots)


def validate_media_url(url: str) -> str:
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    if parsed.scheme not in {"http", "https"} or not host:
        raise HTTPException(status_code=400, detail="Use a YouTube or SoundCloud URL.")
    for source, allowed_roots in SUPPORTED_DOWNLOAD_HOSTS.items():
        if supported_host(host, allowed_roots):
            return source
    raise HTTPException(status_code=400, detail="Only YouTube and SoundCloud URLs are supported.")


def copy_upload(source: Any, dest: Path) -> None:
    with dest.open("wb") as target:
        while chunk := source.read(1024 * 1024):
            target.write(chunk)


def validate_private_request(request: Request) -> Optional[JSONResponse]:
    if request.url.path in PUBLIC_PATHS:
        return None
    if not API_TOKEN:
        log_error("api_token_missing", path=request.url.path)
        return JSONResponse(status_code=503, content={"detail": "Local engine auth token is not configured"})
    if request_token(request) != API_TOKEN:
        log_error("api_token_rejected", path=request.url.path)
        return JSONResponse(status_code=403, content={"detail": "Invalid local engine token"})
    return None


@app.middleware("http")
async def local_engine_middleware(request: Request, call_next):
    auth_error = validate_private_request(request)
    if auth_error:
        return auth_error

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


@app.get("/api/health")
async def health() -> Dict[str, str]:
    return {"status": "ok", "app": APP_NAME}


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
    for entry in sorted(target.iterdir(), key=lambda item: (item.is_file(), item.name.lower())):
        if entry.is_dir():
            stats = entry.stat()
            entries.append({
                "name": entry.name,
                "type": "dir",
                "path": rel_to_root(entry, base),
                "added_at": stats.st_mtime,
            })
        elif entry.is_file() and entry.suffix.lower() in AUDIO_EXTENSIONS:
            stats = entry.stat()
            meta = get_track_meta_fast(entry)
            entries.append({
                "name": entry.name,
                "type": "file",
                "path": rel_to_root(entry, base),
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

    source = validate_media_url(url)
    log_event("download_start", url=url, source=source)
    formats = ["bestaudio/best"]
    attempts: List[Dict[str, Any]] = []
    if YTDLP_COOKIES:
        attempts.extend(
            [
                {"format": formats[0], "player_clients": ["web"], "use_cookies": True},
            ]
        )
        attempts.extend(
            [
                {"format": formats[0], "player_clients": ["android", "web"], "use_cookies": False},
            ]
        )
    else:
        attempts.extend(
            [
                {"format": formats[0], "player_clients": ["android", "web"], "use_cookies": False},
            ]
        )

    info: Optional[Dict[str, Any]] = None
    last_error: Optional[str] = None
    for attempt in attempts:
        try:
            info = await run_in_threadpool(
                run_download,
                url,
                attempt["format"],
                YTDLP_COOKIES,
                attempt["player_clients"],
                attempt["use_cookies"],
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
                "cookies via VANTABEAT_YTDLP_COOKIES."
            )
        if last_error and "format is not available" in last_error.lower():
            await run_in_threadpool(log_available_formats, url, YTDLP_COOKIES, ["web"], bool(YTDLP_COOKIES))
            await run_in_threadpool(log_format_list_cli, url, YTDLP_COOKIES, ["web"], bool(YTDLP_COOKIES))
            await run_in_threadpool(log_available_formats, url, YTDLP_COOKIES, ["android", "web"], False)
            await run_in_threadpool(log_format_list_cli, url, YTDLP_COOKIES, ["android", "web"], False)
        log_error("download_error", url=url, error=last_error or "unknown")
        raise HTTPException(status_code=500, detail=detail)

    download_id = info.get("id") or "download"
    temp_path = Path(info.get("__download_path", str(LIBRARY_DIR / f"{download_id}")))
    if temp_path.suffix.lower() not in AUDIO_EXTENSIONS:
        raise HTTPException(status_code=500, detail="Downloaded file format is not supported")

    parts = title_parts(info, temp_path.stem) if source == "soundcloud" else {
        "raw_title": info.get("track") or info.get("title") or download_id,
        "title": info.get("track") or info.get("title") or download_id,
        "artist": info.get("artist"),
        "uploader": info.get("uploader"),
        "featured_artists": [],
        "remixers": [],
    }
    title = parts.get("title") or download_id
    artist = parts.get("artist")
    thumbnail = best_thumbnail_url(info)
    base_name = f"{artist} - {title}" if artist else title
    path = LIBRARY_DIR / f"{safe_filename(base_name)}{temp_path.suffix.lower()}"
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

    artwork_path = await run_in_threadpool(download_artwork, info, path)
    artwork_embed_result = None
    if artwork_path:
        artwork_embed_result = await run_in_threadpool(embed_artwork, path, artwork_path)
    meta_path = path.with_suffix(path.suffix + ".meta.json")
    requested_downloads = info.get("requested_downloads") or []
    selected_format = (
        info.get("__selected_format_id")
        or (requested_downloads[0].get("format_id") if requested_downloads else None)
        or info.get("format_id")
    )
    meta = {
        "name": title,
        "title": title,
        "raw_title": parts.get("raw_title"),
        "artist": artist,
        "uploader": parts.get("uploader"),
        "featured_artists": parts.get("featured_artists", []),
        "remixers": parts.get("remixers", []),
        "thumbnail": thumbnail,
        "artwork": str(artwork_path) if artwork_path else None,
        "artwork_embedded": bool(artwork_embed_result.embedded) if artwork_embed_result else False,
        "source": source,
        "source_url": info.get("webpage_url") or url,
        "duration": info.get("duration"),
        "genre": info.get("genre"),
        "description": info.get("description"),
        "license": info.get("license"),
        "release_date": info.get("release_date"),
        "download_id": download_id,
        "extractor": info.get("extractor_key"),
        "format_id": selected_format,
        "ext": path.suffix.removeprefix("."),
        "acodec": info.get("acodec"),
        "abr": info.get("abr"),
        "tbr": info.get("tbr"),
    }
    if source == "soundcloud":
        meta["soundcloud_id"] = download_id
    else:
        meta["youtube_id"] = download_id
    try:
        meta_path.write_text(json.dumps(meta, ensure_ascii=True), encoding="utf-8")
    except Exception:
        log_event("meta_write_failed", path=str(meta_path))

    warning = None
    lower_title = (info.get("title") or "").lower()
    if "official video" in lower_title or "music video" in lower_title or re.search(r"\bmv\b", lower_title):
        warning = "This looks like a music video. For best quality, use official audio uploads."

    if req.playlist:
        playlist_path = safe_resolve(PLAYLISTS_DIR, req.playlist)
        if playlist_path.exists() and playlist_path.is_dir():
            try:
                dest = playlist_path / path.name
                shutil.copy2(path, dest)
                if meta_path.exists():
                    shutil.copy2(meta_path, dest.with_suffix(dest.suffix + ".meta.json"))
                if artwork_path and artwork_path.exists():
                    shutil.copy2(artwork_path, dest.with_suffix(dest.suffix + f".artwork{artwork_path.suffix}"))
            except Exception as exc:
                log_error("playlist_add_error", error=str(exc))

    log_event("download_done", url=url, file=path.name)
    return {
        "root": "Library",
        "path": rel_to_root(path, LIBRARY_DIR),
        "title": title,
        "artist": artist,
        "thumbnail": thumbnail,
        "artwork": str(artwork_path) if artwork_path else None,
        "source": source,
        "format_id": selected_format,
        "ext": path.suffix.removeprefix("."),
        "acodec": info.get("acodec"),
        "abr": info.get("abr"),
        "tbr": info.get("tbr"),
        "warning": warning,
    }


@app.post("/api/party/start")
async def party_start() -> Dict[str, Any]:
    code = start_party()
    log_event("party_start", code=code)
    return {"code": code}


@app.post("/api/party/stop")
async def party_stop() -> Dict[str, Any]:
    stop_party()
    log_event("party_stop")
    return {"active": False}


@app.post("/api/party/queue")
async def party_queue(req: PartyQueueRequest) -> Dict[str, Any]:
    require_party_code(req.code)
    return {"queue": party_queue_snapshot()}


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
    validate_media_url(url)

    attempts = [
        {"player_clients": ["web"], "use_cookies": bool(YTDLP_COOKIES)},
        {"player_clients": ["android", "web"], "use_cookies": False},
    ]
    info: Optional[Dict[str, Any]] = None
    last_error: Optional[str] = None
    for attempt in attempts:
        try:
            info = await run_in_threadpool(
                run_info,
                url,
                YTDLP_COOKIES,
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
            "path": rel_to_root(source, base),
            "max_frequency_hz": cached,
            "sample_rate": meta.get("analysis_sample_rate"),
            "min_coverage": meta.get("analysis_min_coverage"),
            "cached": True,
        }

    log_event("audio_profile_start", root=req.root, path=req.path)
    try:
        max_freq, sample_rate = await run_in_threadpool(compute_max_frequency, source, min_coverage)
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
        "path": rel_to_root(source, base),
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
        "path": rel_to_root(target, base),
        "meta": meta,
    }


@app.post("/api/upload")
async def upload_file(file: UploadFile = File(...), root: str = "Library") -> Dict[str, Any]:
    base = safe_root(root)
    filename = safe_filename(Path(file.filename).stem)
    suffix = (Path(file.filename).suffix or ".mp3").lower()
    if suffix.lower() not in AUDIO_EXTENSIONS:
        raise HTTPException(status_code=400, detail="Unsupported audio file type")
    dest = base / f"{filename}{suffix}"
    if dest.exists():
        raise HTTPException(status_code=409, detail="A file with this name already exists")
    log_event("upload_start", root=root, file=file.filename)
    try:
        copy_upload(file.file, dest)
    except Exception as exc:
        dest.unlink(missing_ok=True)
        log_error("upload_error", error=str(exc))
        raise HTTPException(status_code=500, detail="Upload failed")
    finally:
        file.file.close()

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
        "path": rel_to_root(dest, base),
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

    output = safe_output_audio_path(
        EDITS_DIR,
        req.output_name,
        f"{source.stem}_vantabeat_tuned.mp3",
    )
    if output.exists():
        raise HTTPException(status_code=409, detail="A file with this name already exists")

    try:
        filter_chain = build_filter_chain(
            req.preamp_db,
            req.eq_gains,
            req.spatial_width,
            req.drc_mode,
            req.balance,
            req.limiter_on,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    log_event("tune_start", source=str(source), output=str(output))
    try:
        await run_in_threadpool(process_audio, source, output, filter_chain)
    except Exception as exc:
        log_error("tune_error", error=str(exc))
        raise HTTPException(status_code=500, detail="Tune failed")

    meta = read_full_meta(source)
    artwork_path = await run_in_threadpool(copy_artwork_sidecar, source, output)
    artwork_embed_result = None
    if artwork_path:
        artwork_embed_result = await run_in_threadpool(embed_artwork, output, artwork_path)
        meta["artwork"] = str(artwork_path)
        meta["artwork_embedded"] = bool(artwork_embed_result.embedded)
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
        "path": rel_to_root(output, EDITS_DIR),
        "title": meta.get("title"),
        "artist": meta.get("artist"),
        "thumbnail": meta.get("thumbnail"),
    }


@app.post("/api/playlists")
async def create_playlist(req: PlaylistCreateRequest) -> Dict[str, str]:
    name = safe_filename(req.name)
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
    playlist = safe_resolve(PLAYLISTS_DIR, req.playlist)
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
    for candidate in source.parent.iterdir():
        if candidate.name.startswith(source.name + ".artwork."):
            shutil.copy2(candidate, dest.with_suffix(dest.suffix + candidate.name.removeprefix(source.name)))
    log_event("playlist_add", playlist=req.playlist, file=dest.name)
    return {"path": rel_to_root(dest, playlist)}


@app.post("/api/edit-cuts")
async def edit_cuts(req: EditCutsRequest) -> Dict[str, Any]:
    base = safe_root(req.root)
    source = safe_resolve(base, req.path)
    if not source.exists() or not source.is_file():
        raise HTTPException(status_code=404, detail="Source file not found")

    duration = await run_in_threadpool(read_duration_seconds, source)
    if duration <= 0:
        raise HTTPException(status_code=400, detail="Unable to read duration")

    normalized = normalize_cuts(req.cuts, duration)
    keep_segments = build_keep_segments(normalized, duration)
    if not keep_segments:
        raise HTTPException(status_code=400, detail="Cuts remove the entire track")

    output = safe_output_audio_path(
        EDITS_DIR,
        req.output_name,
        f"{source.stem}_cut.mp3",
    )
    if output.exists():
        raise HTTPException(status_code=409, detail="A file with this name already exists")

    log_event("edit_cuts_start", source=str(source), output=str(output))
    try:
        await run_in_threadpool(render_cut_audio, source, output, keep_segments)
    except Exception as exc:
        log_error("edit_cuts_error", error=str(exc))
        raise HTTPException(status_code=500, detail="Edit failed")

    meta = read_full_meta(source)
    artwork_path = await run_in_threadpool(copy_artwork_sidecar, source, output)
    artwork_embed_result = None
    if artwork_path:
        artwork_embed_result = await run_in_threadpool(embed_artwork, output, artwork_path)
        meta["artwork"] = str(artwork_path)
        meta["artwork_embedded"] = bool(artwork_embed_result.embedded)
    meta_path = output.with_suffix(output.suffix + ".meta.json")
    try:
        meta_path.write_text(json.dumps(meta, ensure_ascii=True), encoding="utf-8")
    except Exception:
        log_event("meta_write_failed", path=str(meta_path))

    log_event("edit_cuts_done", output=str(output))
    return {
        "root": "Edited",
        "path": rel_to_root(output, EDITS_DIR),
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
        meta = get_track_meta(source)
        return {
            "root": req.root,
            "path": rel_to_root(source, base),
            "title": meta.get("title"),
            "artist": meta.get("artist"),
            "thumbnail": meta.get("thumbnail"),
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
    for candidate in source.parent.iterdir():
        if candidate.name.startswith(source.name + ".artwork."):
            candidate.rename(dest.with_suffix(dest.suffix + candidate.name.removeprefix(source.name)))

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
        "path": rel_to_root(dest, base),
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
    for candidate in source.parent.iterdir():
        if candidate.name.startswith(source.name + ".artwork."):
            shutil.copy2(candidate, dest.with_suffix(dest.suffix + candidate.name.removeprefix(source.name)))

    meta = get_track_meta(dest)
    log_event("save_to_library", src=str(source), dest=str(dest))
    return {
        "root": "Library",
        "path": rel_to_root(dest, LIBRARY_DIR),
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
        for candidate in target.parent.iterdir():
            if candidate.name.startswith(target.name + ".artwork."):
                candidate.unlink()
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
