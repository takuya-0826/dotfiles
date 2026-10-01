#!/usr/bin/env bash
# sol-review-watch — zj-plan 組織の Sol レビュー ペインに常駐する watcher
# Usage: sol-review-watch <project-dir> [lane]
#
#   lane=plan (既定) … ③ Sol·企画レビュー
#       依頼: <dir>/.zj-plan/review-queue/*.md → 結果: <dir>/.zj-plan/reviews/
#   lane=impl        … ⑤ Sol·実装レビュー
#       依頼: <dir>/.zj-plan/impl-queue/*.md   → 結果: <dir>/.zj-plan/impl-reviews/
#
# 依頼ファイルのフロントマター `effort: xhigh|high|medium|low` で推論強度を
# 指定する（既定 xhigh。CLAUDE.md のレビュー規律に従い、一次発見は xhigh、
# 修正後の検証パスは medium を書く）。
#
# 差分を監視して自動レビューする方式は採らない。①オーケストレーションが
# 明示的にキューへ投げる形にすることで「往復には必ず成果物を挟む」を守り、
# 書きかけコードへの指摘で ChatGPT 枠を捨てるのを避ける。
set -u

DIR="${1:?usage: sol-review-watch <project-dir> [plan|impl]}"
DIR=$(cd "$DIR" && pwd)
LANE="${2:-plan}"

case "$LANE" in
  plan)
    QUEUE="$DIR/.zj-plan/review-queue"
    OUT="$DIR/.zj-plan/reviews"
    LABEL="🧑‍⚖️ Sol·企画レビュー"
    ROLE="あなたは独立レビュアーの Sol です。以下のレビュー依頼に従い、対象ファイルを自分で読んで企画/設計レビューを日本語で返してください。ルール: (1) 指摘は P0(致命)/P1(重要)/P2(改善) の重大度つき箇条書き (2) 依頼に判断基準・要件があれば、文書の見た目ではなくそれへの適合で判定する (3) 良い点の羅列は不要、最後に総評1段落のみ。"
    ;;
  impl)
    QUEUE="$DIR/.zj-plan/impl-queue"
    OUT="$DIR/.zj-plan/impl-reviews"
    LABEL="🔍 Sol·実装レビュー"
    ROLE="あなたは独立レビュアーの Sol です。以下のレビュー依頼に従い、対象の差分/ファイルを自分で読んで実装レビューを日本語で返してください。ルール: (1) 指摘は P0(致命)/P1(重要)/P2(改善) の重大度つき箇条書きで、必ず file:line を添える (2) 判定基準は「コードとして変か」ではなく「依頼に書かれた要件・AC を満たすか」。要件が渡されていなければ、まずそれを指摘する (3) 既存ロジックの消失・回帰・境界値・エラーパスを優先して見る (4) 良い点の羅列は不要、最後に総評1段落のみ。"
    ;;
  *)
    echo "usage: sol-review-watch <project-dir> [plan|impl]" >&2
    exit 1
    ;;
esac

WORK="$DIR/.zj-plan/processing-$LANE"
mkdir -p "$QUEUE" "$OUT" "$WORK"

echo "$LABEL watcher 起動 (lane=$LANE)"
echo "   依頼: ${QUEUE#"$DIR"/}/ に .md を置く（テンプレは protocol.md 参照）"
echo "   結果: ${OUT#"$DIR"/}/ に出力"
echo ""

while true; do
  for req in "$QUEUE"/*.md; do
    [ -e "$req" ] || continue
    base=$(basename "$req" .md)
    ts=$(date +%Y%m%d-%H%M%S)
    work="$WORK/$base.md"
    mv "$req" "$work" || continue

    effort=$(sed -n 's/^effort:[[:space:]]*//p' "$work" | head -1)
    case "$effort" in xhigh | high | medium | low) ;; *) effort=xhigh ;; esac

    out="$OUT/$ts-$base.md"
    echo "▶ $(date +%H:%M:%S) レビュー開始: $base (lane=$LANE, effort=$effort)"
    {
      echo "# Sol review [$LANE]: $base ($ts, effort=$effort)"
      echo ""
      codex exec --cd "$DIR" --sandbox read-only --skip-git-repo-check \
        -m gpt-5.6-sol -c model_reasoning_effort="$effort" \
        "$ROLE

$(cat "$work")"
    } | tee "$out"
    mv "$work" "$OUT/$ts-$base.request.md"
    echo ""
    echo "✅ $(date +%H:%M:%S) 出力: ${out#"$DIR"/}"
    echo ""
  done
  sleep 3
done
