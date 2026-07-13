# g-play-web

## What this codebase does

vantabeat is a local-only macOS music app. A native SwiftUI shell in `macos/GPlayMac/Sources/GPlayMac` launches a bundled Python FastAPI media engine from `backend/app` as a private child process on `127.0.0.1`, then uses that loopback API for library browsing, local file import, YouTube/SoundCloud downloads, playback file URLs, playlists, EQ rendering, trimming, artwork, and a local "party" queue. The release bundle is assembled by `macos/scripts/build_app.sh` into `.build/macos/vantabeat.app`; runtime user data lives under `~/Library/Application Support/vantabeat`.

## Auth shape

- `BackendProcess.backendEnvironment` generates and passes `VANTABEAT_API_TOKEN` to the Python engine on each launch.
- `GPlayAPI.tokenHeader` is the Swift client header name for private API calls.
- `local_engine_middleware` protects every route except `PUBLIC_PATHS`.
- `request_token` accepts the token from the private header and, for some media/file flows, query params.
- `safe_root`, `safe_resolve`, and `rel_to_root` are the path confinement primitives for library, edited, and playlists roots.

## Threat model

The main attacker is local malware or another local user/process trying to use the loopback engine, steal cookie-backed YouTube access, read files outside the app data folders, or overwrite/delete a user's media library. Network exposure should stay loopback-only; remote web attackers should not be able to reach the engine unless the user has exposed localhost. Untrusted inputs include URLs passed to yt-dlp, uploaded audio files, media metadata/artwork URLs, playlist/file names, and relative paths sent to the local API.

## Project-specific patterns to flag

- FastAPI route handlers in `backend/app/main.py` should rely on `local_engine_middleware`; new public paths in `PUBLIC_PATHS` need deliberate review.
- Relative filesystem paths must go through `safe_root` + `safe_resolve`; direct joins against `LIBRARY_DIR`, `EDITS_DIR`, or `PLAYLISTS_DIR` are suspicious.
- File-serving and playback URLs should avoid leaking the per-launch token into logs, history, crash reports, or third-party URL fetches.
- Subprocess work should use argument arrays and bounded inputs; audio tools (`ffmpeg`, `ffprobe`, `yt-dlp`, `open`) process attacker-controlled media/URLs.
- Bundled release scripts must avoid copying local cookies, logs, downloaded tracks, or development-only root markers into the app bundle.

## Known false-positives

- `/api/health` in `PUBLIC_PATHS` is intentionally unauthenticated for app startup readiness.
- `NSAllowsLocalNetworking` in `macos/Info.plist` is required for Swift-to-loopback HTTP inside the app.
- `BackendProcess` intentionally binds uvicorn to `127.0.0.1` and launches a bundled Python child process.
- `open_folder` intentionally invokes Finder/`open` for user-selected app data folders.
- `cookies*.txt`, `library/`, `edited/`, `playlists/`, logs, `.build/`, `.macness/`, and `.artifacts/` are local/runtime artifacts and should not be treated as source.
