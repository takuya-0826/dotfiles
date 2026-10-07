#!/usr/bin/env bash
# zj — どのシェルから呼んでも同じ zellij サーバーに届く形で zellij を呼ぶラッパー。
#
# usage:
#   zj [-s SESSION] action <...>   対象セッションに action を送る
#   zj [-s SESSION] tab-id <name>  名前が完全一致するタブの tab_id を出す (無ければ空 + exit 1)
#   zj find-tab <name>             全セッションから探して "<session>\t<tab_id>" を出す
#   zj ensure <SESSION>            SESSION が無ければバックグラウンドで作る (クライアントは開かない)
#   zj session                     対象セッション名を出す
#   zj preflight [caller]          zellij に届くか確かめ、届かなければ理由を出して exit 69
#   zj <その他>                    zellij にそのまま渡す (TMPDIR の正規化だけ行う)
#
# なぜ要るか:
#   1. zellij の socket は $TMPDIR 配下 (…/T/zellij-<uid>/) に置かれる。launchd や
#      Claude Code の Bash は $TMPDIR が違う (/tmp/claude-501 等) ので、素の `zellij` は
#      別の場所を探して "There is no active session!" で失敗する。ここで macOS の
#      ユーザー一時ディレクトリ (getconf DARWIN_USER_TEMP_DIR) に揃える。
#   2. zellij の外 (launchd / gh-review-watcher / Claude デスクトップ) から呼ぶときは
#      「どのセッションか」が決まらない。-s で明示するか、下の順で選ぶ:
#        $ZJ_SESSION > $ZELLIJ_SESSION_NAME (ペイン内) > list-sessions の (current) > 生きている最初のセッション
#
# 自動化 (dev-up / open-review-tab 等) は固定名のバックグラウンドセッション
# (dev-servers / reviews) を `zj ensure` で用意してそこにタブを作る。herdr の
# workspace の代わりで、作業中のタブのフォーカスを奪わない。
set -uo pipefail

if [ -z "${ZELLIJ_SOCKET_DIR:-}" ]; then
  _t="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null)"
  [ -n "$_t" ] && export TMPDIR="${_t%/}"
fi

live_sessions() {  # 生きているセッション名 (EXITED = 復元待ちの死んだセッションは除く)
  zellij list-sessions --no-formatting 2>/dev/null | grep -v 'EXITED' | awk 'NF{print $1}'
}

pick_session() {
  if [ -n "${ZJ_SESSION:-}" ]; then echo "$ZJ_SESSION"; return 0; fi
  if [ -n "${ZELLIJ_SESSION_NAME:-}" ]; then echo "$ZELLIJ_SESSION_NAME"; return 0; fi
  local cur
  cur=$(zellij list-sessions --no-formatting 2>/dev/null | grep -v EXITED | grep '(current)' | awk '{print $1; exit}')
  [ -n "$cur" ] && { echo "$cur"; return 0; }
  cur=$(live_sessions | head -1)
  [ -n "$cur" ] && { echo "$cur"; return 0; }
  return 1
}

session=""
if [ "${1:-}" = "-s" ]; then session="${2:?zj: -s needs a session name}"; shift 2; fi

case "${1:-}" in
  action)
    shift
    [ -n "$session" ] || session="$(pick_session)" || { echo "zj: no running zellij session" >&2; exit 69; }
    exec zellij --session "$session" action "$@"
    ;;

  tab-id)
    name="${2:?usage: zj [-s SESSION] tab-id <name>}"
    [ -n "$session" ] || session="$(pick_session)" || exit 1
    id=$(zellij --session "$session" action list-tabs --json 2>/dev/null |
      jq -r --arg n "$name" 'first(.[]? | select(.name == $n) | .tab_id) // empty' 2>/dev/null)
    [ -n "$id" ] || exit 1
    echo "$id"
    ;;

  find-tab)
    # 全セッションを横断して名前が完全一致するタブを探し、"<session>\t<tab_id>" を出す。
    # 自動化のタブは「今いるセッション」にも「reviews 等のバックグラウンド」にもありうる。
    name="${2:?usage: zj find-tab <name>}"
    for s in $(live_sessions); do
      id=$(zellij --session "$s" action list-tabs --json 2>/dev/null |
        jq -r --arg n "$name" 'first(.[]? | select(.name == $n) | .tab_id) // empty' 2>/dev/null)
      [ -n "$id" ] && { printf '%s\t%s\n' "$s" "$id"; exit 0; }
    done
    exit 1
    ;;

  ensure)
    s="${2:?usage: zj ensure <SESSION>}"
    if live_sessions | grep -Fxq "$s"; then exit 0; fi
    # 死んだ同名セッションが残っていると attach が「復元」になり、前回のコマンドが
    # 蘇る。自動化用のセッションは毎回まっさらでよいので消してから作る。
    zellij delete-session "$s" >/dev/null 2>&1 || true
    zellij attach --create-background "$s" >/dev/null 2>&1
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      live_sessions | grep -Fxq "$s" && exit 0
      sleep 0.2
    done
    echo "zj: could not create background session '$s'" >&2
    exit 69
    ;;

  session)
    [ -n "$session" ] && { echo "$session"; exit 0; }
    pick_session || { echo "zj: no running zellij session" >&2; exit 1; }
    ;;

  preflight)
    # zellij を叩けるかの事前チェック。herdr 時代に「サーバーはいるのに CLI の版が
    # 違って届かない」状態が 3 日間気づかれなかった (2026-09)。zellij も版ごとに
    # socket の置き場を分けるので、アップグレード後に古いサーバーが残ると同じことが
    # 起きうる。届かない理由を出し分ける。
    self="${2:-zj}"
    zellij list-sessions --no-formatting >/dev/null 2>&1 && exit 0
    base="$TMPDIR/zellij-$(id -u)"
    {
      echo "$self: can't reach zellij (client $(zellij --version 2>/dev/null | awk '{print $NF}'), socket dir $base)."
      if [ -d "$base" ] && find "$base" -type s 2>/dev/null | grep -q .; then
        echo "  Sockets exist but this client can't use them. Most likely a zellij server from"
        echo "  before an upgrade is still running. Restart it: quit zellij (or 'zellij kill-all-sessions'"
        echo "  from a pane of the old version) and start it again."
        find "$base" -type s 2>/dev/null | sed 's/^/    /' | head -5
      else
        echo "  No zellij server is running. Automation creates its own background sessions;"
        echo "  if even that failed, check that 'zellij' is on PATH (home-manager switch)."
      fi
    } >&2
    exit 69
    ;;

  ""|-h|--help)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 64
    ;;

  *)
    exec zellij "$@"
    ;;
esac
