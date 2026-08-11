#!/usr/bin/env bash
# zj-plan — Product企画オーケストレーション組織タブを開く
# Usage: zj-plan <project-dir> [name]
#
# ① Fable·オーケストレーション（左・拓也の対話窓口）
# ② Fable·企画/設計（右上・docs/ に成果物を書く）
# ③ Sol·企画レビュー（右下・review-queue watcher 常駐）
#
# 設計spec: ~/.config/zellij/docs/specs/2026-08-10-zj-plan-product-org-layout.md
set -euo pipefail

DIR="${1:?usage: zj-plan <project-dir> [name]}"
DIR=$(cd "$DIR" && pwd)
NAME="${2:-$(basename "$DIR")}"
TAB="Plan-$NAME"
SESSION="plan-$NAME"
CACHE="$HOME/.cache/zj-plan"
mkdir -p "$CACHE" "$DIR/.zj-plan/review-queue" "$DIR/.zj-plan/reviews"

# ---- protocol.md: 組織の働き方定義（初回のみ配置、既存は上書きしない） ----
PROTO="$DIR/.zj-plan/protocol.md"
if [ ! -f "$PROTO" ]; then
  cat > "$PROTO" <<'PROTOEOF'
# 企画組織プロトコル（zj-plan）

このタブは Product企画を進める3役割の組織である。最終判断は常に拓也。

## 役割

- **① Fable·オーケストレーション**（左ペイン）
  拓也との対話窓口。要望をタスクに分解し、②へ SendMessage で委譲する。
  ③へのレビュー発注と結果の統合、拓也への報告に責任を持つ。
  自分で長文の成果物を書かない（書くのは②の仕事）。
- **② Fable·企画/設計**（右上ペイン)
  ①から届いたタスクを実行し、docs/ 配下に成果物（企画書・PRD・設計文書）を書く。
  完了したら送信元へ成果物のファイルパスと要約を返信する。
- **③ Sol·企画レビュー**（右下ペイン・codex watcher）
  review-queue に置かれた依頼を自動実行する別ベンダーの独立レビュアー。

## 連携ルール

- ①↔② は ListAgents / SendMessage（クロスセッションメッセージング）。
  同一 cwd に2セッションいるので、宛先は ListAgents の [ref] で確実に指定する。
- ③への依頼は `.zj-plan/review-queue/<slug>.md` にファイルを置く（下記テンプレ）。
  結果は `.zj-plan/reviews/` に出る。①が読んで統合する。
- **レビュー対象は必ずファイル化された成果物**。書きかけ・口頭案は依頼しない。
  自由討論での合意形成は禁止（往復には必ず成果物を挟む）。
- ペインが `zellij action write-chars` で他ペインを操作することは禁止。
- 新規P1級の見解対立や設計判断そのものは、①が拓也へエスカレーションして止まる。

## レビュー依頼テンプレ（review-queue/*.md）

```markdown
effort: xhigh   # 一次発見=xhigh / 修正後の検証パス=medium

## レビュー対象
- docs/new-product-proposal.md

## 判断基準（Judgeの独立参照 — 必須）
- 解こうとしている課題 / 要件・AC / 前提資料のパス

## 観点
- 例: MVPスコープは最小か、差別化軸は成立しているか、実現性の穴
```

## 成果物の置き場所

- 企画・設計文書: プロジェクトの docs/（まるちゃん式の順序: postmortem → proposal → architecture → prd-*）
- レビュー履歴: .zj-plan/reviews/（依頼ファイルも *.request.md として保存される）
PROTOEOF
  echo "protocol.md を配置: $PROTO"
fi

# ---- 起動時プロンプト（各Fableに役割を自認させる） ----
ORCH_PROMPT="まず .zj-plan/protocol.md を読むこと。あなたはこの企画組織の①オーケストレーション担当Fableです。拓也との対話窓口として、タスク分解・②企画/設計Fableへの SendMessage 委譲・.zj-plan/review-queue/ への Solレビュー発注・結果統合を担います。読了したら ListAgents で②のセッションを確認し、体制を2行以内で報告して指示を待つこと。"
DESIGN_PROMPT="まず .zj-plan/protocol.md を読むこと。あなたはこの企画組織の②企画/設計担当Fableです。①オーケストレーションのFableから SendMessage で届くタスクを実行し、docs/ 配下に成果物を書いて送信元へファイルパスと要約を返信します。拓也から直接指示が来た場合も同様に対応。読了したら1行で準備完了を報告して待機すること。"

# ---- レイアウト生成（静的KDLは引数を取れないため生成方式） ----
LAYOUT="$CACHE/$NAME.kdl"
cat > "$LAYOUT" <<KDLEOF
layout {
    cwd "$DIR"
    tab name="$TAB" hide_floating_panes=true {
        pane size=1 borderless=true {
            plugin location="zellij:tab-bar"
        }
        pane split_direction="vertical" {
            pane name="① Fable·オーケストレーション" size="50%" command="claude-zellij" {
                args "$TAB" "--dangerously-skip-permissions" "$ORCH_PROMPT"
            }
            pane split_direction="horizontal" {
                pane name="② Fable·企画/設計" size="55%" command="claude-zellij" {
                    args "$TAB" "--dangerously-skip-permissions" "$DESIGN_PROMPT"
                }
                pane name="③ Sol·企画レビュー" command="sol-review-watch" {
                    args "$DIR"
                }
            }
        }
        pane size=1 borderless=true {
            plugin location="zellij:status-bar"
        }
    }
}
KDLEOF

# ---- 起動 ----
# CLAUDE_CODE_CHILD_SESSION 汚染ガード: Claude 配下のシェルから起動しても
# zellij サーバーに env が焼き付かないようにする（2026-08-09 事故の再発防止）
ZJ() { env -u CLAUDE_CODE_CHILD_SESSION -u CLAUDECODE zellij "$@"; }

if [ -n "${ZELLIJ:-}" ]; then
  # zellij 内: 同名タブがあれば移動、無ければタブ追加
  if zellij action query-tab-names | grep -qxF "$TAB"; then
    zellij action go-to-tab-name "$TAB"
  else
    ZJ action new-tab --layout "$LAYOUT" --name "$TAB"
  fi
else
  # zellij 外: 生きていれば attach、EXITED は復元ダンプが claude を掴めないので作り直す
  line=$(zellij list-sessions -n 2>/dev/null | grep -F "$SESSION " || true)
  if printf '%s' "$line" | grep -q EXITED; then
    zellij delete-session --force "$SESSION"
    line=""
  fi
  if [ -n "$line" ]; then
    ZJ attach "$SESSION"
  else
    ZJ --session "$SESSION" --new-session-with-layout "$LAYOUT"
  fi
fi
