#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
RUNTIME_ROOT="$HOME/Library/Application Support/CARINA/dashboard"
SOURCE_ROOT="$RUNTIME_ROOT/sources"
LOG_ROOT="$HOME/Library/Logs/CARINA"
PLIST="$HOME/Library/LaunchAgents/com.leandrofajardo.carina.dashboard.plist"
LABEL="com.leandrofajardo.carina.dashboard"
DOMAIN="gui/$(id -u)"
AGENTOPS_SOURCE="$HOME/Documents/AgentOps"
CODEX_SOURCE="$HOME/Documents/Codex"

/bin/mkdir -p "$RUNTIME_ROOT/dist" "$SOURCE_ROOT/AgentOps" "$SOURCE_ROOT/Codex" "$LOG_ROOT" "$HOME/Library/LaunchAgents"
/bin/chmod 700 "$RUNTIME_ROOT" "$SOURCE_ROOT"
/usr/bin/install -m 700 "$PROJECT_ROOT/src/build_dashboard.py" "$RUNTIME_ROOT/build_dashboard.py"
/usr/bin/install -m 700 "$PROJECT_ROOT/scripts/carina_dashboard_service.py" "$RUNTIME_ROOT/carina_dashboard_service.py"

if [[ -d "$AGENTOPS_SOURCE" ]]; then
    /usr/bin/rsync -a --delete --include='*.md' --exclude='*' "$AGENTOPS_SOURCE/" "$SOURCE_ROOT/AgentOps/"
fi
if [[ -f "$CODEX_SOURCE/_archive/2026-07-04-agentops-review/manifest.json" ]]; then
    /bin/mkdir -p "$SOURCE_ROOT/Codex/_archive/2026-07-04-agentops-review"
    /usr/bin/install -m 600 "$CODEX_SOURCE/_archive/2026-07-04-agentops-review/manifest.json" \
        "$SOURCE_ROOT/Codex/_archive/2026-07-04-agentops-review/manifest.json"
fi

/usr/bin/python3 "$PROJECT_ROOT/src/build_dashboard.py" \
    --agentops-dir "$AGENTOPS_SOURCE" \
    --codex-dir "$CODEX_SOURCE" \
    --write-project-snapshot "$RUNTIME_ROOT/projects.json" \
    --output "$RUNTIME_ROOT/dist/dashboard.html"
/bin/chmod 600 "$RUNTIME_ROOT/projects.json" "$RUNTIME_ROOT/dist/dashboard.html"

/usr/bin/python3 - "$PLIST" "$RUNTIME_ROOT" "$LOG_ROOT" <<'PY'
import plistlib
import sys
from pathlib import Path

plist_path = Path(sys.argv[1])
runtime_root = sys.argv[2]
log_root = sys.argv[3]
payload = {
    "Label": "com.leandrofajardo.carina.dashboard",
    "ProgramArguments": [
        "/usr/bin/python3",
        f"{runtime_root}/carina_dashboard_service.py",
        "--runtime-root",
        runtime_root,
        "--host",
        "127.0.0.1",
        "--port",
        "51003",
    ],
    "RunAtLoad": True,
    "KeepAlive": {"SuccessfulExit": False},
    "ThrottleInterval": 10,
    "ProcessType": "Background",
    "StandardOutPath": f"{log_root}/dashboard.out.log",
    "StandardErrorPath": f"{log_root}/dashboard.err.log",
}
with plist_path.open("wb") as handle:
    plistlib.dump(payload, handle, sort_keys=True)
plist_path.chmod(0o600)
PY

/bin/launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
/bin/launchctl bootstrap "$DOMAIN" "$PLIST"
/bin/launchctl kickstart -k "$DOMAIN/$LABEL"
/bin/sleep 2
/usr/bin/open "http://127.0.0.1:51003/"
/bin/launchctl print "$DOMAIN/$LABEL" | /usr/bin/head -n 38
