#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
RUNTIME_ROOT="$HOME/Library/Application Support/CARINA/forge"
BIN_ROOT="$RUNTIME_ROOT/bin"
SOURCE_ROOT="$RUNTIME_ROOT/sources"
INBOX_ROOT="$RUNTIME_ROOT/inbox"
LOG_ROOT="$HOME/Library/Logs/CARINA"
PLIST="$HOME/Library/LaunchAgents/com.leandrofajardo.carina.forge.plist"
DOMAIN="gui/$(id -u)"
LABEL="com.leandrofajardo.carina.forge"

/bin/mkdir -p "$BIN_ROOT" "$SOURCE_ROOT/docs" "$INBOX_ROOT" "$LOG_ROOT" "$HOME/Library/LaunchAgents"
/bin/chmod 700 "$RUNTIME_ROOT" "$BIN_ROOT" "$SOURCE_ROOT" "$INBOX_ROOT"
/usr/bin/install -m 700 "$PROJECT_ROOT/scripts/carina_forge.py" "$BIN_ROOT/carina_forge.py"
/usr/bin/install -m 600 "$PROJECT_ROOT/apps/bridge/forge_store.py" "$BIN_ROOT/forge_store.py"
/usr/bin/install -m 600 "$PROJECT_ROOT/README.md" "$SOURCE_ROOT/README.md"
/usr/bin/install -m 600 "$PROJECT_ROOT/HANDOFF.md" "$SOURCE_ROOT/HANDOFF.md"
if [[ -d "$PROJECT_ROOT/docs" ]]; then
    /usr/bin/rsync -a --delete --include='*/' --include='*.md' --exclude='*' "$PROJECT_ROOT/docs/" "$SOURCE_ROOT/docs/"
fi

/usr/bin/python3 - "$PLIST" "$PROJECT_ROOT" "$BIN_ROOT" "$SOURCE_ROOT" "$INBOX_ROOT" "$LOG_ROOT" <<'PY'
import plistlib
import sys
from pathlib import Path

plist_path = Path(sys.argv[1])
project_root = sys.argv[2]
bin_root = sys.argv[3]
source_root = sys.argv[4]
inbox_root = sys.argv[5]
log_root = sys.argv[6]
payload = {
    "Label": "com.leandrofajardo.carina.forge",
    "ProgramArguments": [
        "/usr/bin/python3",
        f"{bin_root}/carina_forge.py",
        "ingest",
        "--source",
        source_root,
        "--source",
        inbox_root,
    ],
    "EnvironmentVariables": {"CARINA_PROJECT_ROOT": project_root},
    "RunAtLoad": True,
    "StartInterval": 300,
    "ProcessType": "Background",
    "LowPriorityIO": True,
    "StandardOutPath": f"{log_root}/forge.out.log",
    "StandardErrorPath": f"{log_root}/forge.err.log",
}
with plist_path.open("wb") as handle:
    plistlib.dump(payload, handle, sort_keys=True)
plist_path.chmod(0o600)
PY

/bin/launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
/bin/launchctl bootstrap "$DOMAIN" "$PLIST"
/bin/launchctl kickstart -k "$DOMAIN/$LABEL"
/bin/sleep 1
/bin/launchctl print "$DOMAIN/$LABEL" | /usr/bin/head -n 35
