#!/bin/zsh
set -u

INSTALLER="/Users/rayc/Desktop/ciciswift/Scripts/sign-install-unsigned-ipa.sh"
CONFIG_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/cilicili/sign-install-ipa.conf"
DEFAULT_IPA_DIR="/Users/rayc/Desktop/ciciswift/build/debug-unsigned-ipa"

pause() {
  echo
  read -r "reply?按回车关闭窗口..."
}

die() {
  echo "错误: $*" >&2
  pause
  exit 1
}

choose_ipa() {
  local default_dir="$DEFAULT_IPA_DIR"
  [[ -d "$default_dir" ]] || default_dir="$HOME/Desktop"

  osascript - "$default_dir" <<'APPLESCRIPT'
on run argv
  set defaultPath to item 1 of argv
  set defaultFolder to POSIX file defaultPath
  set chosenFile to choose file with prompt "选择未签名 IPA" default location defaultFolder
  return POSIX path of chosenFile
end run
APPLESCRIPT
}

echo "cilicili IPA 签名安装"
echo

[[ -x "$INSTALLER" ]] || die "找不到安装脚本: $INSTALLER"

if [[ $# -eq 0 ]]; then
  echo "回车: 选择 IPA 包并安装"
  echo "1: 重新配置证书、描述文件和密码"
  echo "q: 退出"
  echo
  read -r "action?请选择: "

  case "$action" in
    "")
      ;;
    1)
      "$INSTALLER" --configure || {
        exit_code=$?
        echo
        echo "配置失败，退出码: $exit_code"
        pause
        exit "$exit_code"
      }
      echo
      read -r "continue_reply?配置完成。按回车选择 IPA 包继续安装，输入 q 退出: "
      if [[ "$continue_reply" == [qQ] ]]; then
        pause
        exit 0
      fi
      ;;
    [qQ])
      exit 0
      ;;
    *)
      die "未知选项: $action"
      ;;
  esac
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "首次使用需要配置证书、描述文件和 iPhone。"
  echo "配置会保存到: $CONFIG_PATH"
  echo
  "$INSTALLER" --configure || {
    exit_code=$?
    echo
    echo "配置失败，退出码: $exit_code"
    pause
    exit "$exit_code"
  }
fi

if [[ $# -gt 0 ]]; then
  IPA_PATH="$1"
else
  IPA_PATH="$(choose_ipa)" || {
    echo "已取消。"
    pause
    exit 0
  }
fi

[[ "$IPA_PATH" == *.ipa ]] || die "请选择 .ipa 文件: $IPA_PATH"
[[ -f "$IPA_PATH" ]] || die "文件不存在: $IPA_PATH"

"$INSTALLER" "$IPA_PATH"
exit_code=$?

echo
if (( exit_code == 0 )); then
  echo "安装完成。"
else
  echo "安装失败，退出码: $exit_code"
fi

pause
exit "$exit_code"
