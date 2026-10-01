#!/usr/bin/env bash
set -euo pipefail

# gh-review-watcher on_remove hook: リストから消えたPRのレビュータブを閉じる
# Arguments: {number} {repo}
#
# herdr のタブはコマンド終了で自動的には消えない (zellij の --close-on-exit 相当が
# 無い) ため、 このフックが review タブの唯一の後片付け経路になる。
NUMBER="$1"
REPO="$2"

TAB_NAME="Review: ${REPO}#${NUMBER}"

# レビュータブが存在しなければ何もしない
TAB_ID=$(herdr-tab-id "$TAB_NAME" || true)

if [[ -z "$TAB_ID" ]]; then
  exit 0
fi

herdr tab close "$TAB_ID"
echo "[CLOSED TAB] ${TAB_NAME}" >> /tmp/gh-review-watcher-hooks.log
