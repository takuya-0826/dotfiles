#!/usr/bin/env bash
set -euo pipefail

# pr-conflict-check が開いた "Conflict: <repo>#<num>" タブを閉じる。
# usage: close-conflict-tab <repo> <num>
# 例: close-conflict-tab Atrae/wevox-mono-web 9664
#
# zellij action close-tab はフォーカスのタブを閉じてしまうため、必ずセッションを横断して
# 名前でタブを探し、tab_id 指定で閉じる。該当タブが無ければ何もせず exit 0。

REPO="${1:-}"
NUM="${2:-}"

if [ -z "$REPO" ] || [ -z "$NUM" ]; then
  echo "usage: $(basename "$0") <repo> <num>" >&2
  exit 2
fi

TAB_NAME="Conflict: ${REPO}#${NUM}"

# find-tab は「届かない」も「無い」も exit 1 で返すので、preflight しないと
# zellij 断絶時に "tab not found" と言って exit 0 してしまう。
zj preflight close-conflict-tab || exit $?

FOUND=$(zj find-tab "$TAB_NAME" || true)
if [ -z "$FOUND" ]; then
  echo "tab not found: $TAB_NAME"
  exit 0
fi

SESSION="${FOUND%%$'\t'*}"
TAB_ID="${FOUND##*$'\t'}"
zj -s "$SESSION" action close-tab-by-id "$TAB_ID"
echo "closed: $TAB_NAME (session=$SESSION tab=$TAB_ID)"
