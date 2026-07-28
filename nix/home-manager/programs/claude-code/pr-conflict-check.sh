#!/usr/bin/env bash
set -euo pipefail

export PATH=$HOME/.local/share/mise/shims:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/Users/takuyamatsumoto

LOG_FILE="/tmp/pr-conflict-check.log"
DRY_RUN="${PR_CONFLICT_DRY_RUN:-0}"
TARGET_PR="${1:-}"
FORCE="${PR_CONFLICT_FORCE:-0}"

log() {
  echo "$(date '+%Y-%m-%dT%H:%M:%S') $*" >> "$LOG_FILE"
}

# 今日もう実行済みなら早期 exit (RunAtLoad で毎ログイン走らせるための idempotency)。
# TARGET 指定 / DRY_RUN / FORCE では強制実行する。
LAST_RUN_FILE="$HOME/.cache/pr-conflict-check/last-run-date"
TODAY=$(date '+%Y-%m-%d')
if [ -z "$TARGET_PR" ] && [ "$DRY_RUN" != "1" ] && [ "$FORCE" != "1" ]; then
  if [ -f "$LAST_RUN_FILE" ] && [ "$(cat "$LAST_RUN_FILE" 2>/dev/null)" = "$TODAY" ]; then
    log "=== Skipped (already ran today: $TODAY). Set PR_CONFLICT_FORCE=1 to override ==="
    exit 0
  fi
  mkdir -p "$(dirname "$LAST_RUN_FILE")"
  echo "$TODAY" > "$LAST_RUN_FILE"
fi

log "=== Starting pr-conflict-check (dry_run=$DRY_RUN, target=${TARGET_PR:-<all>}) ==="

# 古い shallow clone を掃除 (14日以上アクセスのないもの)
# /tmp/pr-conflict-check/<owner>-<repo>/ が対象。prompts/ は除外
SHALLOW_ROOT="/tmp/pr-conflict-check"
if [ -d "$SHALLOW_ROOT" ]; then
  while IFS= read -r dir; do
    [ -z "$dir" ] && continue
    log "removing stale shallow clone: $dir"
    rm -rf "$dir"
  done < <(find "$SHALLOW_ROOT" -mindepth 1 -maxdepth 1 -type d -not -name prompts -atime +14 2>/dev/null)
fi

# 過去に使った main_repo の pr-conflict/ 配下の worktree のうち、
# 1日以上アクセスのないものを prune する。前回 resolve が異常終了して
# worktree が残るとブランチが束縛されて自動化が連続失敗するので、それを防ぐ。
# (worktree 自体は detached HEAD で作るが、古い -B 形式の残骸対策も兼ねる)
KNOWN_REPOS_FILE="$HOME/.cache/pr-conflict-check/known-repos.txt"
if [ -f "$KNOWN_REPOS_FILE" ]; then
  while IFS= read -r main_repo; do
    [ -z "$main_repo" ] && continue
    [ -d "$main_repo/.git" ] || [ -f "$main_repo/.git" ] || continue
    pr_conflict_root="$main_repo/.claude/worktrees/pr-conflict"
    [ -d "$pr_conflict_root" ] || continue
    while IFS= read -r wt; do
      [ -z "$wt" ] && continue
      log "removing stale pr-conflict worktree: $wt"
      git -C "$main_repo" worktree remove --force "$wt" >> "$LOG_FILE" 2>&1 || rm -rf "$wt"
    done < <(find "$pr_conflict_root" -mindepth 1 -maxdepth 1 -type d -atime +1 2>/dev/null)
    git -C "$main_repo" worktree prune >> "$LOG_FILE" 2>&1 || true
  done < "$KNOWN_REPOS_FILE"
fi

# 自分のopen PR (非draft) を取得
PRS_JSON=$(gh search prs --author=@me --state=open --draft=false \
  --json url,repository,number,title \
  --limit 50 2>>"$LOG_FILE") || {
  log "ERROR: gh search prs failed"
  exit 1
}

# 単発指定があれば filter
if [ -n "$TARGET_PR" ]; then
  PRS_JSON=$(echo "$PRS_JSON" | jq -c --arg t "$TARGET_PR" \
    '[.[] | select((.repository.nameWithOwner + "#" + (.number|tostring)) == $t)]')
fi

PR_COUNT=$(echo "$PRS_JSON" | jq 'length')
log "Found $PR_COUNT open PR(s) authored by @me"

N_OK=0
N_AUTO=0
N_HUMAN=0
N_ERR=0
SUMMARY=""

# PR JSON を mapfile で配列に展開してから for で iterate する。
# 旧実装は `while ... done < <(jq -c '.[]')` の process substitution だったが、
# ループ内で起動する子プロセス (特に `claude -p`) が親の stdin (= FIFO) を
# 継承して EOF を引き起こし、ループが途中で打ち切られる事故が発生していた。
mapfile -t PR_LINES < <(echo "$PRS_JSON" | jq -c '.[]')

