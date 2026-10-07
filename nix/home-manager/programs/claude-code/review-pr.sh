#!/usr/bin/env bash
set -euo pipefail

URL="$1"
NUMBER="$2"
REPO="$3"

echo "🔍 Reviewing PR #${NUMBER} in ${REPO}..."
echo ""

# Step 0: PR のメタデータを gh で取得 (Author, Title, Base/Head, Additions/Deletions など)
PR_META_JSON=$(gh pr view "$NUMBER" -R "$REPO" --json \
  title,author,baseRefName,headRefName,additions,deletions,changedFiles,isDraft,mergeStateStatus,createdAt 2>/dev/null || echo "{}")

PR_TITLE=$(echo "$PR_META_JSON" | jq -r '.title // "(タイトル取得失敗)"')
PR_AUTHOR=$(echo "$PR_META_JSON" | jq -r '.author.login // "?"')
PR_BASE=$(echo "$PR_META_JSON" | jq -r '.baseRefName // "?"')
PR_HEAD=$(echo "$PR_META_JSON" | jq -r '.headRefName // "?"')
PR_ADD=$(echo "$PR_META_JSON" | jq -r '.additions // 0')
PR_DEL=$(echo "$PR_META_JSON" | jq -r '.deletions // 0')
PR_FILES=$(echo "$PR_META_JSON" | jq -r '.changedFiles // 0')
PR_DRAFT=$(echo "$PR_META_JSON" | jq -r '.isDraft // false')
PR_STATE=$(echo "$PR_META_JSON" | jq -r '.mergeStateStatus // "?"')
PR_CREATED=$(echo "$PR_META_JSON" | jq -r '.createdAt // "?"' | cut -d'T' -f1)
PR_DRAFT_BADGE=""
[ "$PR_DRAFT" = "true" ] && PR_DRAFT_BADGE=" [DRAFT]"

# Step 0.5: CI (status checks) の状態を取得。
# gh pr checks は「全て pass でない」と exit 1 を返すので、|| true で握りつぶして出力だけ拾う。
CI_JSON=$(gh pr checks "$NUMBER" -R "$REPO" --json name,state,bucket 2>/dev/null) || true
[ -z "${CI_JSON// }" ] && CI_JSON='[]'
CI_FAILED=$(echo "$CI_JSON" | jq -r '[.[] | select(.bucket=="fail" or .bucket=="cancel")] | map(.name) | join(", ")')
CI_PENDING_N=$(echo "$CI_JSON" | jq -r '[.[] | select(.bucket=="pending")] | length')
CI_TOTAL=$(echo "$CI_JSON" | jq -r 'length')
if [ -n "$CI_FAILED" ]; then
  CI_STATUS="FAIL"
  CI_LINE="⛔ FAIL — 失敗: ${CI_FAILED}"
elif [ "${CI_PENDING_N:-0}" -gt 0 ]; then
  CI_STATUS="PENDING"
  CI_LINE="⏳ 実行中 (${CI_PENDING_N} 件 pending)"
elif [ "${CI_TOTAL:-0}" -gt 0 ]; then
  CI_STATUS="PASS"
  CI_LINE="✅ 全て pass (${CI_TOTAL} checks)"
else
  CI_STATUS="NONE"
  CI_LINE="— (status check なし)"
fi

