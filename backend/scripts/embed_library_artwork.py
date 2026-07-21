from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

from app.engine.artwork import embed_library_artwork  # noqa: E402


def default_library_dir() -> Path:
    configured = os.environ.get("VANTABEAT_LIBRARY_DIR")
    if configured:
        return Path(configured)
    return Path.home() / "Library" / "Application Support" / "vantabeat" / "library"


def main() -> int:
    parser = argparse.ArgumentParser(description="Embed Vantabeat artwork sidecars into audio files.")
    parser.add_argument("--library-dir", type=Path, default=default_library_dir())
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-existing", action="store_true", help="Skip files that already have embedded artwork.")
    parser.add_argument(
        "--no-download-missing",
        action="store_true",
        help="Only use existing .artwork sidecars; do not fetch missing cover art from saved metadata thumbnails.",
    )
    args = parser.parse_args()

    summary = embed_library_artwork(
        args.library_dir,
        force=not args.skip_existing,
        dry_run=args.dry_run,
        download_missing=not args.no_download_missing,
    )
    print(json.dumps(summary, indent=2, ensure_ascii=True))
    return 1 if summary["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
