#!/usr/bin/env bash
# sol-review-watch — zj-plan 組織の ③ Sol·企画レビュー ペイン常駐 watcher
# Usage: sol-review-watch <project-dir>
#
# <dir>/.zj-plan/review-queue/*.md をポーリングし、依頼ごとに
# codex exec (gpt-5.6-sol, read-only sandbox) でレビューを実行して
# <dir>/.zj-plan/reviews/ に保存する。依頼ファイルのフロントマター
# `effort: xhigh|high|medium|low` で推論強度を指定（既定 xhigh）。
set -u

DIR="${1:?usage: sol-review-watch <project-dir>}"
DIR=$(cd "$DIR" && pwd)
QUEUE="$DIR/.zj-plan/review-queue"
OUT="$DIR/.zj-plan/reviews"
WORK="$DIR/.zj-plan/processing"
mkdir -p "$QUEUE" "$OUT" "$WORK"

echo "🧑‍⚖️ Sol·企画レビュー watcher 起動"
echo "   依頼: ${QUEUE#$DIR/}/ に .md を置く（テンプレは protocol.md 参照）"
echo "   結果: ${OUT#$DIR/}/ に出力"
echo ""

while true; do
  for req in "$QUEUE"/*.md; do
    [ -e "$req" ] || continue
    base=$(basename "$req" .md)
    ts=$(date +%Y%m%d-%H%M%S)
    work="$WORK/$base.md"
    mv "$req" "$work" || continue

    effort=$(sed -n 's/^effort:[[:space:]]*//p' "$work" | head -1)
    case "$effort" in xhigh|high|medium|low) ;; *) effort=xhigh ;; esac

    out="$OUT/$ts-$base.md"
    echo "▶ $(date +%H:%M:%S) レビュー開始: $base (effort=$effort)"
    {
      echo "# Sol review: $base ($ts, effort=$effort)"
      echo ""
      codex exec --cd "$DIR" --sandbox read-only --skip-git-repo-check \
        -m gpt-5.6-sol -c model_reasoning_effort="$effort" \
        "あなたは独立レビュアーの Sol です。以下のレビュー依頼に従い、対象ファイルを自分で読んで企画/設計レビューを日本語で返してください。ルール: (1) 指摘は P0(致命)/P1(重要)/P2(改善) の重大度つき箇条書き (2) 依頼に判断基準・要件があれば、文書の見た目ではなくそれへの適合で判定する (3) 良い点の羅列は不要、最後に総評1段落のみ。

$(cat "$work")"
    } | tee "$out"
    mv "$work" "$OUT/$ts-$base.request.md"
    echo ""
    echo "✅ $(date +%H:%M:%S) 出力: ${out#$DIR/}"
    echo ""
  done
  sleep 3
done