# Step 0.7: diff を1回だけ取得し、各行に絶対行番号 [LINE N] を付与しておく (グローバル)。
# これを (a) 構造化抽出の入力、(b) print_hunk の hunk 表示、の両方で使い回す。
# +行・コンテキスト行(スペース始まり)にタグを付ける。削除行(-)は変更後行番号を持たないので付けない。
DIFF=""
ANNOTATED_DIFF=""
build_annotated_diff() {
  DIFF=$(gh pr diff "$NUMBER" -R "$REPO" 2>/dev/null || true)
  if [[ -z "${DIFF// }" ]]; then ANNOTATED_DIFF=""; return 0; fi
  ANNOTATED_DIFF=$(printf '%s\n' "$DIFF" | awk '
    # git は非 ASCII を含むパスを C クォート形式で出す:
    #   +++ "b/code/.../\350\250\255\345\256\232....md"
    # これを素の UTF-8 に戻す。戻さないと path が壊れ、投稿時に GitHub が位置を
    # 解決できず 422 ("Line could not be resolved") になる。
    function unquote_path(s,   out, i, c, n, k) {
      if (substr(s, 1, 1) != "\"") return s
      s = substr(s, 2, length(s) - 2)
      out = ""; i = 1
      while (i <= length(s)) {
        c = substr(s, i, 1)
        if (c != "\\") { out = out c; i++; continue }
        n = substr(s, i + 1, 1)
        if (n ~ /^[0-7]$/) {
          k = (substr(s, i+1, 1) + 0) * 64 + (substr(s, i+2, 1) + 0) * 8 + (substr(s, i+3, 1) + 0)
          out = out sprintf("%c", k); i += 4
        } else if (n == "n") { out = out "\n"; i += 2 }
        else if (n == "t")   { out = out "\t"; i += 2 }
        else                 { out = out n;    i += 2 }
      }
      return out
    }
    # ヘッダは正規化した (クォートを外した) 形で出力する。後段の print_hunk と
    # 抽出プロンプトはどちらも "+++ b/<path>" の形を前提にしているため。
    /^diff --git/ { file="" }
    /^\+\+\+ / {
      p = unquote_path(substr($0, 5))
      if (p == "/dev/null") { file=""; print "+++ /dev/null"; next }
      sub(/^b\//, "", p)
      file = p
      printf "+++ b/%s\n", p
      next
    }
    /^--- / {
      p = unquote_path(substr($0, 5))
      if (p == "/dev/null") { print "--- /dev/null"; next }
      sub(/^a\//, "", p)
      printf "--- a/%s\n", p
      next
    }
    /^@@ / {
      s = $0
      sub(/^@@ -[0-9,]+ \+/, "", s)
      sub(/,.*/, "", s)
      newline = s + 0
      print
      next
    }
    file != "" && /^[-+ ]/ {
      prefix = substr($0, 1, 1)
      if (prefix == "-") {
        print
      } else {
        printf "[LINE %d] %s\n", newline, $0
        newline++
      }
      next
    }
    { print }
  ')
}
build_annotated_diff

# print_hunk <path> <line> [ctx]: ANNOTATED_DIFF から該当ファイルの、[LINE <line>] を含む
# hunk の窓 (±ctx 行) を出力する。対象行に ▶、行番号ガター付き、削除行(-)も窓内なら表示。
# 該当行が diff に無ければ「diff に該当箇所なし」。POSIX awk (macOS の BWK awk) で書く。
print_hunk() {
  local path="$1" line="$2" ctx="${3:-3}"
  if [[ -z "${ANNOTATED_DIFF// }" ]]; then echo "     （diff 取得なし）"; return; fi
  printf '%s\n' "$ANNOTATED_DIFF" | awk -v path="$path" -v target="$line" -v ctx="$ctx" '
    function flush(   i,start,end,mark,gut,col,c,z) {
      if (!hit) { n=0; return }
      z="\033[0m"
      start=tgt-ctx; if(start<1)start=1
      end=tgt+ctx;   if(end>n)end=n
      for(i=start;i<=end;i++){
        c=substr(text[i],1,1)
        if(c=="+") col="\033[32m"; else if(c=="-") col="\033[31m"; else col=""
        mark=(num[i]==target)?"▶":" "
        if(num[i]<0) gut="    "; else gut=sprintf("%4d",num[i])
        printf "   %s %s | %s%s%s\n", mark, gut, col, text[i], z
      }
      printed=1; n=0; hit=0
    }
    BEGIN{ infile=0; n=0; hit=0; printed=0 }
    /^diff --git/ { if(infile) flush(); infile=0; n=0; hit=0; next }
    /^--- / { next }
    /^\+\+\+ / { f=substr($0,7); infile=(f==path)?1:0; n=0; hit=0; next }
    /^@@ / { if(infile) flush(); n=0; hit=0; next }
    {
      if(!infile) next
      if(substr($0,1,6)=="[LINE "){
        rb=index($0,"]")
        num[++n]=substr($0,7,rb-7)+0
        text[n]=substr($0,rb+2)
        if(num[n]==target){hit=1;tgt=n}
      } else if(substr($0,1,1)=="-"){
        num[++n]=-1
        text[n]=$0
      }
    }
    END{ if(infile) flush(); if(!printed) print "     （diff に該当箇所なし）" }
  '
}

# render_section <severity> <emoji> <title>: FINDINGS_JSON から該当 severity の指摘を並べ、
# 各指摘の直下に print_hunk で実 diff を出す。
render_section() {
  local sev="$1" emoji="$2" title="$3"
  local n
  n=$(echo "$FINDINGS_JSON" | jq --arg s "$sev" '[.findings[]? | select(.severity==$s)] | length' 2>/dev/null || echo 0)
  echo "## ${emoji} ${title} (${n})"
  if [ "${n:-0}" -eq 0 ]; then echo "なし"; echo ""; return; fi
  local i=0 path line body loc
  while [ "$i" -lt "$n" ]; do
    path=$(echo "$FINDINGS_JSON" | jq -r --arg s "$sev" --argjson i "$i" '[.findings[]?|select(.severity==$s)][$i].path // ""')
    line=$(echo "$FINDINGS_JSON" | jq -r --arg s "$sev" --argjson i "$i" '[.findings[]?|select(.severity==$s)][$i].line // empty')
    body=$(echo "$FINDINGS_JSON" | jq -r --arg s "$sev" --argjson i "$i" '[.findings[]?|select(.severity==$s)][$i].body // ""')
    loc="$path"; [ -n "$line" ] && loc="${path}:${line}"
    echo "${emoji} ${loc} — ${body}"
    if [ -n "$path" ] && [ -n "$line" ]; then
      print_hunk "$path" "$line"
    else
      echo "     （位置情報なし — 変更行外の指摘）"
    fi
    echo ""
    i=$((i + 1))
  done
}

# render_review: FINDINGS_JSON + PR メタ + ANNOTATED_DIFF から、タブ表示を shell で組み立てる。
render_review() {
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║  PR #${NUMBER} — ${REPO}${PR_DRAFT_BADGE}"
  echo "║  ${PR_TITLE}"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "## 📌 PR Info"
  echo "- 👤 Author:  ${PR_AUTHOR}"
  echo "- 🌿 Branch:  \`${PR_HEAD}\` → \`${PR_BASE}\`"
  echo "- 📊 Diff:    +${PR_ADD} / -${PR_DEL}  (${PR_FILES} files)"
  echo "- 🗓  Created: ${PR_CREATED}"
  echo "- 🧭 State:   ${PR_STATE}"
  echo "- 🚦 CI:      ${CI_LINE}"
  echo "- 🔗 URL:     ${URL}"
  echo ""
  echo "────────────────────────────────────────────────────────────────────"

  local verdict reason vemoji
  verdict=$(echo "$FINDINGS_JSON" | jq -r '.verdict // "DISCUSS"')
  reason=$(echo "$FINDINGS_JSON" | jq -r '.verdict_reason // ""')
  case "$verdict" in
    APPROVE)         vemoji="✅" ;;
    REQUEST_CHANGES) vemoji="⛔" ;;
    SKIP)            vemoji="⏭️" ;;
    *)               vemoji="💬" ;;
  esac
  echo "## 🎯 Verdict"
  echo "${vemoji} ${verdict} — ${reason}"
  echo ""
  echo "## 📋 Summary"
  echo "$FINDINGS_JSON" | jq -r '.summary[]? | "- " + .'
  local sc
  sc=$(echo "$FINDINGS_JSON" | jq -r '(.summary // []) | length' 2>/dev/null || echo 0)
  [ "${sc:-0}" -eq 0 ] && echo "- (なし)"
  echo ""
  echo "────────────────────────────────────────────────────────────────────"
  render_section blocker    "⛔" "Blockers"
  echo "────────────────────────────────────────────────────────────────────"
  render_section suggestion "💡" "Suggestions"
  echo "────────────────────────────────────────────────────────────────────"
  render_section note       "📝" "Notes"
}

