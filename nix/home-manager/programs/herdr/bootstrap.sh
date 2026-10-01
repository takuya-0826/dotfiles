#!/usr/bin/env bash
# Build a herdr workspace from scratch — the replacement for the old zellij KDL
# layouts (work.kdl / cockpit.kdl).
#
# usage: herdr-bootstrap <work|cockpit|grid [ROWS] [COLS]>
#   grid [ROWS] [COLS]: 直近アクティブな ROWS×COLS 個(既定 2×4=8)のセッションを
#                       1タブのグリッド(ROWS行 × COLS列)に resume で並べる
#
# Why a script and not a config file: herdr has no declarative layout format.
# A running herdr server keeps workspaces/tabs/panes itself and restores them
# after a restart, so day to day you never run this. It exists for the cases
# persistence can't cover: a new machine, or rebuilding a workspace you closed.
#
# Each project pane gets its command TYPED IN BUT NOT RUN (`pane send-text`
# sends no newline). That is the same ergonomics as the old layouts'
# `start_suspended true`: the tab is ready, you press Enter when you want it.
set -euo pipefail

layout="${1:-}"
case "$layout" in
  work|cockpit|grid) ;;
  *) echo "usage: $(basename "$0") <work|cockpit|grid>" >&2; exit 64 ;;
esac

if ! herdr tab list >/dev/null 2>&1; then
  echo "herdr-bootstrap: no reachable herdr server. Start one with \`herdr\` first." >&2
  exit 69
fi

CLAUDE="claude"

WS_ID=""
SEED_TAB=""

# workspace <label> — create the workspace everything below goes into.
# herdr always gives a new workspace one empty tab; remember it and drop it at
# the end rather than trying to reuse it as the first project tab.
workspace() {
  local out
  out=$(herdr workspace create --label "$1" --cwd "$HOME" --no-focus)
  WS_ID=$(printf '%s' "$out" | jq -r '.result.workspace.workspace_id')
  SEED_TAB=$(printf '%s' "$out" | jq -r '.result.tab.tab_id')
  [ -n "$WS_ID" ] && [ "$WS_ID" != null ] || { echo "bootstrap: workspace create failed: $out" >&2; exit 70; }
}

# tab <label> <cwd-relative-to-HOME> [command...] → prints the new pane id
tab() {
  local label="$1" rel="$2"; shift 2
  local out pane
  out=$(herdr tab create --workspace "$WS_ID" --label "$label" --cwd "$HOME/$rel" --no-focus)
  pane=$(printf '%s' "$out" | jq -r '.result.root_pane.pane_id')
  if [ -z "$pane" ] || [ "$pane" = null ]; then
    echo "bootstrap: tab create failed for $label: $out" >&2
    exit 70
  fi
  if [ "$#" -gt 0 ]; then
    herdr pane send-text "$pane" "$*" >/dev/null
  fi
  printf '%s' "$pane"
}

# below <pane-id> <cwd-relative-to-HOME> [command...] → prints the new pane id
# herdr has no stacked panes, so the old `pane stacked=true` groups become
# ordinary splits below the project's main pane.
below() {
  local target="$1" rel="$2"; shift 2
  local out pane
  out=$(herdr pane split --pane "$target" --direction down --cwd "$HOME/$rel" --no-focus)
  pane=$(printf '%s' "$out" | jq -r '.result.pane.pane_id')
  if [ -z "$pane" ] || [ "$pane" = null ]; then
    echo "bootstrap: pane split failed under $target: $out" >&2
    exit 70
  fi
  if [ "$#" -gt 0 ]; then
    herdr pane send-text "$pane" "$*" >/dev/null
  fi
  printf '%s' "$pane"
}

# right <target-pane> <cwd-relative-to-HOME> [command...] → prints the new pane id.
# below の横方向版（split-right）。grid を組むのに使う。
right() {
  local target="$1" rel="$2"; shift 2
  local out pane
  out=$(herdr pane split --pane "$target" --direction right --cwd "$HOME/$rel" --no-focus)
  pane=$(printf '%s' "$out" | jq -r '.result.pane.pane_id')
  if [ -z "$pane" ] || [ "$pane" = null ]; then
    echo "bootstrap: pane split (right) failed under $target: $out" >&2
    exit 70
  fi
  if [ "$#" -gt 0 ]; then
    herdr pane send-text "$pane" "$*" >/dev/null
  fi
  printf '%s' "$pane"
}

