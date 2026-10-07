#!/usr/bin/env bash
set -euo pipefail

# gh-review-watcher on_remove hook: リストから消えたPRのレビュータブを閉じる
# Arguments: {number} {repo}
#
# review-pr が失敗したタブはシェルに落ちて残るので、このフックが最後の後片付けになる。
# タブはセッションを横断して名前で探し、必ず tab_id 指定で閉じる (素の close-tab は
# フォーカス中のタブを閉じてしまう)。
NUMBER="$1"
REPO="$2"

HOOK_LOG="${GH_REVIEW_WATCHER_LOG:-/tmp/gh-review-watcher-hooks.log}"
TAB_NAME="Review: ${REPO}#${NUMBER}"

# zellij に届かないときに素通りさせない。find-tab は「届かない」と「そんなタブは無い」を
# どちらも exit 1 で返すので、preflight しないと exit 0 (= 片付け済み) を装ってしまう。
if ! PF_ERR=$(zj preflight close-merged-review-tab 2>&1); then
  printf '%s\n' "$PF_ERR" | tee -a "$HOOK_LOG" >&2
  exit 69
fi

FOUND=$(zj find-tab "$TAB_NAME" || true)
[ -z "$FOUND" ] && exit 0

SESSION="${FOUND%%$'\t'*}"
TAB_ID="${FOUND##*$'\t'}"
zj -s "$SESSION" action close-tab-by-id "$TAB_ID"
echo "[CLOSED TAB] ${TAB_NAME} (session=$SESSION)" >> "$HOOK_LOG"
