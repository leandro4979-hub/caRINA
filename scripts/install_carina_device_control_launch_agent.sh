#!/bin/zsh
set -euo pipefail

LABEL="com.leandrofajardo.carina.device-control"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/CARINA"
APPIUM="$HOME/.local/bin/appium"
DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer"

[[ -x "$APPIUM" ]] || { print -u2 "Appium is not installed at $APPIUM"; exit 1; }
[[ -d "$DEVELOPER_DIR" ]] || { print -u2 "Xcode developer directory is missing: $DEVELOPER_DIR"; exit 1; }

mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"
PLIST="$PLIST" APPIUM="$APPIUM" LOG_DIR="$LOG_DIR" DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/python3 - <<'PY'
import os
import plistlib
from pathlib import Path

payload = {
    "Label": "com.leandrofajardo.carina.device-control",
    "ProgramArguments": [os.environ["APPIUM"], "--address", "127.0.0.1", "--port", "4723", "--base-path", "/", "--log-timestamp"],
    "EnvironmentVariables": {
        "APPIUM_XCUITEST_PREFER_DEVICECTL": "true",
        "DEVELOPER_DIR": os.environ["DEVELOPER_DIR"],
        "PATH": f"{Path.home()}/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    },
    "RunAtLoad": True,
    "KeepAlive": {"SuccessfulExit": False},
    "ThrottleInterval": 10,
    "StandardOutPath": str(Path(os.environ["LOG_DIR"]) / "device-control.log"),
    "StandardErrorPath": str(Path(os.environ["LOG_DIR"]) / "device-control-error.log"),
}
with Path(os.environ["PLIST"]).open("wb") as output:
    plistlib.dump(payload, output, sort_keys=True)
PY

xattr -d com.apple.provenance "$PLIST" >/dev/null 2>&1 || true
chmod 644 "$PLIST"
launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$PLIST"
launchctl kickstart -k "gui/$UID/$LABEL"
print "CARINA device-control Appium service installed on 127.0.0.1:4723."