build_work() {
  workspace Work
  local p

  p=$(tab Alchemy      "Projects/alchemy"                                  $CLAUDE -c)
  below "$p" "Projects/alchemy" nr dev >/dev/null

  tab English      "Projects/learn-english-app"                        $CLAUDE -c >/dev/null
  tab Widget       "Projects/wevox/wevox-mono-web/web-progressive"     $CLAUDE    >/dev/null
  tab Sort         "Projects/wevox"                                    $CLAUDE    >/dev/null
  tab Menu         "Projects/wevox/wevox-mono-web/web-progressive"     nvim       >/dev/null

  p=$(tab Croupier     "Projects/croupier"                                 $CLAUDE)
  below "$p" "Projects/croupier" nr dev >/dev/null

  tab Analytics    "Projects/wevox/wevox-mono-web/web-progressive"     $CLAUDE    >/dev/null
  tab dotfiles     "dotfiles"                                          $CLAUDE    >/dev/null

  p=$(tab DesignSystem "Projects/atrae-ui"                                 $CLAUDE)
  below "$p" "Projects/atrae-ui" >/dev/null

  tab Logo         "Projects/sandbox/wevox-logo-generator-handson"     $CLAUDE    >/dev/null
}

build_cockpit() {
  workspace Cockpit
  local p
  # Cockpit ran everything through claude's remote-control mode.
  local cc="$CLAUDE --remote-control -c"

  p=$(tab wevox "Projects/wevox" $cc)
  below "$p" "Projects/wevox" >/dev/null

  p=$(tab web-progressive "Projects/wevox/wevox-mono-web/web-progressive" $cc)
  below "$p" "Projects/wevox/wevox-mono-web/web-progressive" >/dev/null
  below "$p" "Projects/wevox/wevox" >/dev/null

  p=$(tab rest-bff "Projects/wevox/wevox-rest-bff" $cc)
  below "$p" "Projects/wevox/wevox-rest-bff" >/dev/null

  p=$(tab front "Projects/wevox/wevox-front" $cc)
  below "$p" "Projects/wevox/wevox-front" >/dev/null
  below "$p" "Projects/manifest" >/dev/null

  p=$(tab review "Projects" gh-review-watcher)
  below "$p" "Projects" >/dev/null

  p=$(tab scratch "Projects")
  below "$p" "Projects" >/dev/null

  p=$(tab dotfiles "dotfiles" $cc)
  below "$p" "dotfiles" >/dev/null
}

# grid [ROWS] [COLS]: 直近アクティブな ROWS×COLS 個(既定 2×4)のセッションを 1 タブ内の
# グリッド(ROWS行 × COLS列)に並べる。各ペインは cd 済み + `claude --resume <session-id>` を
# 入力済み(未実行, Enter で起動)。行優先で敷き詰める(セッションが足りなければ埋まる分だけ)。
#
# なぜ -c(continue) でなく resume <id> か: -c は「その dir の最新セッション」を継続するので、
# 同じディレクトリに複数セッションがあると取り違えるし、grid に同 dir が2枚あると両方が
# 同じセッションを掴んで競合する。セッションID を明示すれば取り違え・競合しない。

# grid ヘルパー（すべて HOME で split し、割当時に cd で移動する）。
# 均等サイズにするため「半分ずつ再帰分割(balanced)」する: 行/列が power-of-2(2,4,8…)なら
# 全ペイン完全に均等。逐次 split(50/25/12.5…) の偏りを避けるのが目的。
# build_grid の local(SIDS/CWDS/total/cols) は bash の動的スコープで各ヘルパーから見える。

grid_assign() {  # <pane> <session-index> : 名前 + `cd <cwd> && claude --resume <id>` を入力(未実行)
  local pane="$1" cwd="${CWDS[$2]}" sid="${SIDS[$2]}"
  herdr pane rename "$pane" "$(basename "$cwd")" >/dev/null 2>&1 || true
  herdr pane send-text "$pane" "cd $(printf '%q' "$cwd") && $CLAUDE --resume $sid" >/dev/null
}

grid_split1() {  # <right|down> <target-pane> → 新ペイン id (cwd は割当時に cd で合わせる)
  local out pane
  out=$(herdr pane split --pane "$2" --direction "$1" --cwd "$HOME" --no-focus)
  pane=$(printf '%s' "$out" | jq -r '.result.pane.pane_id')
  [ -n "$pane" ] && [ "$pane" != null ] || { echo "grid: split failed: $out" >&2; exit 70; }
  printf '%s' "$pane"
}

