#!/usr/bin/env python3
"""Archive old Codex session folders without deleting data."""

from __future__ import annotations

import argparse
import json
import shutil
from datetime import datetime
from pathlib import Path

from build_dashboard import DEFAULT_CODEX_DIR, collect_codex_folders


DEFAULT_ARCHIVE_DIR = DEFAULT_CODEX_DIR / "_archive" / "2026-07-04-agentops-review"


def unique_destination(path: Path) -> Path:
    if not path.exists():
        return path
    counter = 2
    while True:
        candidate = path.with_name(f"{path.name}-{counter}")
        if not candidate.exists():
            return candidate
        counter += 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Archive non-keep dated Codex folders.")
    parser.add_argument("--archive-dir", type=Path, default=DEFAULT_ARCHIVE_DIR)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    folders = collect_codex_folders(DEFAULT_CODEX_DIR)
    selected = [folder for folder in folders if folder.status != "keep"]
    manifest = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "mode": "dry-run" if args.dry_run else "archive",
        "archive_dir": str(args.archive_dir),
        "items": [],
    }

    for folder in selected:
        destination = unique_destination(args.archive_dir / folder.date / folder.name)
        manifest["items"].append(
            {
                "source": str(folder.path),
                "destination": str(destination),
                "status": folder.status,
                "reason": folder.reason,
                "files": folder.files,
                "size_bytes": folder.size_bytes,
            }
        )
        if not args.dry_run:
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(folder.path), str(destination))

    manifest_path = args.archive_dir / "manifest.json"
    if not args.dry_run:
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

