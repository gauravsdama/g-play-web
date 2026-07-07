# G Play for macOS

This folder packages G Play as a native SwiftUI macOS app backed by the local FastAPI audio engine.

The current architecture is:

- SwiftUI app shell
- native SwiftUI navigation, library, player, download, playlist, tuning, and visualizer views
- bundled FastAPI backend launched as a child process
- user data stored in `~/Library/Application Support/G Play`

## Build

```sh
cd /Users/gauravsdama/git/mediaplayerAPP/g-play-web
./macos/scripts/build_app.sh
```

The app bundle is written to:

```sh
/Users/gauravsdama/git/mediaplayerAPP/g-play-web/.build/macos/G Play.app
```

## Run

```sh
open "/Users/gauravsdama/git/mediaplayerAPP/g-play-web/.build/macos/G Play.app"
```

## Verify With macness

```sh
cd /Users/gauravsdama/git/mediaplayerAPP/g-play-web
./macos/scripts/verify_with_macness.sh
```

`macness` will launch the app, snapshot it, and write verification artifacts under:

```sh
/Users/gauravsdama/git/mediaplayerAPP/g-play-web/.macness/runs
```

The bundled smoke check intentionally avoids screenshot and accessibility assertions so it can run before macOS permissions are granted. After granting permissions, use richer checks like:

```sh
/Users/gauravsdama/git/macness/.build/release/macness verify \
  --bundle-id com.gauravsdama.gplay \
  --expect-window "G Play" \
  --expect-text "G Play"
```

For full screenshots and accessibility assertions, grant the terminal Accessibility and Screen Recording access:

```sh
/Users/gauravsdama/git/macness/.build/release/macness doctor --prompt
```

## Runtime Notes

The native app uses its own data folder:

```sh
~/Library/Application Support/G Play
```

Put a `cookies.txt` file in that folder if you want `yt-dlp` to use browser cookies for downloads.
