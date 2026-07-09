# vantabeat for macOS

This folder packages vantabeat as a native SwiftUI macOS app backed by a bundled local Python media engine.

The current architecture is:

- SwiftUI app shell
- native SwiftUI navigation, library, player, imports, playlists, EQ, and visualiser views
- bundled Python media engine launched as a child process
- per-launch local API token shared only between Swift and the child process
- user data stored in `~/Library/Application Support/vantabeat`

## Build

```sh
cd /Users/gauravsdama/git/mediaplayerAPP/g-play-web
./macos/scripts/build_app.sh
```

The app bundle is written to:

```sh
/Users/gauravsdama/git/mediaplayerAPP/g-play-web/.build/macos/vantabeat.app
```

To opt into repo-local runtime folders while developing, build with:

```sh
VANTABEAT_DEV_DATA_ROOT=1 ./macos/scripts/build_app.sh
```

## Run

```sh
open "/Users/gauravsdama/git/mediaplayerAPP/g-play-web/.build/macos/vantabeat.app"
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
  --bundle-id com.gauravsdama.vantabeat \
  --expect-window "vantabeat" \
  --expect-text "vantabeat"
```

For full screenshots and accessibility assertions, grant the terminal Accessibility and Screen Recording access:

```sh
/Users/gauravsdama/git/macness/.build/release/macness doctor --prompt
```

## Runtime Notes

The app uses its own data folder:

```sh
~/Library/Application Support/vantabeat
```

Put a `cookies.txt` file in that folder if you want `yt-dlp` to use browser cookies for imports.

Supported local audio containers include `.aac`, `.m4a`, `.mp3`, `.flac`, `.wav`, `.ogg`, `.opus`, and `.webm`.
