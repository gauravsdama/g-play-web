# G Play (React + FastAPI)

Single-container build with a React + Vite frontend and a FastAPI backend. Audio is always local (downloaded or uploaded) and the visualizer uses the currently playing track.

## macOS App
Build the native macOS shell:

```bash
cd g-play-web
./macos/scripts/build_app.sh
open "./.build/macos/G Play.app"
```

Verify the app with `macness`:

```bash
./macos/scripts/verify_with_macness.sh
```

The macOS app stores runtime data in:

```bash
~/Library/Application Support/G Play
```

For YouTube cookies in the macOS app, place `cookies.txt` in that same folder.

## Ports
- Docker (single port): `9137`
- Vite dev server (optional): `5176`

## Docker (single container)
```bash
cd g-play-web

docker compose up --build
```

Open `http://localhost:9137`.

Bind mounts are enabled in `docker-compose.yml`:
- `./library` -> `/app/library`
- `./edited` -> `/app/edited`
- `./playlists` -> `/app/playlists`
- `./logs` -> `/app/logs`

### YouTube Cookies

YouTube pulls often need cookies. Keep your local `cookies.txt` in this folder, but do not commit it. It is ignored by git. The file must exist before you use the cookie override.

Run Docker with the cookie override:

```bash
docker compose -f docker-compose.yml -f docker-compose.cookies.yml up --build
```

That mounts local `./cookies.txt` at `/app/cookies.txt` and sets `GPLAY_YTDLP_COOKIES=/app/cookies.txt` inside the container.

## Local dev (optional)
Backend:
```bash
cd g-play-web/backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 9137
```

Frontend:
```bash
cd g-play-web/frontend
npm install
npm run dev
```

If running frontend + backend separately, set `VITE_API_BASE` to `http://localhost:9137`.

## Notes
- YouTube downloads save into `g-play-web/library` with sidecar metadata for title/artist/artwork.
- Edited audio renders into `g-play-web/edited`.
- Playlists are folders in `g-play-web/playlists`.
- If YouTube blocks downloads, pass a cookies file with `GPLAY_YTDLP_COOKIES=/app/cookies.txt`.
- To auto-use browser cookies (no manual updates) when running locally, set `GPLAY_YTDLP_COOKIES_FROM_BROWSER=chrome` (or `firefox`, etc.). This does not work inside Docker because the container cannot access your host browser cookie store.
- Runtime folders, cookies, generated app bundles, virtualenvs, and dependency folders are ignored by git.
