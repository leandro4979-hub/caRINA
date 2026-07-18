#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
RUNTIME_ROOT="$HOME/Library/Application Support/CARINA/deployment"
SNAPSHOT_ROOT="$RUNTIME_ROOT/project"
DERIVED_DATA="$RUNTIME_ROOT/DerivedData"
LOG_ROOT="$HOME/Library/Logs/CARINA"
PLIST="$HOME/Library/LaunchAgents/com.leandrofajardo.carina.deployment-guardian.plist"
LABEL="com.leandrofajardo.carina.deployment-guardian"
DOMAIN="gui/$(id -u)"
REVISION="$(git -C "$PROJECT_ROOT" rev-parse HEAD:apps/ios)"
CURRENT_APP="/tmp/CARINA-DerivedData/Build/Products/Debug-iphoneos/Carina.app"
RUNTIME_APP="$DERIVED_DATA/Build/Products/Debug-iphoneos/Carina.app"

/bin/mkdir -p "$SNAPSHOT_ROOT/apps" "$DERIVED_DATA" "$LOG_ROOT" "$HOME/Library/LaunchAgents"
/bin/chmod 700 "$RUNTIME_ROOT" "$SNAPSHOT_ROOT" "$DERIVED_DATA"
/usr/bin/rsync -a --delete --exclude='.DerivedData' --exclude='DerivedData' \
    "$PROJECT_ROOT/apps/ios/" "$SNAPSHOT_ROOT/apps/ios/"
/usr/bin/install -m 700 "$PROJECT_ROOT/scripts/carina_deployment_guardian.py" \
    "$RUNTIME_ROOT/carina_deployment_guardian.py"

if [[ ! -d "$RUNTIME_APP" && -d "$CURRENT_APP" ]]; then
    /bin/mkdir -p "${RUNTIME_APP:h}"
    /usr/bin/ditto --norsrc "$CURRENT_APP" "$RUNTIME_APP"
fi

/usr/bin/python3 - "$PLIST" "$RUNTIME_ROOT" "$SNAPSHOT_ROOT" "$LOG_ROOT" "$REVISION" <<'PY'
import plistlib
import sys
from pathlib import Path

plist_path = Path(sys.argv[1])
runtime_root = sys.argv[2]
snapshot_root = sys.argv[3]
log_root = sys.argv[4]
revision = sys.argv[5]
payload = {
    "Label": "com.leandrofajardo.carina.deployment-guardian",
    "ProgramArguments": ["/usr/bin/python3", f"{runtime_root}/carina_deployment_guardian.py", "run"],
    "EnvironmentVariables": {
        "CARINA_DEPLOYMENT_ROOT": runtime_root,
        "CARINA_DEPLOYMENT_PROJECT": snapshot_root,
        "CARINA_IOS_REVISION": revision,
        "CARINA_DEVICE_NAME": "17promax",
        "DEVELOPER_DIR": str(Path.home() / "Downloads/Xcode-beta.app/Contents/Developer"),
    },
    "RunAtLoad": True,
    "StartInterval": 21600,
    "ProcessType": "Background",
    "LowPriorityIO": True,
    "StandardOutPath": f"{log_root}/deployment-guardian.out.log",
    "StandardErrorPath": f"{log_root}/deployment-guardian.err.log",
}
with plist_path.open("wb") as handle:
    plistlib.dump(payload, handle, sort_keys=True)
plist_path.chmod(0o600)
PY

/bin/launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
/bin/launchctl bootstrap "$DOMAIN" "$PLIST"
/bin/launchctl kickstart -k "$DOMAIN/$LABEL"
/bin/sleep 2
/bin/launchctl print "$DOMAIN/$LABEL" | /usr/bin/head -n 38
