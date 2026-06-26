#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CERT_DIR="${CERT_DIR:-/Users/rayc/Desktop/Apple Distribution Eric Kirsche KQ737H7L22_certificate}"
PROFILE_PATH="$CERT_DIR/cert.mobileprovision"
PROFILE_PLIST="${TMPDIR:-/tmp}/cilicili_distribution_profile.plist"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
DERIVED_DATA_PATH="$ROOT_DIR/build/DistributionSignedDerivedData"
ARCHIVE_PATH="$ROOT_DIR/build/archives/cilicili-distribution-$TIMESTAMP.xcarchive"
EXPORT_PATH="$ROOT_DIR/build/distribution-ipa/$TIMESTAMP"
EXPORT_OPTIONS_PLIST="${TMPDIR:-/tmp}/cilicili_distribution_export_options_$TIMESTAMP.plist"
LOG_DIR="$ROOT_DIR/build/logs"
LOG_PATH="$LOG_DIR/distribution-ipa-$TIMESTAMP.log"

"$ROOT_DIR/Scripts/configure-distribution-signing.sh"

security cms -D -i "$PROFILE_PATH" > "$PROFILE_PLIST"
PROFILE_NAME="$(plutil -extract Name raw -o - "$PROFILE_PLIST")"
TEAM_ID="$(plutil -extract TeamIdentifier.0 raw -o - "$PROFILE_PLIST")"
APP_IDENTIFIER="$(plutil -extract Entitlements.application-identifier raw -o - "$PROFILE_PLIST")"
BUNDLE_ID="${APP_IDENTIFIER#*.}"
IDENTITY_NAME="Apple Distribution: Eric Kirsche ($TEAM_ID)"

mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_PATH" "$LOG_DIR"

cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>ad-hoc</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>compileBitcode</key>
  <false/>
  <key>provisioningProfiles</key>
  <dict>
    <key>$BUNDLE_ID</key>
    <string>$PROFILE_NAME</string>
  </dict>
</dict>
</plist>
EOF

echo "Archiving Release build..."
if ! xcodebuild archive \
    -project "$ROOT_DIR/bili.xcodeproj" \
    -scheme bili \
    -configuration Release \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -archivePath "$ARCHIVE_PATH" > "$LOG_PATH" 2>&1; then
  echo "Archive failed. Log: $LOG_PATH" >&2
  tail -120 "$LOG_PATH" >&2
  exit 1
fi

echo "Exporting signed IPA..."
if ! xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" >> "$LOG_PATH" 2>&1; then
  echo "Export failed. Log: $LOG_PATH" >&2
  tail -120 "$LOG_PATH" >&2
  exit 1
fi

IPA_PATH="$(find "$EXPORT_PATH" -maxdepth 1 -name '*.ipa' -print -quit)"
if [[ -z "$IPA_PATH" ]]; then
  echo "Export finished but no IPA was found in $EXPORT_PATH" >&2
  exit 1
fi

echo "Signed IPA: $IPA_PATH"
echo "Build log: $LOG_PATH"
