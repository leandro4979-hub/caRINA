#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$ROOT/.venv"
PYTHON="${PYTHON:-/usr/bin/python3}"

if [[ ! -x "$VENV/bin/python" ]]; then
  "$PYTHON" -m venv "$VENV"
fi

"$VENV/bin/python" -m pip install --disable-pip-version-check --quiet --upgrade pip
"$VENV/bin/python" -m pip install --disable-pip-version-check --quiet -r "$ROOT/apps/bridge/requirements.txt"
"$VENV/bin/python" -m py_compile "$ROOT/apps/bridge/api.py" "$ROOT/apps/bridge/websocket_server.py" "$ROOT/apps/bridge/carina_bridge.py"
print "CARINA bridge environment is ready."
