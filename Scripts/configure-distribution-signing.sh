#!/bin/zsh
set -euo pipefail

CERT_DIR="${CERT_DIR:-/Users/rayc/Desktop/Apple Distribution Eric Kirsche KQ737H7L22_certificate}"
P12_PATH="$CERT_DIR/cert.p12"
PROFILE_PATH="$CERT_DIR/cert.mobileprovision"
PASSWORD_PATH="$CERT_DIR/password.txt"
PROFILE_PLIST="${TMPDIR:-/tmp}/cilicili_distribution_profile.plist"
WWDR_G3_DER="${TMPDIR:-/tmp}/apple_wwdr_g3.der"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Missing required file: $path" >&2
    exit 1
  fi
}

extract_password() {
  local raw
  raw="$(tr -d '\r\n' < "$PASSWORD_PATH")"
  if [[ "$raw" == *": "* ]]; then
    print -r -- "${raw##*: }"
  elif [[ "$raw" == *":"* ]]; then
    print -r -- "${raw##*:}"
  else
    print -r -- "$raw"
  fi
}

ensure_wwdr_g3() {
  if security find-certificate -a -c "Apple Worldwide Developer Relations Certification Authority" "$KEYCHAIN" /Library/Keychains/System.keychain 2>/dev/null | grep -q "OU=G3"; then
    return
  fi

  echo "Installing Apple WWDR G3 intermediate certificate..."
  env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
    curl -fsSL "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer" -o "$WWDR_G3_DER"
  security add-certificates -k "$KEYCHAIN" "$WWDR_G3_DER" >/dev/null 2>&1 || true
}

require_file "$P12_PATH"
require_file "$PROFILE_PATH"
require_file "$PASSWORD_PATH"

security cms -D -i "$PROFILE_PATH" > "$PROFILE_PLIST"
PROFILE_UUID="$(plutil -extract UUID raw -o - "$PROFILE_PLIST")"
PROFILE_NAME="$(plutil -extract Name raw -o - "$PROFILE_PLIST")"
TEAM_ID="$(plutil -extract TeamIdentifier.0 raw -o - "$PROFILE_PLIST")"
APP_IDENTIFIER="$(plutil -extract Entitlements.application-identifier raw -o - "$PROFILE_PLIST")"
BUNDLE_ID="${APP_IDENTIFIER#*.}"
IDENTITY_NAME="Apple Distribution: Eric Kirsche ($TEAM_ID)"

mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$PROFILE_PATH" "$HOME/Library/MobileDevice/Provisioning Profiles/$PROFILE_UUID.mobileprovision"

if ! security find-identity -v -p codesigning "$KEYCHAIN" | grep -Fq "$IDENTITY_NAME"; then
  echo "Importing distribution certificate..."
  P12_PASSWORD="$(extract_password)"
  security import "$P12_PATH" \
    -k "$KEYCHAIN" \
    -P "$P12_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    -f pkcs12 >/dev/null
fi

if ! security find-identity -v -p codesigning "$KEYCHAIN" | grep -Fq "$IDENTITY_NAME"; then
  ensure_wwdr_g3
fi

if ! security find-identity -v -p codesigning "$KEYCHAIN" | grep -Fq "$IDENTITY_NAME"; then
  echo "Signing identity is still not valid: $IDENTITY_NAME" >&2
  echo "Open Keychain Access and confirm the private key is present under the certificate." >&2
  exit 1
fi

cat <<EOF
Distribution signing is configured.
Identity: $IDENTITY_NAME
Team ID: $TEAM_ID
Bundle ID: $BUNDLE_ID
Profile: $PROFILE_NAME ($PROFILE_UUID)
Installed profile: $HOME/Library/MobileDevice/Provisioning Profiles/$PROFILE_UUID.mobileprovision
EOF
