#!/usr/bin/env bash
set -euo pipefail

# gh-review-watcher から呼ばれる: "Review: <repo>#<num>" タブを開いて review-pr を走らせる。
# usage: open-review-tab <url> <number> <repo>
#
# herdr には zellij の `new-tab --close-on-exit -- cmd` が無い（コマンド直生やし不可・
# 終了で自動で閉じない）ため:
#   - タブは `tab create` → `pane run` で作り、
#   - review-pr の終了時に「自分のタブを id 指定で閉じる」ことで --close-on-exit を再現する
#     （on_remove の close-merged-review-tab は PR がリストから消えた時のバックアップ）。
#   - review タブは専用 workspace "reviews"（無ければ作成）にまとめ、作業スペースを汚さない。
#     ラベルは $REVIEW_WORKSPACE で変更可。

URL="${1:-}"
NUMBER="${2:-}"
REPO="${3:-}"

if [ -z "$URL" ] || [ -z "$NUMBER" ] || [ -z "$REPO" ]; then
  echo "usage: $(basename "$0") <url> <number> <repo>" >&2
  exit 2
fi

TAB_NAME="Review: ${REPO}#${NUMBER}"

# 同名タブが既にあれば focus するだけ（herdr-tab-id は全 workspace を横断して探す）。
EXISTING=$(herdr-tab-id "$TAB_NAME" || true)
if [ -n "$EXISTING" ]; then
  herdr tab focus "$EXISTING" >/dev/null
  echo "focused existing tab: $TAB_NAME"
  exit 0
fi

# 専用 workspace "reviews" を解決（無ければ作成 → 作成後に list で id を引き直す堅牢方式）。
WS_LABEL="${REVIEW_WORKSPACE:-reviews}"
ws_id() {
  herdr workspace list 2>/dev/null \
    | jq -r --arg l "$WS_LABEL" 'first(.result.workspaces[]? | select(.label == $l) | .workspace_id) // empty' 2>/dev/null
}
WSID=$(ws_id)
if [ -z "$WSID" ]; then
  herdr workspace create --label "$WS_LABEL" --no-focus >/dev/null 2>&1 || true
  WSID=$(ws_id)
fi
WSOPT=()
[ -n "$WSID" ] && WSOPT=(--workspace "$WSID")

# --no-focus: レビュー依頼が飛んできても作業中のタブを奪わない。
CREATED=$(herdr tab create "${WSOPT[@]}" --label "$TAB_NAME" --no-focus)
TAB_ID=$(printf '%s' "$CREATED" | jq -r '.result.tab.tab_id // empty')
PANE_ID=$(printf '%s' "$CREATED" | jq -r '.result.root_pane.pane_id // empty')

if [ -z "$PANE_ID" ]; then
  echo "open-review-tab: no pane id in herdr response: $CREATED" >&2
  exit 70
fi

# review-pr を走らせ、**成功した(exit 0)ときだけ**このタブを閉じる（= --close-on-exit 相当）。
# `;` ではなく `&&` なのが肝: review-pr は `set -euo pipefail` なので [c] の途中
# (claude 抽出 / gh api POST 等) で失敗すると即 exit する。`;` だと失敗しても無条件で
# タブを閉じ、コメント挿入前に落ちてエラーも見えなくなる。`&&` なら失敗時はタブが残り、
# エラーをその場で確認できる（閉じている=成功、開いたまま=要確認、と読める）。
RUNCMD="$(printf '%q ' review-pr "$URL" "$NUMBER" "$REPO")"
[ -n "$TAB_ID" ] && RUNCMD="${RUNCMD}&& herdr tab close $(printf '%q' "$TAB_ID")"
herdr pane run "$PANE_ID" "$RUNCMD" >/dev/null
echo "opened: $TAB_NAME (pane=$PANE_ID, ws=${WSID:-current})"
