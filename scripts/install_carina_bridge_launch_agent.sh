#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.leandrofajardo.carina.bridge"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/CARINA"
RUNTIME="$HOME/Library/Application Support/CARINA"
VENV="$RUNTIME/.venv"
ENV_FILE="${CARINA_OPENAI_ENV_FILE:-}"

if [[ -z "$ENV_FILE" ]]; then
  ENV_FILE="$(find "$HOME/Documents" -path '*/maya-listener-py/.env.local' -type f -print -quit 2>/dev/null)"
fi

if [[ -z "$ENV_FILE" || ! -f "$ENV_FILE" ]]; then
  print -u2 "No existing Maya/Karina .env.local was found. Set CARINA_OPENAI_ENV_FILE and retry."
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR" "$RUNTIME/bridge"
rsync -a --delete "$ROOT/apps/bridge/" "$RUNTIME/bridge/"

if [[ ! -x "$VENV/bin/python" ]]; then
  /usr/bin/python3 -m venv "$VENV"
fi
"$VENV/bin/python" -m pip install --disable-pip-version-check --quiet -r "$RUNTIME/bridge/requirements.txt"
"$VENV/bin/python" -m py_compile "$RUNTIME/bridge/api.py" "$RUNTIME/bridge/websocket_server.py" "$RUNTIME/bridge/carina_bridge.py"

RUNTIME="$RUNTIME" PLIST="$PLIST" LOG_DIR="$LOG_DIR" ENV_FILE="$ENV_FILE" "$VENV/bin/python" - <<'PY'
import os
import plistlib
from pathlib import Path

runtime = Path(os.environ["RUNTIME"])
payload = {
    "Label": "com.leandrofajardo.carina.bridge",
    "ProgramArguments": [
        str(runtime / ".venv/bin/python"),
        str(runtime / "bridge/carina_bridge.py"),
    ],
    "WorkingDirectory": str(runtime),
    "EnvironmentVariables": {
        "CARINA_OPENAI_ENV_FILE": os.environ["ENV_FILE"],
        "CARINA_STATE_ROOT": str(runtime),
        "PYTHONUNBUFFERED": "1",
    },
    "RunAtLoad": True,
    "KeepAlive": {"SuccessfulExit": False},
    "ThrottleInterval": 10,
    "StandardOutPath": str(Path(os.environ["LOG_DIR"]) / "bridge.log"),
    "StandardErrorPath": str(Path(os.environ["LOG_DIR"]) / "bridge-error.log"),
    "ProcessType": "Interactive",
}
with Path(os.environ["PLIST"]).open("wb") as handle:
    plistlib.dump(payload, handle, sort_keys=True)
PY

chmod 600 "$PLIST"
launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$PLIST"
launchctl kickstart -k "gui/$UID/$LABEL"
print "CARINA bridge LaunchAgent installed and started."
