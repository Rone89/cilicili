#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CERT_DIR="${CERT_DIR:-/Users/rayc/Desktop/Apple Distribution Eric Kirsche KQ737H7L22_certificate}"
PROFILE_PATH="$CERT_DIR/cert.mobileprovision"
PROFILE_PLIST="${TMPDIR:-/tmp}/cilicili_distribution_profile.plist"

security cms -D -i "$PROFILE_PATH" > "$PROFILE_PLIST"
DEFAULT_DEVICE="$(plutil -extract ProvisionedDevices.0 raw -o - "$PROFILE_PLIST")"
DEVICE="${1:-$DEFAULT_DEVICE}"

"$ROOT_DIR/Scripts/build-distribution-ipa.sh"

ARCHIVE_PATH="$(find "$ROOT_DIR/build/archives" -maxdepth 1 -name 'cilicili-distribution-*.xcarchive' -print | sort | tail -1)"
APP_PATH="$ARCHIVE_PATH/Products/Applications/bili.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built archive does not contain the app bundle: $APP_PATH" >&2
  exit 1
fi

echo "Installing to device: $DEVICE"
xcrun devicectl device install app --device "$DEVICE" "$APP_PATH"
