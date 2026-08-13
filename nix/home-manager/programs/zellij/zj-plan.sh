#!/usr/bin/env bash
# zj-plan — Product企画オーケストレーション組織タブを開く
# Usage: zj-plan <project-dir> [name]
#
# ┌──────────────┬──────────────┬──────────────┐
# │              │ ②企画/計画   │ ④実装        │
# │ ①オーケスト  │  Fable       │  Fable       │
# │   レーション  ├──────────────┼──────────────┤
# │  (拓也の窓口) │ ③企画レビュー│ ⑤実装レビュー│
# │              │  Sol watcher │  Sol watcher │
# └──────────────┴──────────────┴──────────────┘
#     左 40%          中 30%          右 30%
#
# 「左 = 指揮 / 中 = 企画レーン / 右 = 実装レーン」で、各レーンが
# 「作る人・レビューする人」の対になる。2026-08-13 に ④⑤ を追加して
# 3 役割 → 5 役割にした。
#
# 設計spec: ~/.config/zellij/docs/specs/2026-08-10-zj-plan-product-org-layout.md
set -euo pipefail

DIR="${1:?usage: zj-plan <project-dir> [name]}"
DIR=$(cd "$DIR" && pwd)
NAME="${2:-$(basename "$DIR")}"
TAB="Plan-$NAME"
SESSION="plan-$NAME"
CACHE="$HOME/.cache/zj-plan"
mkdir -p "$CACHE" \
  "$DIR/.zj-plan/review-queue" "$DIR/.zj-plan/reviews" \
  "$DIR/.zj-plan/impl-queue" "$DIR/.zj-plan/impl-reviews"

# ---- protocol.md: 組織の働き方定義 ----
# 5 役割化 (2026-08-13) 以前の 3 役割版が残っている場合は .bak へ退避して書き直す。
# 手で書き足した内容を黙って捨てないよう、退避したことを必ず表示する。
PROTO="$DIR/.zj-plan/protocol.md"
if [ -f "$PROTO" ] && ! grep -q '⑤ Sol·実装レビュー' "$PROTO"; then
  cp -f "$PROTO" "$PROTO.bak"
  echo "⚠️  protocol.md が 3 役割版だったので $PROTO.bak へ退避して更新します" >&2
  rm -f "$PROTO"
fi
if [ ! -f "$PROTO" ]; then
  cat > "$PROTO" <<'PROTOEOF'
# 企画組織プロトコル（zj-plan）

このタブは Product企画から実装までを進める5役割の組織である。最終判断は常に拓也。

## 役割

- **① Fable·オーケストレーション**（左ペイン）
  拓也との対話窓口。要望をタスクに分解し、②（企画）④（実装）へ SendMessage で
  委譲する。③⑤へのレビュー発注と結果の統合、拓也への報告に責任を持つ。
  自分で長文の成果物を書かない（書くのは②④の仕事）。
- **② Fable·企画/計画**（中央上ペイン）
  ①から届いたタスクを実行し、docs/ 配下に成果物（企画書・PRD・設計文書）を書く。
  完了したら送信元へ成果物のファイルパスと要約を返信する。
- **③ Sol·企画レビュー**（中央下ペイン・codex watcher）
  `.zj-plan/review-queue/` に置かれた依頼を自動実行する別ベンダーの独立レビュアー。
- **④ Fable·実装**（右上ペイン）
  ②の成果物が固まってから動く。①から届いたタスクを実装し、変更したファイルと
  テスト結果を送信元へ返信する。設計を勝手に変えない（変えたくなったら①に上げる）。
- **⑤ Sol·実装レビュー**（右下ペイン・codex watcher）
  `.zj-plan/impl-queue/` に置かれた依頼を自動実行する。差分の監視ではなく
  ①からの明示発注で動く。

## 連携ルール

- ①↔②④ は ListAgents / SendMessage（クロスセッションメッセージング）。
  同一 cwd に複数セッションがいるので、宛先は ListAgents の [ref] で確実に指定する。
- ③への依頼は `.zj-plan/review-queue/<slug>.md`、⑤への依頼は
  `.zj-plan/impl-queue/<slug>.md` にファイルを置く（下記テンプレ）。
  結果はそれぞれ `.zj-plan/reviews/` `.zj-plan/impl-reviews/` に出る。①が読んで統合する。
