#!/usr/bin/env python3
"""Carina's macOS-first safe text insertion router.

The command is intentionally usable from Apple Shortcuts: pass a JSON request on
stdin and receive one JSON result on stdout.  Interactive CLI calls show a
preview and wait for confirmation before touching the active application.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Protocol


DEFAULT_CONFIG_PATH = Path("~/.config/carina-type/config.json").expanduser()
SHORT_TEXT_LIMIT = 180


class RouterError(Exception):
    """A request that cannot safely be completed."""


class Clipboard(Protocol):
    def copy(self, value: str) -> None: ...
    def paste(self) -> str: ...


class InputDriver(Protocol):
    def write(self, value: str, interval: float = 0.03) -> None: ...
    def hotkey(self, *keys: str) -> None: ...
    def press(self, key: str) -> None: ...


class AIAdapter(Protocol):
    def generate(self, action: str, text: str, context: str, preset: dict[str, Any]) -> str: ...


class PyperclipClipboard:
    def __init__(self) -> None:
        try:
            import pyperclip
        except ImportError as exc:
            raise RouterError("Clipboard support requires: python3 -m pip install pyperclip") from exc
        self._pyperclip = pyperclip

    def copy(self, value: str) -> None:
        self._pyperclip.copy(value)

    def paste(self) -> str:
        return self._pyperclip.paste()


class PyAutoGUIInput:
    def __init__(self) -> None:
        try:
            import pyautogui
        except ImportError as exc:
            raise RouterError("Typing support requires: python3 -m pip install pyautogui") from exc
        pyautogui.PAUSE = 0.05
        pyautogui.FAILSAFE = True
        self._gui = pyautogui

    def write(self, value: str, interval: float = 0.03) -> None:
        self._gui.write(value, interval=interval)

    def hotkey(self, *keys: str) -> None:
        self._gui.hotkey(*keys)

    def press(self, key: str) -> None:
        self._gui.press(key)


class OpenAIAdapter:
    """Optional adapter. API key is read from macOS Keychain at call time."""

    def __init__(self, settings: dict[str, Any]) -> None:
        self.settings = settings

    def generate(self, action: str, text: str, context: str, preset: dict[str, Any]) -> str:
        try:
            import keyring
            from openai import OpenAI
        except ImportError as exc:
            raise RouterError("AI support requires: python3 -m pip install keyring openai") from exc
        service = self.settings.get("keychain_service", "carina-type")
        account = self.settings.get("keychain_account", "openai_api_key")
        api_key = keyring.get_password(service, account)
        if not api_key:
            raise RouterError(f"No API key in Keychain for service '{service}', account '{account}'")
        instruction = preset.get("instruction") or (
            "Rewrite the supplied text clearly and concisely." if action == "rewrite"
            else "Write a helpful, concise reply to the supplied message."
        )
        response = OpenAI(api_key=api_key).responses.create(
            model=self.settings.get("model", "gpt-4.1-mini"),
            input=f"{instruction}\n\nText:\n{text}\n\nContext:\n{context}",
        )
        return response.output_text.strip()


class PreviewClipboard:
    """Dependency-free placeholder used for a guaranteed non-mutating preview."""
    def copy(self, value: str) -> None:
        raise AssertionError("preview must not write the clipboard")

    def paste(self) -> str:
        raise AssertionError("preview must not read the clipboard")


class PreviewInput:
    def write(self, value: str, interval: float = 0.03) -> None:
        raise AssertionError("preview must not type")

    def hotkey(self, *keys: str) -> None:
        raise AssertionError("preview must not paste")

    def press(self, key: str) -> None:
        raise AssertionError("preview must not navigate fields")


@dataclass
class Request:
    action: str
    text: str | None = None
    template: str | None = None
    profile: str | None = None
    context: str = ""
    mode: str = "auto"
    confirm: bool = True
    preview_only: bool = False
    fields: list[str] | None = None

    @classmethod
    def from_mapping(cls, value: dict[str, Any]) -> "Request":
        if not isinstance(value, dict):
            raise RouterError("Request must be a JSON object")
        action = value.get("action")
        if action not in {"type", "paste", "rewrite", "reply", "fill_form"}:
            raise RouterError("action must be type, paste, rewrite, reply, or fill_form")
        mode = value.get("mode", "auto")
        if mode not in {"auto", "type", "paste"}:
            raise RouterError("mode must be auto, type, or paste")
        fields = value.get("fields")
        if fields is not None and (not isinstance(fields, list) or not all(isinstance(x, str) for x in fields)):
            raise RouterError("fields must be an array of strings")
        for name in ("text", "template", "profile", "context"):
            if name in value and value[name] is not None and not isinstance(value[name], str):
                raise RouterError(f"{name} must be a string")
        if "confirm" in value and not isinstance(value["confirm"], bool):
            raise RouterError("confirm must be a boolean")
        if "preview_only" in value and not isinstance(value["preview_only"], bool):
            raise RouterError("preview_only must be a boolean")
        return cls(action=action, text=value.get("text"), template=value.get("template"),
                   profile=value.get("profile"), context=value.get("context", ""), mode=mode,
                   confirm=value.get("confirm", True), preview_only=value.get("preview_only", False), fields=fields)


def load_config(path: Path = DEFAULT_CONFIG_PATH) -> dict[str, Any]:
    if not path.exists():
        return {"templates": {}, "profiles": {}, "forms": {}, "ai": {"provider": "openai"}, "clipboard_restore": True}
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise RouterError(f"Unable to read config: {exc}") from exc
    if not isinstance(data, dict):
        raise RouterError("Config root must be a JSON object")
    return data


def resolve_text(request: Request, config: dict[str, Any], ai: AIAdapter | None) -> str:
    if request.template:
        try:
            text = config.get("templates", {})[request.template]
        except KeyError as exc:
            raise RouterError(f"Unknown template: {request.template}") from exc
    else:
        text = request.text
    if request.action == "fill_form":
        return text or ""
    if not text:
        raise RouterError("text or template is required")
    if request.action in {"rewrite", "reply"}:
        if ai is None:
            raise RouterError("AI is not configured")
        preset = config.get("profiles", {}).get(request.profile or request.action, {})
        if not isinstance(preset, dict):
            raise RouterError("Profile must be an object")
        return ai.generate(request.action, text, request.context, preset)
    return text


def choose_mode(request: Request, text: str) -> str:
    if request.mode != "auto":
        return request.mode
    if request.action == "type":
        return "type"
    if request.action == "paste":
        return "paste"
    # pyautogui.write is not reliable for Unicode and multiline payloads.
    return "type" if text.isascii() and "\n" not in text and len(text) <= SHORT_TEXT_LIMIT else "paste"


@dataclass
class Router:
    clipboard: Clipboard
    input: InputDriver
    config: dict[str, Any]
    ai: AIAdapter | None = None
    confirm_fn: Any = field(default=None)
    sleep_fn: Any = time.sleep

    def _confirm(self, action: str, preview: str, requested: bool) -> bool:
        if not requested:
            return True
        if self.confirm_fn:
            return bool(self.confirm_fn(action, preview))
        print(f"\n--- Carina preview ({action}) ---\n{preview}\n--- end preview ---")
        try:
            return input("Insert into the focused app? [y/N] ").strip().lower() in {"y", "yes"}
        except (EOFError, KeyboardInterrupt):
            return False

    def _paste(self, text: str) -> None:
        prior = self.clipboard.paste()
        try:
            self.clipboard.copy(text)
            self.input.hotkey("command", "v")
            # Keep the new clipboard value available while the receiving app
            # handles the keyboard event, then restore the user's clipboard.
            self.sleep_fn(float(self.config.get("paste_settle_seconds", 0.15)))
        finally:
            if self.config.get("clipboard_restore", True):
                self.clipboard.copy(prior)

    def run(self, request: Request) -> dict[str, Any]:
        if request.action == "fill_form":
            fields = request.fields
            if fields is None and request.template:
                fields = self.config.get("forms", {}).get(request.template)
            if not fields:
                raise RouterError("fill_form requires fields or a named form template")
            preview = "\n".join(f"{index + 1}. {value}" for index, value in enumerate(fields))
            if request.preview_only:
                return {"status": "preview", "action": request.action, "preview": preview, "mode": "paste"}
            if not self._confirm("fill_form", preview, request.confirm):
                return {"status": "cancelled", "action": request.action, "preview": preview}
            for index, value in enumerate(fields):
                self._paste(value)
                if index < len(fields) - 1:
                    self.input.press("tab")
            return {"status": "confirmed", "action": request.action, "preview": preview, "mode": "paste"}
        text = resolve_text(request, self.config, self.ai)
        mode = choose_mode(request, text)
        if request.preview_only:
            return {"status": "preview", "action": request.action, "preview": text, "mode": mode}
        if not self._confirm(request.action, text, request.confirm):
            return {"status": "cancelled", "action": request.action, "preview": text, "mode": mode}
        if mode == "type":
            self.input.write(text)
        else:
            self._paste(text)
        return {"status": "confirmed", "action": request.action, "preview": text, "mode": mode}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="carina-type")
    p.add_argument("action", nargs="?", choices=["type", "paste", "rewrite", "reply", "fill_form"])
    p.add_argument("--text")
    p.add_argument("--template")
    p.add_argument("--profile")
    p.add_argument("--context", default="")
    p.add_argument("--mode", choices=["auto", "type", "paste"], default="auto")
    p.add_argument("--confirm", action=argparse.BooleanOptionalAction, default=True)
    p.add_argument("--preview", action="store_true", help="Return resolved text without inserting it")
    p.add_argument("--fields", help="JSON string array used by fill_form")
    p.add_argument("--json", action="store_true", help="Read one JSON request from stdin")
    p.add_argument("--config", type=Path, default=DEFAULT_CONFIG_PATH)
    return p


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        raw = json.load(sys.stdin) if args.json else {
            "action": args.action, "text": args.text, "template": args.template, "profile": args.profile,
            "context": args.context, "mode": args.mode, "confirm": args.confirm,
            "preview_only": args.preview,
            "fields": json.loads(args.fields) if args.fields else None,
        }
        request = Request.from_mapping(raw)
        config = load_config(args.config)
        ai = OpenAIAdapter(config.get("ai", {})) if request.action in {"rewrite", "reply"} else None
        clipboard: Clipboard = PreviewClipboard() if request.preview_only else PyperclipClipboard()
        input_driver: InputDriver = PreviewInput() if request.preview_only else PyAutoGUIInput()
        result = Router(clipboard, input_driver, config, ai).run(request)
        print(json.dumps(result))
        return 0
    except (RouterError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "error", "error": str(exc)}))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
