#!/bin/zsh
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  pin-ffmpegkit-to-local-av1-vt.sh [options]

Options:
  --ffmpeg-src <path>      Local FFmpeg repo with AV1 VideoToolbox support.
                           Default: $HOME/Desktop/FFmpeg-av1-vt
  --ffmpegkit-root <path>  Local FFmpegKit package root.
                           Default: /Users/rayc/Desktop/ciciswift_副本/Packages/FFmpegKit
  --commit <sha>           Pin to a specific commit. Default: HEAD of --ffmpeg-src
  --force                  Replace existing .Script/FFmpeg-<commit> directory.
  -h, --help               Show help.

What this script does:
  1. Reads the exact FFmpeg commit from your local checkout
  2. Clones that checkout into FFmpegKit/.Script/FFmpeg-<commit>
  3. Rewrites BuildFFmpeg plugin version pin from n6.1 to that commit
  4. Creates a timestamped backup of the old plugin file before patching

After it finishes, rebuild with:
  cd /Users/rayc/Desktop/ciciswift_副本/Packages/FFmpegKit
  swift package --disable-sandbox BuildFFmpeg notRecompile enable-FFmpeg
EOF
}

FFMPEG_SRC="${FFMPEG_SRC:-$HOME/Desktop/FFmpeg-av1-vt}"
FFMPEGKIT_ROOT="${FFMPEGKIT_ROOT:-/Users/rayc/Desktop/ciciswift_副本/Packages/FFmpegKit}"
PIN_COMMIT="${PIN_COMMIT:-}"
FORCE_REPLACE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ffmpeg-src)
      FFMPEG_SRC="$2"
      shift 2
      ;;
    --ffmpegkit-root)
      FFMPEGKIT_ROOT="$2"
      shift 2
      ;;
    --commit)
      PIN_COMMIT="$2"
      shift 2
      ;;
    --force)
      FORCE_REPLACE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

require_command git
require_command perl
require_command cp
require_command mkdir
require_command rm

if [[ ! -d "$FFMPEG_SRC/.git" ]]; then
  echo "FFmpeg source repo not found: $FFMPEG_SRC" >&2
  exit 1
fi

if [[ ! -d "$FFMPEGKIT_ROOT" ]]; then
  echo "FFmpegKit root not found: $FFMPEGKIT_ROOT" >&2
  exit 1
fi

PLUGIN_MAIN="$FFMPEGKIT_ROOT/Plugins/BuildFFmpeg/main.swift"
if [[ ! -f "$PLUGIN_MAIN" ]]; then
  echo "BuildFFmpeg plugin file not found: $PLUGIN_MAIN" >&2
  exit 1
fi

if [[ -z "$PIN_COMMIT" ]]; then
  PIN_COMMIT="$(git -C "$FFMPEG_SRC" rev-parse HEAD)"
fi

PIN_BRANCH="$(git -C "$FFMPEG_SRC" rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)"
SCRIPT_ROOT="$FFMPEGKIT_ROOT/.Script"
TARGET_DIR="$SCRIPT_ROOT/FFmpeg-$PIN_COMMIT"
BACKUP_ROOT="$SCRIPT_ROOT/backups"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"
METADATA_FILE="$TARGET_DIR/.codex-source-pin.txt"

mkdir -p "$SCRIPT_ROOT"
mkdir -p "$BACKUP_DIR"

if [[ -e "$TARGET_DIR" ]]; then
  if [[ "$FORCE_REPLACE" -eq 1 ]]; then
    echo "Removing existing pinned source: $TARGET_DIR"
    rm -rf "$TARGET_DIR"
  else
    echo "Pinned source already exists: $TARGET_DIR" >&2
    echo "Re-run with --force to replace it." >&2
    exit 1
  fi
fi

echo "Cloning local FFmpeg source into FFmpegKit working directory..."
git clone "$FFMPEG_SRC" "$TARGET_DIR" >/dev/null
git -C "$TARGET_DIR" checkout "$PIN_COMMIT" >/dev/null

cat > "$METADATA_FILE" <<EOF
source_repo=$FFMPEG_SRC
source_branch=$PIN_BRANCH
source_commit=$PIN_COMMIT
pinned_at=$TIMESTAMP
EOF

cp "$PLUGIN_MAIN" "$BACKUP_DIR/main.swift.before-pin"

CURRENT_PLUGIN_VERSION="$(perl -0ne 'if (/case \.FFmpeg:\s*return "([^"]+)"/s) { print $1 }' "$PLUGIN_MAIN")"
if [[ -z "$CURRENT_PLUGIN_VERSION" ]]; then
  echo "Failed to locate current FFmpeg version pin in $PLUGIN_MAIN" >&2
  exit 1
fi

export PIN_COMMIT
perl -0pi -e 's/(case \.FFmpeg:\s*return ")([^"]+)(")/$1.$ENV{PIN_COMMIT}.$3/se' "$PLUGIN_MAIN"

UPDATED_PLUGIN_VERSION="$(perl -0ne 'if (/case \.FFmpeg:\s*return "([^"]+)"/s) { print $1 }' "$PLUGIN_MAIN")"
if [[ "$UPDATED_PLUGIN_VERSION" != "$PIN_COMMIT" ]]; then
  echo "Failed to update plugin FFmpeg pin. Expected $PIN_COMMIT, got $UPDATED_PLUGIN_VERSION" >&2
  exit 1
fi

echo
echo "Pinned FFmpegKit to local AV1 VT source:"
echo "  FFmpeg src        : $FFMPEG_SRC"
echo "  Branch            : $PIN_BRANCH"
echo "  Commit            : $PIN_COMMIT"
echo "  Pinned source dir : $TARGET_DIR"
echo "  Old plugin pin    : $CURRENT_PLUGIN_VERSION"
echo "  New plugin pin    : $UPDATED_PLUGIN_VERSION"
echo "  Backup            : $BACKUP_DIR/main.swift.before-pin"

echo
echo "Next step:"
echo "  cd $FFMPEGKIT_ROOT"
echo "  swift package --disable-sandbox BuildFFmpeg notRecompile enable-FFmpeg"
