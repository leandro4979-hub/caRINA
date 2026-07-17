#!/bin/zsh
set -euo pipefail

BRIDGE_LABEL="com.leandrofajardo.carina.bridge"
BRIDGE_SERVICE="gui/$UID/$BRIDGE_LABEL"

if launchctl print "$BRIDGE_SERVICE" >/dev/null 2>&1; then
  launchctl kickstart "$BRIDGE_SERVICE" >/dev/null 2>&1 || true
else
  print -u2 "CARINA bridge is not installed. Run ./scripts/install_carina_bridge_launch_agent.sh first."
fi

/usr/bin/osascript <<'APPLESCRIPT'
tell application "QuickTime Player"
    activate
    set liveViews to every document whose name contains "Movie Recording"
    if (count of liveViews) is 0 then
        new movie recording
    end if
end tell
APPLESCRIPT

print "Hands-On Live View is open. Select the iPhone from QuickTime's capture-device menu if it is not already selected."
print "Operate the iPhone physically; CARINA's bridge remains active in the background."
