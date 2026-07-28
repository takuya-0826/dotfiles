#!/usr/bin/env bash
set -euo pipefail

export PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/Users/takuyamatsumoto

LOG_FILE="/tmp/daily-report.log"
REPORT_DATE=$(date +%Y-%m-%d)
DAY_OF_WEEK=$(date +%a)

echo "$(date): Starting daily report generation for $REPORT_DATE ($DAY_OF_WEEK)" >> "$LOG_FILE"

# Auto-discover all git repos under ~/Projects (up to 3 levels deep) + ~/dotfiles
PROJECTS=()
while IFS= read -r d; do
  PROJECTS+=("${d%/.git}")
done < <(find "$HOME/Projects" -maxdepth 3 -name .git -type d 2>/dev/null | sort)
[ -d "$HOME/dotfiles/.git" ] && PROJECTS+=("$HOME/dotfiles")

# Collect git log from each repository
GIT_SUMMARY=""
for dir in "${PROJECTS[@]}"; do
  PROJECT_NAME=$(echo "$dir" | sed "s|$HOME/Projects/||; s|$HOME/||")
  LOGS=$(cd "$dir" && git log --all \
    --since="$REPORT_DATE 00:00" \
    --until="$(date -v+1d +%Y-%m-%d) 00:00" \
    --author="takuya-0826" --author="takuya.matsumoto@atrae.co.jp" \
    --pretty=format:"- %h %s (%ar)" \
    2>/dev/null || true)
  if [ -n "$LOGS" ]; then
    GIT_SUMMARY+="### $PROJECT_NAME
$LOGS

"
  fi
done

if [ -z "$GIT_SUMMARY" ]; then
  GIT_SUMMARY="活動なし"
fi

# Collect Claude Code session logs for the target date
CLAUDE_PROJECTS_DIR="$HOME/.claude/projects"
SESSION_SUMMARY=""
if [ -d "$CLAUDE_PROJECTS_DIR" ]; then
  for proj_dir in "$CLAUDE_PROJECTS_DIR"/-Users-takuyamatsumoto-*; do
    [ -d "$proj_dir" ] || continue
    PROJ_SLUG=$(basename "$proj_dir" | sed 's/^-Users-takuyamatsumoto-//; s/-/\//g')

    # Find session files modified today
    PROJ_SESSIONS=""
    while IFS= read -r session_file; do
      [ -f "$session_file" ] || continue
      # Extract user and assistant text messages from the target date
      MSGS=$(jq -r '
        select(.type == "user" or .type == "assistant") |
        select(.timestamp >= "'"$REPORT_DATE"'") |
        select(.timestamp < "'"$(date -v+1d +%Y-%m-%d)"'") |
        .type as $t |
        .message.content[]? | select(.type == "text") | select(.text | length > 15) |
        ($t | ascii_upcase) + ": " + (.text | gsub("\n"; " ") | .[0:300])
      ' "$session_file" 2>/dev/null || true)
      if [ -n "$MSGS" ]; then
        PROJ_SESSIONS+="$MSGS
"
      fi
    done < <(find "$proj_dir" -name "*.jsonl" -maxdepth 1 -newer /dev/null -mtime -1 2>/dev/null)

    if [ -n "$PROJ_SESSIONS" ]; then
      SESSION_SUMMARY+="### $PROJ_SLUG
$PROJ_SESSIONS

"
    fi
  done
fi

if [ -z "$SESSION_SUMMARY" ]; then
  SESSION_SUMMARY="セッションログなし"
fi

echo "$(date): Git data and session logs collected, sending to Claude..." >> "$LOG_FILE"

# Send prompt to Claude -p for formatting and Notion posting
command claude -p --dangerously-skip-permissions "$(cat <<PROMPT
あなたは日報自動生成アシスタントです。以下のGitデータ、Claude Codeセッションログ、タスク情報をもとに、Notionに詳細な日報を作成または更新してください。

## 日付: $REPORT_DATE ($DAY_OF_WEEK)

## Git活動データ
$GIT_SUMMARY

## Claude Codeセッションログ（作業の詳細コンテキスト）
$SESSION_SUMMARY

## 手順
1. Google Tasksからタスク進捗を取得してください（gws tasks tasks list --params '{"tasklist": "MTAzMTUxMjk3ODI0NjM4OTc0NjU6MDow"}' コマンドを使用）
2. Notion MCPの notion-search で「日報 - $REPORT_DATE」を検索してください
3. 既存ページがあれば notion-update-page の replace_content で内容を更新、なければ notion-create-pages で新規作成してください:
   - 日報DBの data_source_id: 64bb8b84-6d5b-431c-831f-1069f737f1b3
   - タイトル: 「日報 - $REPORT_DATE ($DAY_OF_WEEK)」
   - 内容（セッションログから各PRの背景・原因分析・修正内容まで詳細に記載すること）:
     ## 📝 本日の活動
     （プロジェクト別に整理。各PRの背景・問題分析・解決策を含む詳細な記述）
     ## ✅ タスク状況
     （Google Tasksから取得した進行中・完了タスク）
     ## 🤖 Claude Codeとしての学び
     （セッションログから得た技術的な学び・気づき: 新たに理解したこと、うまくいったアプローチ、改善すべき点、次回に活かせるパターン）
     ## 💡 メモ
     （特記事項・振り返り）
4. 作成/更新したページのURLを出力してください
PROMPT
)" >> "$LOG_FILE" 2>&1

echo "$(date): Daily report generation complete." >> "$LOG_FILE"
