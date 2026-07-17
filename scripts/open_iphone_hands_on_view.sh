#!/bin/zsh
set -euo pipefail

BRIDGE_LABEL="com.leandrofajardo.carina.bridge"
BRIDGE_SERVICE="gui/$UID/$BRIDGE_LABEL"

if launchctl print "$BRIDGE_SERVICE" >/dev/null 2>&1; then
  launchctl kickstart "$BRIDGE_SERVICE" >/dev/null 2>&1 || true
else
  print -u2 "CARINA bridge is not installed. Run ./scripts/install_carina_bridge_launch_agent.sh first."
fi

/usr/bin/open "x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension"

print "Hands-On Live View is ready. Confirm AirPlay Receiver is enabled on the Mac."
print "On the iPhone, open Control Center, tap Screen Mirroring, and select this Mac."
print "CARINA's bridge remains active while the physical iPhone stays interactive."
