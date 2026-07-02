#!/bin/zsh
set -euo pipefail

# 输出未签名的 Debug ipa，用于真机侧载测试（含 #if DEBUG 入口，如 UIKit 播放页原型）。
# 未签名 ipa 不能直接通过 Xcode/devicectl 安装，需用 AltStore / Sideloadly / TrollStore
# 等侧载工具自行签名安装。

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/build/DebugUnsignedDerivedData"
EXPORT_DIR="$ROOT_DIR/build/debug-unsigned-ipa"
LOG_DIR="$ROOT_DIR/build/logs"
LOG_PATH="$LOG_DIR/debug-unsigned-ipa.log"
IPA_PATH="$EXPORT_DIR/bili-debug-unsigned.ipa"

mkdir -p "$EXPORT_DIR" "$LOG_DIR"

echo "Building Debug (unsigned, device) ..."
if ! xcodebuild build \
    -project "$ROOT_DIR/bili.xcodeproj" \
    -scheme bili \
    -configuration Debug \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    AD_HOC_CODE_SIGNING_ALLOWED=YES \
    ENABLE_DEBUG_DYLIB=NO > "$LOG_PATH" 2>&1; then
  echo "Build failed. Log: $LOG_PATH" >&2
  tail -120 "$LOG_PATH" >&2
  exit 1
fi

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphoneos/bili.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded but app bundle not found: $APP_PATH" >&2
  exit 1
fi

echo "Packaging IPA ..."
PAYLOAD_DIR="$EXPORT_DIR/Payload"
rm -rf "$PAYLOAD_DIR" "$IPA_PATH"
mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/"

(cd "$EXPORT_DIR" && zip -qry "$IPA_PATH" Payload)
rm -rf "$PAYLOAD_DIR"

echo "Unsigned Debug IPA: $IPA_PATH"
echo "Build log: $LOG_PATH"