# レビュー生成 + 構造化抽出 + 表示。[r] で丸ごと再実行できる。
# REVIEW_RESULT (生レビュー) と FINDINGS_JSON (構造化) をグローバルに残す ([d]/[c] が使う)。
REVIEW_RESULT=""
FINDINGS_JSON='{"findings":[]}'
run_review() {
  echo "🔍 レビュー生成中..."
  # Step 1: claude -p でレビュー実行。
  # `/review <URL>` は使わない: そんなスラッシュコマンドは存在せず、code-review スキルに
  # 流れて「カレントディレクトリの diff」がレビューされてしまう。レビュータブの cwd は
  # 開いた時のフォーカス中ペインの cwd を継いで無関係な worktree になりうるため、実測で
  # 「PR #11478 を頼んだのに atrae-ui の git diff main...HEAD がレビューされる」事故が出た。
  # → 対象をプロンプト内で完結させ、cwd に一切依存しない形にする。
  local REVIEW_PROMPT
  REVIEW_PROMPT="次の GitHub PR をコードレビューしてください。

対象は **この PR の diff だけ** です。ローカルの作業ツリー・カレントブランチ・他リポジトリは
レビュー対象ではありません。cwd に git リポジトリがあっても無視してください。

- Repo:   ${REPO}
- PR:     #${NUMBER}
- URL:    ${URL}
- Title:  ${PR_TITLE}
- Author: ${PR_AUTHOR}
- Branch: ${PR_HEAD} → ${PR_BASE}
- Diff:   +${PR_ADD} / -${PR_DEL} (${PR_FILES} files)
- CI:     ${CI_LINE}

追加の文脈が要る場合は gh を使ってこの PR / このリポジトリだけを参照してください
(例: gh pr view ${NUMBER} -R ${REPO}, gh api repos/${REPO}/contents/<path>?ref=${PR_HEAD})。

観点: 正しさ・退行・エラーハンドリング・既存実装との重複・i18n/アクセシビリティ・型の緩さ。
指摘には必ず該当ファイルと行番号を添えてください。行番号は下の annotated diff の各行頭に
付いている [LINE N] の N をそのまま使うこと (自分で数えない)。

--- ANNOTATED DIFF ---
${ANNOTATED_DIFF}"

  REVIEW_RESULT=$(claude --dangerously-skip-permissions -p "$REVIEW_PROMPT" 2>&1 || true)
  if [[ -z "${REVIEW_RESULT// }" ]]; then
    echo "⚠️  レビュー生成に失敗しました（claude が空応答）。[r] でやり直せます。"
    return 1
  fi

  # Step 2: 生レビュー + annotated diff を構造化 JSON に抽出 (verdict/summary/findings)。
  # findings の line は [LINE N] の番号をそのまま使わせる (自前計算させない = 実績ある手法)。
  local EXTRACT_PROMPT RAW
  EXTRACT_PROMPT="以下は PR #${NUMBER} (${REPO}) のコードレビュー結果と annotated diff です。
これを解析し、下記スキーマの JSON を1つだけ出力してください。JSON 以外の文字列・コードフェンス・前置き・後置きは一切出力しない。

スキーマ:
{
  \"verdict\": \"APPROVE | REQUEST_CHANGES | DISCUSS | SKIP のいずれか\",
  \"verdict_reason\": \"1行の理由\",
  \"summary\": [\"変更の要点を3項目以内\"],
  \"findings\": [
    {\"severity\": \"blocker | suggestion | note\", \"path\": \"変更ファイルのパス\", \"line\": 42, \"side\": \"RIGHT\", \"body\": \"指摘内容(日本語で簡潔に)\"}
  ]
}

ルール:
- 内容は元レビューにある事実だけを使う。勝手に増やさない。
- severity: merge をブロックすべき問題=blocker、推奨修正=suggestion、それ以外の気づき/praise/確認点=note。
- line: annotated diff の各行頭に付いている [LINE N] の N をそのまま使う (自分で計算しない)。該当行が特定できない指摘は line を null にする。
- path: [LINE N] が付いている該当ファイル (+++ b/... のパスから先頭の b/ を除いたもの)。
- side は常に \"RIGHT\"。
- 元レビューが「issues なし / No issues found」系なら verdict=APPROVE、findings=[]。
- 元レビューが「closed/draft でレビュー対象外」系なら verdict=SKIP、findings=[]。
- 指摘が無ければ findings=[]。

--- ANNOTATED DIFF ---
${ANNOTATED_DIFF}

--- REVIEW ---
${REVIEW_RESULT}"

  RAW=$(claude --dangerously-skip-permissions -p "$EXTRACT_PROMPT" 2>&1 || true)
  # コードフェンス等を剥がして最初の { ... } を取り出す
  FINDINGS_JSON=$(printf '%s\n' "$RAW" | sed -n '/^{/,/^}/p')
  if ! echo "$FINDINGS_JSON" | jq -e . >/dev/null 2>&1; then
    echo "⚠️  構造化抽出に失敗しました。生レビューをそのまま表示します。"
    echo ""
    echo "$REVIEW_RESULT"
    echo ""
    FINDINGS_JSON='{"findings":[]}'
    return 0
  fi

  render_review
  echo ""
}

