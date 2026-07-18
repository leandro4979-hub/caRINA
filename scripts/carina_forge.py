#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import re
import sys
import time
from pathlib import Path
from typing import Iterable


PROJECT_ROOT = Path(
    os.environ.get("CARINA_PROJECT_ROOT", Path(__file__).resolve().parents[1])
).expanduser().resolve()
BRIDGE_ROOT = PROJECT_ROOT / "apps/bridge"
for import_root in (Path(__file__).resolve().parent, BRIDGE_ROOT):
    if str(import_root) not in sys.path:
        sys.path.insert(0, str(import_root))

from forge_store import ForgeDocument, ForgeStore  # noqa: E402


LOGGER = logging.getLogger("CarinaForge")
MAX_SOURCE_BYTES = 2_000_000
MAX_INDEXED_CHARACTERS = 200_000
SUPPORTED_SUFFIXES = frozenset(
    {".md", ".txt", ".json", ".jsonl", ".yaml", ".yml", ".toml", ".csv"}
)
SECRET_PATTERNS = (
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b"),
    re.compile(r"\bBearer\s+[A-Za-z0-9._~+/=-]{20,}", re.IGNORECASE),
    re.compile(
        r"\b(?:OPENAI_API_KEY|OPENCLAW_TOKEN|CARINA_BRIDGE_TOKEN)\s*=\s*['\"]?(?!\$\{|replace|your[_ -]?key|example)[^\s'\"]{16,}",
        re.IGNORECASE,
    ),
)


def default_sources() -> list[Path]:
    home_documents = Path.home() / "Documents"
    return [
        home_documents / "CARINA-Workspace/00-Inbox",
        PROJECT_ROOT / "README.md",
        PROJECT_ROOT / "HANDOFF.md",
        PROJECT_ROOT / "docs",
        home_documents / "AgentOps",
    ]


def discover_files(sources: Iterable[Path]) -> list[Path]:
    discovered: set[Path] = set()
    for source in sources:
        candidate = source.expanduser().resolve()
        if candidate.is_file() and candidate.suffix.casefold() in SUPPORTED_SUFFIXES:
            discovered.add(candidate)
            continue
        if not candidate.is_dir():
            LOGGER.warning("source unavailable: %s", candidate)
            continue
        for path in candidate.rglob("*"):
            if not path.is_file() or path.is_symlink():
                continue
            if path.suffix.casefold() not in SUPPORTED_SUFFIXES:
                continue
            if any(part.startswith(".") for part in path.relative_to(candidate).parts):
                continue
            discovered.add(path.resolve())
    return sorted(discovered, key=lambda item: str(item).casefold())


def contains_secret(text: str) -> bool:
    return any(pattern.search(text) for pattern in SECRET_PATTERNS)


def ingest_file(store: ForgeStore, path: Path) -> str:
    size = path.stat().st_size
    if size > MAX_SOURCE_BYTES:
        LOGGER.warning("source exceeds %d bytes: %s", MAX_SOURCE_BYTES, path)
        return "oversized"
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        LOGGER.warning("source is not UTF-8 text: %s", path)
        return "invalid"
    trust_state = "quarantined" if contains_secret(text) else "ready"
    indexed_text = text[:MAX_INDEXED_CHARACTERS]
    document = ForgeDocument.from_text(
        source_path=str(path),
        title=path.stem.replace("_", " ").replace("-", " "),
        kind=path.suffix.casefold().lstrip(".") or "text",
        text=indexed_text,
        trust_state=trust_state,
    )
    full_hash = hashlib.sha256(text.encode("utf-8")).hexdigest()
    if size != document.size_bytes or full_hash != document.sha256:
        document = ForgeDocument(
            source_path=document.source_path,
            title=document.title,
            kind=document.kind,
            sha256=full_hash,
            size_bytes=size,
            trust_state=document.trust_state,
            excerpt=document.excerpt,
            content=document.content,
        )
    outcome = store.upsert(document)
    return "quarantined" if trust_state == "quarantined" and outcome != "unchanged" else outcome


def ingest_sources(store: ForgeStore, sources: Iterable[Path]) -> dict[str, object]:
    started = time.monotonic()
    outcomes = {"inserted": 0, "updated": 0, "unchanged": 0, "quarantined": 0, "oversized": 0, "invalid": 0, "failed": 0}
    files = discover_files(sources)
    for path in files:
        try:
            outcome = ingest_file(store, path)
            outcomes[outcome] = outcomes.get(outcome, 0) + 1
        except (OSError, ValueError) as exc:
            outcomes["failed"] += 1
            LOGGER.error("ingest failed for %s: %s", path, type(exc).__name__)
    duration_ms = round((time.monotonic() - started) * 1000)
    success = outcomes["failed"] == 0
    store.record_operation("forge-ingest", success, duration_ms, len(files), json.dumps(outcomes, sort_keys=True))
    return {
        "success": success,
        "duration_ms": duration_ms,
        "files_seen": len(files),
        "outcomes": outcomes,
        "status": store.status(),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Safe CARINA Forge document ingestion")
    parser.add_argument("command", choices=("ingest", "status", "search"))
    parser.add_argument("query", nargs="?", default="")
    parser.add_argument("--source", action="append", type=Path, default=[])
    parser.add_argument("--limit", type=int, default=5)
    return parser.parse_args()


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
    args = parse_args()
    store = ForgeStore()
    if args.command == "ingest":
        result = ingest_sources(store, args.source or default_sources())
    elif args.command == "status":
        result = store.status()
    else:
        if not args.query.strip():
            raise SystemExit("search requires a query")
        result = {"query": args.query, "results": store.search(args.query, args.limit)}
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if not isinstance(result, dict) or result.get("success", True) else 1


if __name__ == "__main__":
    raise SystemExit(main())
