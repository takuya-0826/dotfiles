#!/usr/bin/env bash
# そのディレクトリの直近セッションを session-id 明示で resume する。
#
# 使い方: claude-resume-latest [dir] [-- <claude への追加引数>]
#   dir を省略すると $PWD。zellij レイアウトの command として使う想定。
#
# なぜ `claude --continue` を使わないか (2026-08-03):
#   --continue は "current directory の最新会話" を継続するが、11MB / 5067 行の
#   セッションで "No conversation found to continue" になり復元できなかった
#   (3.1MB のセッションは成功。cwd の記録・ディレクトリ名・プロセスのロックは
#   いずれも正常だったので、サイズが疑わしいが原因は未確定)。
#   --resume は ID 直指定なので探索ロジックを迂回できる。ID をレイアウトに
#   焼き込むと使い回せないため、jsonl から最新の session-id を毎回引く。
#
# セッションが 1 つも無ければ通常起動にフォールバックする (初回はこれになる)。
set -uo pipefail

dir="${1:-$PWD}"
[ $# -gt 0 ] && shift

# 必ず cd する。--resume / --continue はどちらも「現在の cwd に紐づくセッション」
# しか見ないため、cwd がずれていると ID を正しく渡しても
# "No conversation found with session ID" になる (2026-08-03 に実測)。
# zellij レイアウト側の cwd 指定に依存せず、ここで確定させる。
cd "$dir" || {
  echo "[claude-resume-latest] cannot cd to $dir" >&2
  exit 1
}

# ~/.claude/projects/ 配下のディレクトリ名は、cwd の "/" "." "_" をすべて "-" に
# 置換したもの (実データ 4 パターンで一致を確認済み)。
esc="$(printf '%s' "$dir" | tr '/._' '---')"
proj="$HOME/.claude/projects/$esc"

latest=""
if [ -d "$proj" ]; then
  latest="$(ls -t "$proj"/*.jsonl 2>/dev/null | head -1)"
fi

if [ -n "$latest" ]; then
  sid="$(basename "$latest" .jsonl)"
  echo "[claude-resume-latest] resuming $sid  ($(du -h "$latest" | cut -f1))" >&2
  exec claude --dangerously-skip-permissions --resume "$sid" "$@"
fi

echo "[claude-resume-latest] no previous session under $dir - starting fresh" >&2
exec claude --dangerously-skip-permissions "$@"