# 初回レビュー生成（失敗してもメニューは出す。[r] でやり直せる）
run_review || true

# Step 2.5: CI が失敗しているなら自動で request-changes を送る。
# gh-review-watcher 経由でタブが開くたびに走るので、既に自分の CHANGES_REQUESTED が
# あれば再送しない (二重送信ガード)。
if [ "$CI_STATUS" = "FAIL" ]; then
  VIEWER=$(gh api user --jq '.login' 2>/dev/null || echo "")
  ALREADY=$(gh pr view "$NUMBER" -R "$REPO" --json reviews --jq \
    --arg u "$VIEWER" '[.reviews[]? | select(.author.login==$u and .state=="CHANGES_REQUESTED")] | length' 2>/dev/null || echo 0)
  if [ "${ALREADY:-0}" -gt 0 ]; then
    echo "🚦 CI 失敗中だが既に request-changes 済み。再送しません。"
  else
    FAIL_BULLETS=$(echo "$CI_FAILED" | tr ',' '\n' | sed 's/^ *//; s/^/- /')
    if gh pr review "$NUMBER" -R "$REPO" --request-changes --body "$(cat <<EOF
⛔ **CI が失敗しています。** マージ前に修正が必要です。

**失敗している check:**
${FAIL_BULLETS}

CI が green になったら再度レビューします。