for pr in "${PR_LINES[@]}"; do
  [ -z "$pr" ] && continue
  REPO=$(echo "$pr" | jq -r '.repository.nameWithOwner')
  NUM=$(echo "$pr" | jq -r '.number')
  URL=$(echo "$pr" | jq -r '.url')
  TITLE=$(echo "$pr" | jq -r '.title')

  # mergeable / mergeStateStatus は gh search では取れないので gh pr view で取得。
  # GitHub の mergeable は lazy 計算で、最初のリクエストは UNKNOWN を返すことが多い。
  # 巨大 PR では計算に時間がかかるため、UNKNOWN なら 5秒 sleep して最大6回 retry する。
  MERGEABLE="UNKNOWN"
  STATE="UNKNOWN"
  BRANCH=""
  BASE=""
  GH_FAILED=0
  for attempt in 1 2 3 4 5 6; do
    PR_DETAIL=$(gh pr view "$NUM" -R "$REPO" \
      --json headRefName,mergeable,mergeStateStatus,baseRefName 2>>"$LOG_FILE") || {
      GH_FAILED=1
      break
    }
    BRANCH=$(echo "$PR_DETAIL" | jq -r '.headRefName')
    BASE=$(echo "$PR_DETAIL" | jq -r '.baseRefName')
    MERGEABLE=$(echo "$PR_DETAIL" | jq -r '.mergeable')
    STATE=$(echo "$PR_DETAIL" | jq -r '.mergeStateStatus')
    [ "$MERGEABLE" != "UNKNOWN" ] && break
    log "[$REPO#$NUM] mergeable=UNKNOWN (attempt $attempt/6), waiting 5s"
    sleep 5
  done

  if [ "$GH_FAILED" = "1" ]; then
    log "[$REPO#$NUM] ERROR: gh pr view failed"
    N_ERR=$((N_ERR+1))
    SUMMARY+="✗ $REPO#$NUM (gh pr view failed)\n"
    continue
  fi

  log "[$REPO#$NUM] mergeable=$MERGEABLE state=$STATE branch=$BRANCH base=$BASE"

  # ケースA0: 30秒待っても UNKNOWN のまま。判定不能 → エラーとして通知し、clean とは絶対表示しない
  if [ "$MERGEABLE" = "UNKNOWN" ]; then
    log "  → ERROR: mergeable still UNKNOWN after retries"
    N_ERR=$((N_ERR+1))
    SUMMARY+="✗ $REPO#$NUM (mergeable UNKNOWN - GitHub still computing)\n"
    continue
  fi

  # ケースA: コンフリクトなし
  if [ "$MERGEABLE" != "CONFLICTING" ] && [ "$STATE" != "DIRTY" ]; then
    log "  → SKIP (clean)"
    N_OK=$((N_OK+1))
    SUMMARY+="✓ $REPO#$NUM (clean)\n"
    continue
  fi

  # dry-run: 検出のみ
  if [ "$DRY_RUN" = "1" ]; then
    log "  → [dry-run] would invoke pr-conflict-resolve"
    SUMMARY+="? $REPO#$NUM (dry-run, conflict)\n"
    continue
  fi

  # サブスクリプトに委譲。stdout の最終行が結果コード。
  # stdin は明示的に /dev/null へ切る (claude 等が親の stdin を吸わないように)。
  log "  → invoking pr-conflict-resolve"
  RESOLVE_OUT=$(/Users/takuyamatsumoto/.local/bin/pr-conflict-resolve \
    --repo "$REPO" --number "$NUM" --url "$URL" \
    --branch "$BRANCH" --base "$BASE" --title "$TITLE" \
    < /dev/null 2>>"$LOG_FILE") || true

  RESULT=$(echo "$RESOLVE_OUT" | tail -1)

  case "$RESULT" in
    AUTO_FIXED)
      N_AUTO=$((N_AUTO+1))
      SUMMARY+="✓ $REPO#$NUM (auto-fixed)\n"
      ;;
    HUMAN_NEEDED)
      N_HUMAN=$((N_HUMAN+1))
      SUMMARY+="! $REPO#$NUM (zellij tab opened)\n"
      ;;
    SKIPPED_CACHED)
      # 直近 24h で can_auto=false 判定済み & HEAD 不変。再処理せずスキップ
      N_OK=$((N_OK+1))
      SUMMARY+="- $REPO#$NUM (skipped: cached judge)\n"
      ;;
    *)
      N_ERR=$((N_ERR+1))
      SUMMARY+="✗ $REPO#$NUM (error: $RESULT)\n"
      ;;
  esac
done

log "Summary: ok=$N_OK auto=$N_AUTO human=$N_HUMAN err=$N_ERR"
log "Details:
$(echo -e "$SUMMARY")"

# macOS 通知 (1回だけ)
NOTIFIER=/Applications/Utilities/Notifier.app/Contents/MacOS/Notifier
if [ "$DRY_RUN" != "1" ] && [ -x "$NOTIFIER" ]; then
  TOTAL=$((N_OK + N_AUTO + N_HUMAN + N_ERR))
  if [ "$N_HUMAN" -gt 0 ] || [ "$N_ERR" -gt 0 ]; then
    SUBTITLE="$N_HUMAN need review / $N_ERR error / $N_AUTO auto / $N_OK clean"
  else
    SUBTITLE="$TOTAL PR(s) all clean ($N_AUTO auto-fixed)"
  fi
  "$NOTIFIER" \
    --type banner --title "PR Conflict Check" \
    --subtitle "$SUBTITLE" \
    --message "$(echo -e "$SUMMARY" | head -10)" \
    >> "$LOG_FILE" 2>&1 || true
fi

log "=== Done ==="
