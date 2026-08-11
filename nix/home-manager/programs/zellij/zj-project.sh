#!/usr/bin/env bash
# zj-project — PJごとの zellij タブをオンデマンドで開く
#   使い方: zj-project [general|frank|ats|forms|all]
#   - zellij セッション内: 同名タブへ移動 / 無ければレイアウト付きで新規タブ
#   - セッション外: "dev" セッションに attach / 無ければ新規作成
#   - all: 全PJタブをまとめて開く
#
# 形は「タブ = プロジェクト、ペイン = そのPJ内の役割」。1 画面 8 分割に 4 PJ を
# 並べる dev-hub は 2026-08-11 に退役した (経緯は layouts/frank.kdl 冒頭)。
set -euo pipefail

SESSION="dev"
proj="${1:-general}"

# CLAUDE_CODE_CHILD_SESSION 汚染ガード (2026-08-09 事故の再発防止)。
# Claude 配下のシェルから起動すると、この env が zellij サーバーに焼き付いて
# 全ペインの claude が「自分はサブエージェントの子」と誤認し、transcript 保存が
# OFF になる (= exit 後に --resume 不能)。サーバーを起こす系のコマンドは必ずこれ経由。
ZJ() { env -u CLAUDE_CODE_CHILD_SESSION -u CLAUDECODE zellij "$@"; }

# proj名 -> "タブ名:レイアウト名"
resolve() {
  case "$1" in
    general) echo "General:general" ;;
    frank)   echo "Frank:frank"     ;;
    ats)     echo "ATS:ats"         ;;
    forms)   echo "Forms:forms"     ;;
    *) echo ""; return 1 ;;
  esac
}

# zellij 内: 同名タブへ移動 / 無ければレイアウト付き新規タブ
open_tab() {
  local tab="$1" layout="$2"
  if zellij action query-tab-names 2>/dev/null | grep -Fxq "$tab"; then
    zellij action go-to-tab-name "$tab" >/dev/null
  else
    ZJ action new-tab --name "$tab" --layout "$layout"
  fi
}

open_all_inside() {
  local p pair
  for p in general frank ats forms; do
    pair="$(resolve "$p")"
    open_tab "${pair%%:*}" "${pair##*:}"
  done
}

# 冷えた端末からの起動。生きているセッションにだけ attach する。
#
# ★ EXITED セッションには attach しない (2026-08-11 に zj-hub から移植)。
#   zellij の attach は EXITED を「復元ダンプ」から起こすが、ダンプに記録される
#   コマンドは claude ではなく **claude の子プロセスの MCP サーバ** になる
#   (zellij はペインの実行中コマンドを `ps -ao ppid,args` で推定するため最も
#   深い子を掴む)。復元すると MCP サーバが stdio 単体起動して即終了し、
#   「Atrae UI MCP Server started」等の出力だけが残って claude は起動しない。
#   会話本体は ~/.claude/projects/ にあるのでダンプは捨ててよい。
#
# ★ zellij 0.44.3 では `-s NAME -l LAYOUT` が「アタッチ」扱いで、セッションが
#   無いと `Session not found` で失敗する。新規作成は --new-session-with-layout。
attach_or_create() {
  local layout="$1" line
  line="$(zellij list-sessions -n 2>/dev/null | grep -E "^${SESSION} " || true)"

  if [ -n "$line" ] && printf '%s' "$line" | grep -q EXITED; then
    echo "[zj-project] EXITED の $SESSION を破棄して作り直します (復元ダンプは claude を掴めない)" >&2
    zellij delete-session --force "$SESSION" >/dev/null 2>&1 || true
    line=""
  fi

  if [ -n "$line" ]; then
    ZJ attach "$SESSION"
  else
    ZJ --session "$SESSION" --new-session-with-layout "$layout"
  fi
}

if [ "$proj" = "all" ]; then
  if [ -n "${ZELLIJ:-}" ]; then
    # 既に zellij 内: 各PJタブを個別に開く(重複回避)
    open_all_inside
  else
    # 冷えた端末: all.kdl(全4タブ)で一発起動
    attach_or_create all
  fi
  exit 0
fi

pair="$(resolve "$proj")" || { echo "usage: zj-project [general|frank|ats|forms|all]" >&2; exit 1; }
TAB="${pair%%:*}"; LAYOUT="${pair##*:}"

if [ -n "${ZELLIJ:-}" ]; then
  open_tab "$TAB" "$LAYOUT"
else
  attach_or_create "$LAYOUT"
fi
