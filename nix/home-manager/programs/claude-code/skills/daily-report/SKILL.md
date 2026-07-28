---
name: daily-report
version: 1.2.0
description: "Generate or update a detailed daily report from Git activity, Claude Code session logs, and Google Tasks, then post to Notion."
---

# daily-report

Generate or update a detailed daily report and post it to Notion. Uses Git activity, Claude Code session logs, and Google Tasks. Can be triggered manually via `/daily-report` or runs automatically at AM 3:00 via launchd.

## Arguments

- Optional: date in `YYYY-MM-DD` format (defaults to today)

## Behavior

### Step 1: Collect Git activity

Auto-discover all git repos under `~/Projects` (up to 3 levels deep) and `~/dotfiles`:

```bash
REPORT_DATE="${1:-$(date +%Y-%m-%d)}"
DAY_OF_WEEK=$(date -j -f %Y-%m-%d "$REPORT_DATE" +%a 2>/dev/null || date -d "$REPORT_DATE" +%a)
NEXT_DATE=$(date -j -v+1d -f %Y-%m-%d "$REPORT_DATE" +%Y-%m-%d 2>/dev/null || date -d "$REPORT_DATE + 1 day" +%Y-%m-%d)

PROJECTS=()
while IFS= read -r d; do
  PROJECTS+=("${d%/.git}")
done < <(find "$HOME/Projects" -maxdepth 3 -name .git -type d 2>/dev/null | sort)
[ -d "$HOME/dotfiles/.git" ] && PROJECTS+=("$HOME/dotfiles")

for dir in "${PROJECTS[@]}"; do
  PROJECT_NAME=$(echo "$dir" | sed "s|$HOME/Projects/||; s|$HOME/||")
  LOGS=$(cd "$dir" && git log --all \
    --since="$REPORT_DATE 00:00" \
    --until="$NEXT_DATE 00:00" \
    --author="takuya-0826" --author="takuya.matsumoto@atrae.co.jp" \
    --pretty=format:"- %h %s (%ar)" \
    2>/dev/null || true)
  if [ -n "$LOGS" ]; then
    echo "### $PROJECT_NAME"
    echo "$LOGS"
    echo ""
  fi
done
```

### Step 2: Collect Claude Code session logs

Extract user/assistant text messages from `~/.claude/projects/` session files modified on the target date. This provides detailed context about what was worked on, why, and how problems were solved.

```bash
CLAUDE_PROJECTS_DIR="$HOME/.claude/projects"
for proj_dir in "$CLAUDE_PROJECTS_DIR"/-Users-takuyamatsumoto-*; do
  [ -d "$proj_dir" ] || continue
  PROJ_SLUG=$(basename "$proj_dir" | sed 's/^-Users-takuyamatsumoto-//; s/-/\//g')

  for session_file in $(find "$proj_dir" -name "*.jsonl" -maxdepth 1 -mtime -1 2>/dev/null); do
    jq -r '
      select(.type == "user" or .type == "assistant") |
      select(.timestamp >= "REPORT_DATE") |
      select(.timestamp < "NEXT_DATE") |
      .type as $t |
      .message.content[]? | select(.type == "text") | select(.text | length > 15) |
      ($t | ascii_upcase) + ": " + (.text | gsub("\n"; " ") | .[0:300])
    ' "$session_file" 2>/dev/null
  done
done
```

### Step 3: Get Google Tasks

Run `gws tasks tasks list --params '{"tasklist": "MTAzMTUxMjk3ODI0NjM4OTc0NjU6MDow"}'`

### Step 4: Check existing report

Use `notion-search` MCP tool to search for "日報 - YYYY-MM-DD" in the 日報 database (data_source: `collection://64bb8b84-6d5b-431c-831f-1069f737f1b3`).

### Step 5: Create or update Notion page

- **If a page for that date already exists**: Use `notion-update-page` with `replace_content` to update the content.
- **If no page exists**: Use `notion-create-pages` with parent `data_source_id: 64bb8b84-6d5b-431c-831f-1069f737f1b3`.

Format:
- Title: `日報 - YYYY-MM-DD (DAY)`
- Properties: `日付` = YYYY-MM-DD, `ステータス` = 完了
- Content:

```markdown
## 📝 本日の活動

### プロジェクト名（コミット数 / セッション数）

**PR・機能名**
- 背景・問題の説明
- 原因分析（バグ修正の場合）
- 解決策・実装内容
- 具体的な変更点

（プロジェクトごとに繰り返し）

## ✅ タスク状況
（Google Tasks progress）

## 🤖 Claude Codeとしての学び
（セッションログから得た技術的な学び・気づきを記載）
- 今日の作業で新たに理解したこと（ライブラリ・アーキテクチャ・ドメイン知識など）
- うまくいったアプローチ・判断
- 改善すべきだった点（遠回りした調査、誤った初期仮説など）
- 次回以降に活かせるパターンやテクニック

## 💡 メモ
（振り返り・特記事項）
```

### Writing guidelines

- セッションログからPRの背景・問題分析・解決策を読み取り、詳細に記述する
- バグ修正の場合は根本原因まで記載する（例: 「原因: drawCardの__done__ガードがデッキ空の場合を考慮していなかった」）
- 新機能の場合は設計判断や技術的な選択も含める
- Copilotレビュー対応など、コードレビューの内容も記載する
- 単なるコミットリストではなく、ストーリーとして読める日報にする
- 「Claude Codeとしての学び」セクションでは、セッションログを振り返り、技術的発見・うまくいった判断・反省点を率直に書く。例: 「mapfileがzshで使えないことに気づかず失敗した→bashとzshの互換性を意識すべき」「デッドロックの原因特定にadvanceTurnのフロー全体を追った結果、ガード条件の漏れを発見できた」

## Notes

- The same logic runs automatically at AM 3:00 via `~/.local/bin/daily-report` (launchd agent)
- Logs are written to `/tmp/daily-report.log`
- If no git activity is found, report "活動なし" in the activity section
- Notion 日報 DB data_source_id: `64bb8b84-6d5b-431c-831f-1069f737f1b3`
- Session log files are at `~/.claude/projects/-Users-takuyamatsumoto-{ProjectPath}/*.jsonl`
