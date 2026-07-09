# vantabeat

vantabeat is a local macOS music studio for playback, imports, EQ rendering, and reactive visuals. The SwiftUI app owns the user interface and launches a bundled Python media engine as a private child process.

Runtime data lives outside the repo by default:

```bash
~/Library/Application Support/vantabeat
```

## macOS App

Build the app bundle:

```bash
./macos/scripts/build_app.sh
```

Run it:

```bash
open "./.build/macos/vantabeat.app"
```

Verify it with `macness`:

```bash
./macos/scripts/verify_with_macness.sh
```

## Runtime Data

The app stores local music, rendered tracks, playlists, logs, and optional YouTube cookies in:

```bash
~/Library/Application Support/vantabeat
```

For YouTube imports that need cookies, place `cookies.txt` in that folder. Do not commit cookies, songs, sidecar metadata, logs, or generated app bundles.

Supported local audio containers include `.aac`, `.m4a`, `.mp3`, `.flac`, `.wav`, `.ogg`, `.opus`, and `.webm`.

## Development Media Engine

Docker is kept as a development-only runtime for the local media engine:

```bash
docker compose up --build
```

The API listens on `http://localhost:9137` and expects the dev token from `docker-compose.yml`.

For YouTube cookies in Docker:

```bash
docker compose -f docker-compose.yml -f docker-compose.cookies.yml up --build
```

That mounts local `./cookies.txt` at `/app/cookies.txt` and sets `VANTABEAT_YTDLP_COOKIES=/app/cookies.txt` inside the container.

## Local Engine Development

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
VANTABEAT_API_TOKEN=dev-local-token uvicorn app.main:app --reload --port 9137
```

Runtime folders, cookies, generated app bundles, virtualenvs, dependency folders, and verification artifacts are ignored by git.