🤖 Reviewed by Claude Code (gh-review-watcher)
EOF
)"; then
      echo "⛔ CI 失敗のため request-changes を自動送信しました。"
    else
      echo "⚠️  request-changes の送信に失敗しました (権限/自分のPR等)。"
    fi
  fi
fi

# 分析完了後、このレビュータブにフォーカスを移動 (タブ id で。名前で探してセッションも特定する)
if REVIEW_TAB=$(zj find-tab "Review: ${REPO}#${NUMBER}" 2>/dev/null); then
  zj -s "${REVIEW_TAB%%$'\t'*}" action go-to-tab-by-id "${REVIEW_TAB##*$'\t'}" >/dev/null 2>&1 || true
fi

# 選択肢を提示（メニューはループ）。API 失敗時は abort せずメニューに戻る:
#   - approve/comment が失敗したら「もう一度同じキー」で再実行できる（冪等な再送）。
#   - [r] はレビュー生成（claude /review + 構造化抽出 + 表示）を丸ごとやり直す。
# アクション実行中は set -e を止め、各 API 呼び出しの失敗を明示チェックして
# 「失敗→メニューへ戻す／成功→exit 0(=タブ close)」に振り分ける。
set +e
while true; do
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  [a] Approve this PR"
echo "  [c] Comment concerns as pending review (open in browser)"
echo "  [d] Discuss with Claude Code"
echo "  [o] Open in browser"
echo "  [r] Re-review (レビューをもう一度生成し直す)"
echo "  [q] Quit"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -r -p "Choose action: " choice

# [r] はレビュー生成（claude /review + 構造化抽出 + 表示）を丸ごとやり直す
if [ "$choice" = "r" ]; then
  echo "↻ レビューを再生成します..."
  run_review || true
  continue
fi

