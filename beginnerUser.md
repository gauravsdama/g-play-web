# Starting G Play on macOS

## Build the app

Open Terminal in this folder and run:

```bash
./macos/scripts/build_app.sh
```

## Open the app

```bash
open "./.build/macos/G Play.app"
```

## Stop the backend-only Docker runtime

If you used Docker for backend development:

```bash
docker compose down
```
