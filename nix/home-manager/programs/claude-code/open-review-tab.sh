#!/usr/bin/env bash
set -euo pipefail

# gh-review-watcher から呼ばれる: "Review: <repo>#<num>" タブを開いて review-pr を走らせる。
# usage: open-review-tab <url> <number> <repo>
#
# どこに開くか:
#   - zellij の中から呼ばれた (gh-review-watcher を zellij のタブで動かしている) なら、
#     そのセッションに新しいタブを作り、すぐ元のタブにフォーカスを戻す。
#   - zellij の外 (launchd 等) からなら、バックグラウンドセッション "reviews"
#     ($REVIEW_SESSION で変更可) に作る。見るときは `zellij attach reviews`。
#
# タブは review-pr が **成功 (exit 0) したときだけ** 閉じる。失敗したらシェルに落ちて
# タブが残り、エラーをその場で読める (閉じている = 成功、開いたまま = 要確認)。
# PR がリストから消えたときは on_remove の close-merged-review-tab が閉じる。

URL="${1:-}"
NUMBER="${2:-}"
REPO="${3:-}"

if [ -z "$URL" ] || [ -z "$NUMBER" ] || [ -z "$REPO" ]; then
  echo "usage: $(basename "$0") <url> <number> <repo>" >&2
  exit 2
fi

HOOK_LOG="${GH_REVIEW_WATCHER_LOG:-/tmp/gh-review-watcher-hooks.log}"
TAB_NAME="Review: ${REPO}#${NUMBER}"

if [ -n "${ZELLIJ_SESSION_NAME:-}" ]; then
  SESSION="$ZELLIJ_SESSION_NAME"
  INSIDE=1
else
  SESSION="${REVIEW_SESSION:-reviews}"
  INSIDE=0
  zj ensure "$SESSION" >/dev/null 2>&1 || true
fi

# zellij に届かないなら、理由ごと記録して止まる。launchd 経由で走るので stderr は
# 誰も見ない → hooks ログに残すのが唯一の手掛かり。素通りさせるとタブが黙って開かず、
# 理由が分からなくなる (herdr 時代、CLI だけ更新されて 3 日間気づかなかった)。
if ! PF_ERR=$(zj preflight open-review-tab 2>&1); then
  printf '%s\n' "$PF_ERR" | tee -a "$HOOK_LOG" >&2
  exit 69
fi

# 同名タブが既にあれば何もしない (全セッションを横断して探す)。
if EXISTING=$(zj find-tab "$TAB_NAME"); then
  echo "already open: $TAB_NAME (${EXISTING/$'\t'/ tab })"
  exit 0
fi

# --cwd を明示する。指定しないと、その時フォーカスしていたペインの cwd (別リポジトリの
# worktree 等) を継いでしまう。review-pr は PR を URL で受けて動くので cwd に依存しない。
#
# 成功時だけ閉じる仕組み: --close-on-exit を付けたうえで、review-pr が失敗したら
# 対話シェルに置き換える (exec "$SHELL")。成功なら zsh が終わってペインごとタブが閉じる。
# zsh -l なのは、home-manager の PATH (~/.local/bin の review-pr 等) が .zshenv で入るため。
RUN=$(printf '%q ' review-pr "$URL" "$NUMBER" "$REPO")
TAB_ID=$(zj -s "$SESSION" action new-tab --name "$TAB_NAME" --cwd "$HOME" --close-on-exit -- \
  zsh -lc "$RUN || { echo; echo '✗ review-pr failed — this tab stays open. Exit the shell to close it.'; exec \"\${SHELL:-bash}\" -l; }" |
  tr -dc '0-9')

# 中から開いたときは作業中のタブにフォーカスを戻す (レビュー依頼で作業を奪わない)。
[ "$INSIDE" = 1 ] && zj -s "$SESSION" action go-to-previous-tab >/dev/null 2>&1 || true

echo "opened: $TAB_NAME (session=$SESSION tab=${TAB_ID:-?})"
