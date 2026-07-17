#!/bin/zsh
set -euo pipefail

export PATH="$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer"

[[ -x "$HOME/.local/bin/appium" ]] || { print -u2 "Appium is not installed."; exit 1; }

if (( EUID != 0 )); then
  exec sudo --preserve-env=HOME,PATH,DEVELOPER_DIR "$0"
fi

exec "$HOME/.local/bin/appium" driver run xcuitest tunnel-creation