- **レビュー対象は必ずファイル化された成果物**。書きかけ・口頭案は依頼しない。
  自由討論での合意形成は禁止（往復には必ず成果物を挟む）。
- ペインが `zellij action write-chars` で他ペインを操作することは禁止。
- 新規P1級の見解対立や設計判断そのものは、①が拓也へエスカレーションして止まる。
- レビューは上限2パス。1巡目で発見、2巡目は修正差分だけを検証。終了条件は
  「新規 P0/P1 がゼロ」。P2以下は起票して先へ進む。検証パスで新規P1が出たら
  ラウンドを増やさず拓也へエスカレーションする。

## レビュー依頼テンプレ（review-queue / impl-queue 共通）

```markdown
effort: xhigh   # 一次発見=xhigh / 修正後の検証パス=medium

## レビュー対象
- docs/new-product-proposal.md        # ③の場合
- git diff の範囲 / 変更ファイルのパス  # ⑤の場合

## 判断基準（Judgeの独立参照 — 必須）
- 解こうとしている課題 / 要件・AC / 前提資料のパス / テスト結果

## 観点
- ③の例: MVPスコープは最小か、差別化軸は成立しているか、実現性の穴
- ⑤の例: 要件を満たすか、既存ロジックの消失・回帰、境界値とエラーパス
```

## 成果物の置き場所

- 企画・設計文書: プロジェクトの docs/（まるちゃん式の順序: postmortem → proposal → architecture → prd-*）
- レビュー履歴: .zj-plan/reviews/ と .zj-plan/impl-reviews/（依頼ファイルも *.request.md として保存される）
PROTOEOF
  echo "protocol.md を配置: $PROTO"
fi

# ---- 起動時プロンプト（各Fableに役割を自認させる） ----
ORCH_PROMPT="まず .zj-plan/protocol.md を読むこと。あなたはこの企画組織の①オーケストレーション担当Fableです。拓也との対話窓口として、タスク分解・②企画/計画Fableと④実装Fableへの SendMessage 委譲・.zj-plan/review-queue/ と .zj-plan/impl-queue/ へのSolレビュー発注・結果統合を担います。読了したら ListAgents で②④のセッションを確認し、体制を2行以内で報告して指示を待つこと。"
DESIGN_PROMPT="まず .zj-plan/protocol.md を読むこと。あなたはこの企画組織の②企画/計画担当Fableです。①オーケストレーションのFableから SendMessage で届くタスクを実行し、docs/ 配下に成果物を書いて送信元へファイルパスと要約を返信します。拓也から直接指示が来た場合も同様に対応。読了したら1行で準備完了を報告して待機すること。"
IMPL_PROMPT="まず .zj-plan/protocol.md を読むこと。あなたはこの企画組織の④実装担当Fableです。①オーケストレーションのFableから SendMessage で届くタスクを実装し、変更したファイルのパスとテスト結果を送信元へ返信します。②が書いた設計を勝手に変えないこと（変更が要ると判断したら実装せず①へ上げる）。読了したら1行で準備完了を報告して待機すること。"

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
            pane name="① Fable·オーケストレーション" size="40%" command="claude-zellij" {
                args "$TAB" "--dangerously-skip-permissions" "$ORCH_PROMPT"
            }
            pane split_direction="horizontal" size="30%" {
                pane name="② Fable·企画/計画" size="55%" command="claude-zellij" {
                    args "$TAB" "--dangerously-skip-permissions" "$DESIGN_PROMPT"
                }
                pane name="③ Sol·企画レビュー" command="sol-review-watch" {
                    args "$DIR" "plan"
                }
            }
            pane split_direction="horizontal" size="30%" {
                pane name="④ Fable·実装" size="55%" command="claude-zellij" {
                    args "$TAB" "--dangerously-skip-permissions" "$IMPL_PROMPT"
                }
                pane name="⑤ Sol·実装レビュー" command="sol-review-watch" {
                    args "$DIR" "impl"
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
  # zellij 外: セッションが生きていれば attach、無ければ新規作成
  # (session_serialization は 2026-08-13 に外したので EXITED の復元ダンプは無い)
  if zellij list-sessions -n 2>/dev/null | grep -q "^$SESSION "; then
    ZJ attach "$SESSION"
  else
    ZJ --session "$SESSION" --new-session-with-layout "$LAYOUT"
  fi
fi
