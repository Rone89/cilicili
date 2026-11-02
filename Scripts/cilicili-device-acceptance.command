#!/bin/zsh
set -u
SCRIPT_DIR="${0:A:h}"
python3 "$SCRIPT_DIR/device-acceptance.py" "$@"
result=$?
if [[ -t 0 ]]; then
  read -r 'reply?按回车关闭窗口...'
fi
exit "$result"
