#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  WDA_TEAM_ID=YOUR_TEAM_ID ./install_wda_once.sh DEVICE_UDID

Example:
  WDA_TEAM_ID=AB12CDE345 ./install_wda_once.sh 00008140-0012345678901234

Optional environment variables:
  WDA_BUNDLE_ID       Custom WDA bundle id.
                      Default: com.dinosaur.carina.WebDriverAgentRunner

  WDA_DIR             Checkout/build directory.
                      Default: $HOME/Developer/WebDriverAgent-Carina

  DERIVED_DATA        Xcode DerivedData location.
                      Default: $WDA_DIR/DerivedData

  CODE_SIGN_IDENTITY  Signing identity.
                      Default: Apple Development
EOF
}

if [[ $# -ne 1 ]]; then
  usage
  exit 64
fi

DEVICE_UDID="$1"

: "${WDA_TEAM_ID:?Set WDA_TEAM_ID to your Apple Developer Team ID before running this script.}"

WDA_BUNDLE_ID="${WDA_BUNDLE_ID:-com.dinosaur.carina.WebDriverAgentRunner}"
WDA_DIR="${WDA_DIR:-$HOME/Developer/WebDriverAgent-Carina}"
DERIVED_DATA="${DERIVED_DATA:-$WDA_DIR/DerivedData}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Apple Development}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 69
  fi
}

require_command git
require_command xcodebuild
require_command xcrun
require_command plutil

echo "==> Verifying active Xcode"
xcode-select -p
xcodebuild -version

echo
echo "==> Checking that the device is visible"
if ! xcrun devicectl list devices 2>/dev/null | grep -Fq "$DEVICE_UDID"; then
  echo "ERROR: device $DEVICE_UDID is not visible to devicectl." >&2
  echo "Connect/unlock/trust the iPhone and verify Developer Mode is enabled." >&2
  exit 70
fi

echo
echo "==> Preparing WebDriverAgent"
if [[ -d "$WDA_DIR/.git" ]]; then
  git -C "$WDA_DIR" fetch --tags --prune
  git -C "$WDA_DIR" pull --ff-only
else
  mkdir -p "$(dirname "$WDA_DIR")"
  git clone --depth 1 https://github.com/appium/WebDriverAgent.git "$WDA_DIR"
fi

cd "$WDA_DIR"

echo
echo "==> Removing previous DerivedData"
rm -rf "$DERIVED_DATA"
mkdir -p "$DERIVED_DATA"

echo
echo "==> Building signed WebDriverAgentRunner"
xcodebuild \
  -project WebDriverAgent.xcodeproj \
  -scheme WebDriverAgentRunner \
  -configuration Debug \
  -destination "id=$DEVICE_UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$WDA_TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  PRODUCT_BUNDLE_IDENTIFIER="$WDA_BUNDLE_ID" \
  GCC_TREAT_WARNINGS_AS_ERRORS=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build-for-testing

WDA_APP="$DERIVED_DATA/Build/Products/Debug-iphoneos/WebDriverAgentRunner-Runner.app"

if [[ ! -d "$WDA_APP" ]]; then
  echo "ERROR: WDA build completed but runner was not found at:" >&2
  echo "  $WDA_APP" >&2
  exit 71
fi

echo
echo "==> Removing embedded XCTest frameworks for preinstalled-WDA launch"

FRAMEWORK_DIR="$WDA_APP/Frameworks"

if [[ -d "$FRAMEWORK_DIR" ]]; then
  find "$FRAMEWORK_DIR" \
    -maxdepth 1 \
    -type d \
    -name 'XC*.framework' \
    -print \
    -exec rm -rf {} +
fi

INFO_PLIST="$WDA_APP/Info.plist"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "ERROR: missing WDA Info.plist" >&2
  exit 72
fi

ACTUAL_BUNDLE_ID="$(
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleIdentifier' \
    "$INFO_PLIST"
)"

echo
echo "==> Build complete"
echo "Runner:"
echo "  $WDA_APP"
echo
echo "Bundle identifier:"
echo "  $ACTUAL_BUNDLE_ID"
echo
echo "Team:"
echo "  $WDA_TEAM_ID"
echo
echo "Device:"
echo "  $DEVICE_UDID"

echo
echo "==> Installing WDA runner on the physical iPhone"

xcrun devicectl device install app \
  --device "$DEVICE_UDID" \
  "$WDA_APP"

echo
echo "============================================================"
echo "WDA BUILD + INSTALL COMPLETE"
echo "============================================================"
echo
echo "Export these values before starting the Appium smoke test:"
printf 'export CARINA_IOS_UDID=%q\n' "$DEVICE_UDID"
printf 'export CARINA_WDA_APP=%q\n' "$WDA_APP"
printf 'export CARINA_WDA_BUNDLE_ID=%q\n' "$ACTUAL_BUNDLE_ID"