# <pane> を <dir> 方向に <k> 個の均等ペインへ分割し、セッション[ks..ks+k-1]を視覚順で割当。
grid_place() {  # <dir> <pane> <ks> <k>
  local dir="$1" pane="$2" ks="$3" k="$4"
  if [ "$k" -le 1 ]; then grid_assign "$pane" "$ks"; return; fi
  local half=$((k / 2)) rest np
  rest=$((k - half))
  np=$(grid_split1 "$dir" "$pane")               # pane=前半(左/上), np=後半(右/下)
  grid_place "$dir" "$pane" "$ks"            "$half"
  grid_place "$dir" "$np"   "$((ks + half))" "$rest"
}

# <pane> を下方向に <nr> 行へ均等分割し、各行(全幅)を列に割ってセッションを敷き詰める。
# 行を全部先に切ってから列に割るので各行が全幅になる。
grid_rows() {  # <pane> <row-start> <nr>
  local pane="$1" rs="$2" nr="$3"
  if [ "$nr" -le 1 ]; then
    local ch=$((total - rs * cols)); [ "$ch" -gt "$cols" ] && ch=$cols   # 最終行は余りだけ
    grid_place right "$pane" "$((rs * cols))" "$ch"
    return
  fi
  local half=$((nr / 2)) rest np
  rest=$((nr - half))
  np=$(grid_split1 down "$pane")
  grid_rows "$pane" "$rs"            "$half"
  grid_rows "$np"   "$((rs + half))" "$rest"
}

build_grid() {
  local rows="${1:-2}" cols="${2:-4}"
  case "$rows" in ''|*[!0-9]*) rows=2 ;; esac
  case "$cols" in ''|*[!0-9]*) cols=4 ;; esac
  [ "$rows" -ge 1 ] 2>/dev/null || rows=2
  [ "$cols" -ge 1 ] 2>/dev/null || cols=4
  local n=$((cols * rows))

  # 直近アクティブな N セッションを .jsonl の mtime 順で拾う（このセッションは除外）。
  local SELF="7990c3e2-fa2b-4903-ae64-eeafdf18ef89"
  # NOTE: カウンタで数える。set -u の bash 3.2 では空配列の ${#arr[@]} が
  # "unbound variable" になるため、${#SIDS[@]} は使わない。
  local -a SIDS=() CWDS=()
  local f sid cwd count=0
  while IFS= read -r f; do
    [ "$count" -ge "$n" ] && break
    sid=$(basename "$f" .jsonl)
    [ "$sid" = "$SELF" ] && continue
    # cwd はセッション transcript から (grep -m1 で先頭の "cwd":"..." を高速抽出)
    cwd=$(grep -m1 -oE '"cwd":"[^"]+"' "$f" 2>/dev/null | sed 's/^"cwd":"//; s/"$//')
    [ -n "$cwd" ] && [ -d "$cwd" ] || continue
    SIDS[$count]="$sid"; CWDS[$count]="$cwd"; count=$((count + 1))
  done < <(ls -t "$HOME"/.claude/projects/*/*.jsonl 2>/dev/null)

  local total=$count
  [ "$total" -ge 1 ] || { echo "grid: 対象セッションが見つかりません (~/.claude/projects/*/*.jsonl)" >&2; exit 1; }

  workspace Grid
  # 実際に使う行数 = ceil(total/cols)（total は rows*cols で上限済みなので rows 以下）
  local arows=$(((total + cols - 1) / cols))
  [ "$arows" -gt "$rows" ] && arows=$rows

  # グリッドの最初のペイン（タブの root）を HOME で作る
  local out first
  out=$(herdr tab create --workspace "$WS_ID" --label grid --cwd "$HOME" --no-focus)
  first=$(printf '%s' "$out" | jq -r '.result.root_pane.pane_id')
  [ -n "$first" ] && [ "$first" != null ] || { echo "grid: tab create failed: $out" >&2; exit 70; }

  grid_rows "$first" 0 "$arows"    # 均等に行→列へ分割してセッションを敷き詰める
  echo "grid: $total セッションを ${rows}行×${cols}列(均等)グリッドに配置（各ペインで Enter → resume）"
}

case "$layout" in
  work)    build_work ;;
  cockpit) build_cockpit ;;
  grid)    build_grid "${2:-}" "${3:-}" ;;
esac

# Drop the empty tab herdr created with the workspace.
[ -n "$SEED_TAB" ] && [ "$SEED_TAB" != null ] && herdr tab close "$SEED_TAB" >/dev/null 2>&1 || true

echo "herdr-bootstrap: built '$layout' in workspace $WS_ID"
echo "  各タブのコマンドは入力済みで未実行。 Enter で起動する。"