case "$choice" in
  a)
    if gh pr review "$NUMBER" -R "$REPO" --approve --body "LGTM 👍 (Reviewed by Claude Code)"; then
      echo "✅ Approved!"
      exit 0
    fi
    echo "❌ approve に失敗しました(API 等)。もう一度 [a] を押してください。"
    ;;
  c)
    # 表示に使った FINDINGS_JSON をそのまま inline comment 化する（表示＝投稿で行番号一致）。
    # blocker / suggestion のみ投稿（note は投稿しない）。line が無い指摘はスキップ。
    echo "🤖 findings から inline comment を作成します..."
    OWNER="${REPO%/*}"
    REPO_NAME="${REPO#*/}"
    COMMENT_JSON=$(echo "$FINDINGS_JSON" | jq -c '
      [.findings[]?
        | select(.severity=="blocker" or .severity=="suggestion")
        | select(.line != null and ((.path // "") != ""))
        | {path, line, side: (.side // "RIGHT"), body}]' 2>/dev/null || echo "[]")

    if [ -z "$COMMENT_JSON" ] || [ "$COMMENT_JSON" = "[]" ]; then
      echo "ℹ️  投稿対象の指摘（blocker/suggestion で行が特定できるもの）がありません。"
      continue
    fi

    # 投稿前に (path, line) が diff 上に実在するか ANNOTATED_DIFF で検証する。
    # GitHub は解決できない行が1件でもあるとリクエスト全体を 422 ("Line could not be
    # resolved") で落とすので、外れた指摘は落として残りだけ投稿する。
    VALID_JSON=$(printf '%s\n' "$ANNOTATED_DIFF" | awk '
      /^\+\+\+ / { f = substr($0, 7); next }
      /^\[LINE / { if (f != "") { n = $2; sub(/\]/, "", n); print f "\t" n } }
    ' | jq -R -s '
      split("\n") | map(select(length > 0) | split("\t") | {key: (.[0] + ":" + .[1]), value: true}) | from_entries')

    SPLIT_JSON=$(jq -n --argjson c "$COMMENT_JSON" --argjson v "$VALID_JSON" '
      def key: .path + ":" + (.line | tostring);
      { ok: [ $c[] | select($v[key] == true) | .line |= (tonumber? // .) ],
        ng: [ $c[] | select($v[key] != true) ] }' 2>/dev/null || echo '{"ok":[],"ng":[]}')

    NG_N=$(echo "$SPLIT_JSON" | jq '.ng | length')
    if [ "$NG_N" -gt 0 ]; then
      echo "⚠️  diff 上に解決できない行の指摘を ${NG_N} 件スキップしました:"
      echo "$SPLIT_JSON" | jq -r '.ng[] | "   - \(.path):\(.line)  \(.body | .[0:60])"'
    fi

    COMMENT_JSON=$(echo "$SPLIT_JSON" | jq -c '.ok')
    if [ "$COMMENT_JSON" = "[]" ]; then
      echo "ℹ️  投稿できる指摘が残りませんでした（行番号が diff と一致していません）。"
      continue
    fi

    COMMIT_ID=$(gh pr view "$NUMBER" -R "$REPO" --json headRefOid -q '.headRefOid') || { echo "❌ commit-id 取得に失敗(API)。もう一度 [c] を押してください。"; continue; }

    echo "$COMMENT_JSON" | jq .

    # pending review を作成（event を指定しないと pending になる）
    PAYLOAD=$(jq -n --arg commit "$COMMIT_ID" --argjson comments "$COMMENT_JSON" \
      '{commit_id: $commit, comments: $comments}')

    # 失敗時は API の応答本文をそのまま出す (422 の原因はほぼ本文の errors[] にしか書かれていない)。
    # set -e 下なので rc は || で受ける (素の代入だと失敗時にスクリプトごと落ちる)。
    API_RC=0
    API_OUT=$(echo "$PAYLOAD" | gh api "repos/${OWNER}/${REPO_NAME}/pulls/${NUMBER}/reviews" \
      --method POST --input - 2>&1) || API_RC=$?
    if [ "$API_RC" -ne 0 ]; then
      echo "❌ コメント投稿に失敗しました。API 応答:"
      echo "$API_OUT" | head -40
      echo "--- 送信した payload ---"
      echo "$PAYLOAD" | jq . | head -60
      echo "もう一度 [c] を押せば再送できます。"
      continue
    fi

    echo "✅ Pending review created. Opening browser..."
    open "${URL}/files"
    exit 0
    ;;
  d)
    exec claude --dangerously-skip-permissions \
      "PR #${NUMBER} (${REPO}) について議論しましょう。URL: ${URL}

以下はClaude Codeによる事前レビュー結果です:

${REVIEW_RESULT}"
    ;;
  o)
    open "$URL"
    ;;
  q)
    exit 0
    ;;
  *)
    echo "不明な選択: '$choice'"
    ;;
esac
done
