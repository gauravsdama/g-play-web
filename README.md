# G Play

G Play is a native SwiftUI macOS music app backed by a local FastAPI audio engine. The macOS app owns the interface, launches the Python backend as a child process, and stores runtime data outside the repo in `~/Library/Application Support/G Play`.

## macOS App

Build the app bundle:

```bash
./macos/scripts/build_app.sh
```

Run it:

```bash
open "./.build/macos/G Play.app"
```

Verify it with `macness`:

```bash
./macos/scripts/verify_with_macness.sh
```

## Runtime Data

The native app stores local music, edited audio, playlists, logs, and optional YouTube cookies here:

```bash
~/Library/Application Support/G Play
```

For YouTube downloads that need cookies, place `cookies.txt` in that folder. Do not commit cookies, songs, sidecar metadata, logs, or generated app bundles.

## Backend Dev Container

Docker is kept as a backend-only development runtime:

```bash
docker compose up --build
```

The API listens on `http://localhost:9137`.

YouTube cookies are opt-in through the ignored local override:

```bash
docker compose -f docker-compose.yml -f docker-compose.cookies.yml up --build
```

That mounts local `./cookies.txt` at `/app/cookies.txt` and sets `GPLAY_YTDLP_COOKIES=/app/cookies.txt` inside the container.

## Local Backend Development

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 9137
```

Runtime folders, cookies, generated app bundles, virtualenvs, and dependency folders are ignored by git.
