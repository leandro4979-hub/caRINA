#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
from datetime import datetime
from pathlib import Path


PROJECT_ROOT = Path(
    os.environ.get("CARINA_PROJECT_ROOT", Path(__file__).resolve().parents[1])
).expanduser().resolve()
DEFAULT_LOG_PATH = PROJECT_ROOT / "System_Update_Log.md"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Append a timestamped system update block")
    parser.add_argument("--log-file", type=Path, default=DEFAULT_LOG_PATH)
    parser.add_argument("--state", action="append", default=[])
    parser.add_argument("--next-step", action="append", default=[])
    return parser.parse_args()


def ensure_blank_line(lines: list[str]) -> None:
    if lines and lines[-1] != "":
        lines.append("")


def append_block(log_path: Path, state_items: list[str], next_step_items: list[str]) -> None:
    timestamp = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
    lines = log_path.read_text(encoding="utf-8").splitlines() if log_path.exists() else []

    ensure_blank_line(lines)
    lines.append(f"## {timestamp}")
    lines.append("### Current State")
    if state_items:
        lines.extend(f"- {item}" for item in state_items)
    else:
        lines.append("- ")
    lines.append("")
    lines.append("### Next Steps")
    if next_step_items:
        lines.extend(f"- {item}" for item in next_step_items)
    else:
        lines.append("- ")
    lines.append("")

    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    append_block(args.log_file, args.state, args.next_step)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())