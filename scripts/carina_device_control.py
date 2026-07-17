#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


APPIUM_URL = "http://127.0.0.1:4723"
DEVICE_NAME = "leandros 17pro max"
BUNDLE_ID = "com.leandrofajardo.carina"
TEAM_ID = "S6FYTWBGVH"
WDA_BUNDLE_ID = "com.leandrofajardo.carina.WebDriverAgentRunner"
STATE_DIR = Path.home() / "Library/Application Support/CARINA"
SESSION_PATH = STATE_DIR / "appium-session.json"
XCODE_DEVELOPER_DIR = Path.home() / "Downloads/Xcode-beta.app/Contents/Developer"


class DeviceControlError(RuntimeError):
    pass


def appium_request(method: str, path: str, body: dict[str, Any] | None = None, timeout: int = 240) -> dict[str, Any]:
    data = json.dumps(body).encode("utf-8") if body is not None else None
    request = urllib.request.Request(
        f"{APPIUM_URL}{path}", data=data, headers={"Content-Type": "application/json"}, method=method
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            decoded = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        decoded = json.loads(error.read().decode("utf-8"))
    except (OSError, urllib.error.URLError) as error:
        raise DeviceControlError(f"Appium is unavailable: {type(error).__name__}") from error
    if not isinstance(decoded, dict):
        raise DeviceControlError("Appium returned an invalid response")
    value = decoded.get("value")
    if isinstance(value, dict) and value.get("error"):
        raise DeviceControlError(str(value.get("message", value["error"])))
    return decoded


def discover_device() -> tuple[str, str]:
    environment = os.environ.copy()
    environment.setdefault("DEVELOPER_DIR", str(XCODE_DEVELOPER_DIR))
    with tempfile.NamedTemporaryFile(prefix="carina-devices-", suffix=".json") as output:
        completed = subprocess.run(
            ["xcrun", "devicectl", "list", "devices", "--json-output", output.name],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
            env=environment,
        )
        if completed.returncode != 0:
            raise DeviceControlError("devicectl could not list devices")
        output.seek(0)
        payload = json.load(output)
    for device in payload.get("result", {}).get("devices", []):
        properties = device.get("properties", {})
        hardware = properties.get("hardware", {})
        state = properties.get("state", {})
        software = properties.get("software", {})
        if state.get("name") == DEVICE_NAME and hardware.get("reality") == "physical" and hardware.get("platform") == "iOS":
            udid = hardware.get("udid")
            version = software.get("osVersionNumber", {}).get("stringValue")
            if isinstance(udid, str) and isinstance(version, str):
                return udid, version
    raise DeviceControlError(f"physical device '{DEVICE_NAME}' is unavailable")


def save_session(session_id: str) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(SESSION_PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as output:
        json.dump({"session_id": session_id}, output)
        output.write("\n")


def load_session() -> str:
    try:
        payload = json.loads(SESSION_PATH.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError) as error:
        raise DeviceControlError("no CARINA device-control session is saved") from error
    session_id = payload.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        raise DeviceControlError("saved device-control session is invalid")
    return session_id


def start_session() -> None:
    udid, platform_version = discover_device()
    payload = {
        "capabilities": {
            "alwaysMatch": {
                "platformName": "iOS",
                "appium:automationName": "XCUITest",
                "appium:deviceName": DEVICE_NAME,
                "appium:platformVersion": platform_version,
                "appium:udid": udid,
                "appium:bundleId": BUNDLE_ID,
                "appium:xcodeOrgId": TEAM_ID,
                "appium:xcodeSigningId": "Apple Development",
                "appium:updatedWDABundleId": WDA_BUNDLE_ID,
                "appium:allowProvisioningDeviceRegistration": True,
                "appium:showXcodeLog": True,
                "appium:useNewWDA": True,
                "appium:wdaLaunchTimeout": 180_000,
                "appium:wdaConnectionTimeout": 180_000,
                "appium:noReset": True,
            },
            "firstMatch": [{}],
        }
    }
    response = appium_request("POST", "/session", payload)
    session_id = response.get("value", {}).get("sessionId") or response.get("sessionId")
    if not isinstance(session_id, str) or not session_id:
        raise DeviceControlError("Appium did not return a session identifier")
    save_session(session_id)
    print("CARINA device-control session started.")


def session_status() -> None:
    session_id = load_session()
    appium_request("GET", f"/session/{session_id}", timeout=15)
    print("CARINA device-control session is active.")


def tap(x: int, y: int) -> None:
    if x < 0 or y < 0:
        raise DeviceControlError("tap coordinates must be non-negative")
    session_id = load_session()
    actions = {"actions": [{"type": "pointer", "id": "carina-finger", "parameters": {"pointerType": "touch"}, "actions": [
        {"type": "pointerMove", "duration": 0, "x": x, "y": y},
        {"type": "pointerDown", "button": 0},
        {"type": "pause", "duration": 80},
        {"type": "pointerUp", "button": 0},
    ]}]}
    appium_request("POST", f"/session/{session_id}/actions", actions, timeout=30)
    print(f"Tapped ({x}, {y}) in CARINA.")


def screenshot(path: Path) -> None:
    session_id = load_session()
    response = appium_request("GET", f"/session/{session_id}/screenshot", timeout=30)
    encoded = response.get("value")
    if not isinstance(encoded, str):
        raise DeviceControlError("Appium did not return a screenshot")
    path = path.expanduser().resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(base64.b64decode(encoded, validate=True))
    print(path)


def stop_session() -> None:
    session_id = load_session()
    appium_request("DELETE", f"/session/{session_id}", timeout=30)
    SESSION_PATH.unlink(missing_ok=True)
    print("CARINA device-control session stopped.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Control CARINA on a paired physical iPhone through Appium/XCTest")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("start")
    commands.add_parser("status")
    tap_parser = commands.add_parser("tap")
    tap_parser.add_argument("x", type=int)
    tap_parser.add_argument("y", type=int)
    screenshot_parser = commands.add_parser("screenshot")
    screenshot_parser.add_argument("path", type=Path)
    commands.add_parser("stop")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "start":
            start_session()
        elif args.command == "status":
            session_status()
        elif args.command == "tap":
            tap(args.x, args.y)
        elif args.command == "screenshot":
            screenshot(args.path)
        elif args.command == "stop":
            stop_session()
    except DeviceControlError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
