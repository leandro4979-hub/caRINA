#!/usr/bin/env python3
"""Estimate token counts for AgentOps text, prompts, and message payloads."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any


DEFAULT_MODEL = "gpt-4o-mini"
DEFAULT_ENCODING = "o200k_base"


def load_tiktoken() -> Any | None:
    try:
        import tiktoken  # type: ignore
    except ImportError:
        return None
    return tiktoken


def estimate_tokens_from_text(text: str) -> int:
    return max(1, math.ceil(len(text) / 4))


def encoding_for(tiktoken: Any, model: str, encoding_name: str) -> Any:
    try:
        return tiktoken.encoding_for_model(model)
    except KeyError:
        return tiktoken.get_encoding(encoding_name)


def count_text(text: str, model: str, encoding_name: str) -> tuple[int, str]:
    tiktoken = load_tiktoken()
    if tiktoken is None:
        return estimate_tokens_from_text(text), "estimated"
    encoding = encoding_for(tiktoken, model, encoding_name)
    return len(encoding.encode(text)), "tiktoken"


def count_messages(messages: list[dict[str, Any]], model: str, encoding_name: str) -> tuple[int, str]:
    tiktoken = load_tiktoken()
    if tiktoken is None:
        chars = sum(len(str(value)) for message in messages for value in message.values())
        return estimate_tokens_from_text("x" * chars) + (4 * len(messages)) + 3, "estimated"

    encoding = encoding_for(tiktoken, model, encoding_name)
    tokens_per_message = 3
    tokens_per_name = 1
    total = 3
    for message in messages:
        total += tokens_per_message
        for key, value in message.items():
            if isinstance(value, str):
                total += len(encoding.encode(value))
            else:
                total += len(encoding.encode(json.dumps(value, separators=(",", ":"))))
            if key == "name":
                total += tokens_per_name
    return total, "tiktoken"


def read_input(args: argparse.Namespace) -> str:
    chunks: list[str] = []
    if args.text:
        chunks.append(args.text)
    for path in args.file or []:
        chunks.append(Path(path).read_text(encoding="utf-8"))
    if not chunks and not sys.stdin.isatty():
        chunks.append(sys.stdin.read())
    return "\n".join(chunks)


def read_json_payload(value: str | None, file_path: str | None) -> Any | None:
    if file_path:
        return json.loads(Path(file_path).read_text(encoding="utf-8"))
    if value:
        return json.loads(value)
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--encoding", default=DEFAULT_ENCODING)
    parser.add_argument("--text")
    parser.add_argument("--file", action="append")
    parser.add_argument("--messages-json")
    parser.add_argument("--messages-file")
    args = parser.parse_args()

    messages = read_json_payload(args.messages_json, args.messages_file)
    if messages is not None:
        if not isinstance(messages, list):
            raise SystemExit("--messages-json/--messages-file must be a JSON list of message objects")
        tokens, method = count_messages(messages, args.model, args.encoding)
    else:
        text = read_input(args)
        if not text:
            raise SystemExit("Provide --text, --file, --messages-json, --messages-file, or stdin")
        tokens, method = count_text(text, args.model, args.encoding)

    print(json.dumps({"tokens": tokens, "method": method, "model": args.model}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
