#!/usr/bin/env bash
set -euo pipefail

# pr-conflict-check が開いた "Conflict: <repo>#<num>" タブを閉じる。
# usage: close-conflict-tab <repo> <num>
# 例: close-conflict-tab Atrae/wevox-mono-web 9664
#
# herdr の `tab close` は tab_id 必須なので、 旧 zellij の「裸の close-tab が
# フォーカス中のタブを巻き込む」事故は構造的に起きない。 label から id を引いて
# 閉じるだけ。 該当タブが無ければ何もせず exit 0。

REPO="${1:-}"
NUM="${2:-}"

if [ -z "$REPO" ] || [ -z "$NUM" ]; then
  echo "usage: $(basename "$0") <repo> <num>" >&2
  exit 2
fi

TAB_NAME="Conflict: ${REPO}#${NUM}"

TAB_ID=$(herdr-tab-id "$TAB_NAME" || true)

if [ -z "$TAB_ID" ]; then
  echo "tab not found: $TAB_NAME"
  exit 0
fi

herdr tab close "$TAB_ID"
echo "closed: $TAB_NAME (id=$TAB_ID)"
