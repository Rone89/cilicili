#!/bin/zsh
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  fetch-ffmpeg-av1-vt.sh [options]

Options:
  --dest <path>      Clone/update target directory.
                     Default: $HOME/Desktop/FFmpeg-av1-vt
  --remote <url>     Git remote URL.
                     Default: https://github.com/FFmpeg/FFmpeg.git
  --ref <name>       Branch, tag, or commit to checkout.
                     Default: master
  --force            Remove existing target directory before cloning.
  --no-verify        Skip AV1 VideoToolbox source verification.
  -h, --help         Show help.

Environment overrides:
  DEST_DIR
  FFMPEG_REMOTE
  FFMPEG_REF

Examples:
  ./Scripts/fetch-ffmpeg-av1-vt.sh
  ./Scripts/fetch-ffmpeg-av1-vt.sh --dest "$HOME/Desktop/ffmpeg-master-av1vt"
  ./Scripts/fetch-ffmpeg-av1-vt.sh --remote https://github.com/yourname/FFmpeg.git --ref av1-videotoolbox
EOF
}

DEST_DIR="${DEST_DIR:-$HOME/Desktop/FFmpeg-av1-vt}"
FFMPEG_REMOTE="${FFMPEG_REMOTE:-https://github.com/FFmpeg/FFmpeg.git}"
FFMPEG_REF="${FFMPEG_REF:-master}"
FORCE_CLONE=0
VERIFY_SOURCE=1
SEARCH_TOOL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      DEST_DIR="$2"
      shift 2
      ;;
    --remote)
      FFMPEG_REMOTE="$2"
      shift 2
      ;;
    --ref)
      FFMPEG_REF="$2"
      shift 2
      ;;
    --force)
      FORCE_CLONE=1
      shift
      ;;
    --no-verify)
      VERIFY_SOURCE=0
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

if command -v rg >/dev/null 2>&1; then
  SEARCH_TOOL="rg"
elif command -v grep >/dev/null 2>&1; then
  SEARCH_TOOL="grep"
else
  echo "Missing required command: rg or grep" >&2
  exit 1
fi

checkout_ref() {
  local repo_dir="$1"
  local ref="$2"

  if git -C "$repo_dir" show-ref --verify --quiet "refs/remotes/origin/$ref"; then
    git -C "$repo_dir" checkout -B "$ref" "origin/$ref"
  else
    git -C "$repo_dir" checkout "$ref"
  fi
}

clone_or_update_repo() {
  local repo_dir="$1"
  local remote_url="$2"
  local ref="$3"

  if [[ -d "$repo_dir/.git" ]]; then
    echo "Updating existing repo: $repo_dir"
    git -C "$repo_dir" remote set-url origin "$remote_url"
    git -C "$repo_dir" fetch --all --tags --prune
    checkout_ref "$repo_dir" "$ref"
    return
  fi

  if [[ -e "$repo_dir" ]]; then
    if [[ "$FORCE_CLONE" -eq 1 ]]; then
      echo "Removing existing path: $repo_dir"
      rm -rf "$repo_dir"
    else
      echo "Target path already exists and is not a git repo: $repo_dir" >&2
      echo "Re-run with --force to replace it." >&2
      exit 1
    fi
  fi

  echo "Cloning $remote_url -> $repo_dir"
  if git clone --filter=blob:none --single-branch --branch "$ref" "$remote_url" "$repo_dir"; then
    return
  fi

  echo "Branch/tag '$ref' was not available during clone. Falling back to full clone." >&2
  git clone --filter=blob:none "$remote_url" "$repo_dir"
  git -C "$repo_dir" fetch --all --tags --prune
  checkout_ref "$repo_dir" "$ref"
}

verify_av1_videotoolbox_support() {
  local repo_dir="$1"
  local matches=()
  local -a search_paths

  search_paths=(
    "$repo_dir/libavcodec"
    "$repo_dir/configure"
  )

  while IFS= read -r line; do
    matches+=("$line")
  done < <(
    if [[ "$SEARCH_TOOL" == "rg" ]]; then
      rg -n --no-heading \
        -e 'av1_videotoolbox' \
        -e 'kCMVideoCodecType_AV1' \
        -e 'ff_videotoolbox_av1c_extradata_create' \
        -e 'hardware accelerated AV1 decoding' \
        "${search_paths[@]}" 2>/dev/null || true
    else
      grep -RInE \
        'av1_videotoolbox|kCMVideoCodecType_AV1|ff_videotoolbox_av1c_extradata_create|hardware accelerated AV1 decoding' \
        "${search_paths[@]}" 2>/dev/null || true
    fi
  )

  echo
  echo "Verification:"
  if [[ "${#matches[@]}" -gt 0 ]]; then
    echo "  Found AV1 VideoToolbox-related markers:"
    printf '    %s\n' "${matches[@]}"
    return 0
  fi

  echo "  No AV1 VideoToolbox-specific markers were found."
  echo "  This usually means one of these:"
  echo "    1. You are still on a branch without AV1 VT support."
  echo "    2. The implementation lives in a fork/feature branch, not upstream ref '$FFMPEG_REF'."
  echo "    3. You need to switch to a patch branch and re-run this script."
  return 1
}

clone_or_update_repo "$DEST_DIR" "$FFMPEG_REMOTE" "$FFMPEG_REF"

echo
echo "Checked out:"
echo "  Repo   : $FFMPEG_REMOTE"
echo "  Ref    : $(git -C "$DEST_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)"
echo "  Commit : $(git -C "$DEST_DIR" rev-parse HEAD)"
echo "  Path   : $DEST_DIR"

if [[ "$VERIFY_SOURCE" -eq 1 ]]; then
  verify_av1_videotoolbox_support "$DEST_DIR" || exit 2
fi

echo
echo "Done."
