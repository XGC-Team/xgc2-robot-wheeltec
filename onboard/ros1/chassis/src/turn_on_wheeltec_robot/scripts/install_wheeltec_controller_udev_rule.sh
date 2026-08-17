#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RULE_DIR="$SCRIPT_DIR/../udev"

if [[ $EUID -ne 0 ]]; then
  echo "This script installs udev rules and must run as root." >&2
  echo "Inspect the controller USB attributes first, then run: sudo $0" >&2
  exit 1
fi

shopt -s nullglob
rules=("$RULE_DIR"/99-xgc2-wheeltec-controller*.rules)
if [[ ${#rules[@]} -eq 0 ]]; then
  echo "Packaged controller udev rules missing in $RULE_DIR" >&2
  exit 1
fi

for src in "${rules[@]}"; do
  dest="/etc/udev/rules.d/$(basename "$src")"
  install -m 0644 "$src" "$dest"
  echo "Installed $dest"
done

udevadm control --reload-rules
udevadm trigger --subsystem-match=tty || true
echo "Reconnect the controller USB UART if /dev/wheeltec_controller does not appear."
