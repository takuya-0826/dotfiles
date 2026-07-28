#!/usr/bin/env bash
set -euo pipefail

export PATH=$HOME/.local/share/mise/shims:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/Users/takuyamatsumoto

LOG_FILE="/tmp/pr-conflict-check.log"
JUDGE_TIMEOUT="${PR_JUDGE_TIMEOUT_SECS:-300}"     # 5min
RESOLVE_TIMEOUT="${PR_RESOLVE_TIMEOUT_SECS:-900}" # 15min
CACHE_DIR="$HOME/.cache/pr-conflict-check"
CACHE_FILE="$CACHE_DIR/judge.jsonl"
CACHE_TTL_SECS=86400  # 24h

log() {
  echo "$(date '+%Y-%m-%dT%H:%M:%S') [resolve] $*" >> "$LOG_FILE"
}

# coreutils の `timeout` を優先 (nix 経由で入れている)。無ければ素のまま実行。
run_with_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout --kill-after=10s "${secs}s" "$@"
  else
    "$@"
  fi
}

# 直近 24h 内の同じ commit に対する judge 結果が記録されていれば返す。
# キー: <repo>#<num>@<commit>
# 値 (jsonl 1行): {"key":"...","ts":<unix>,"can":"...","conf":"...","reason":"..."}
judge_cache_lookup() {
  local key="$1"
  [ -f "$CACHE_FILE" ] || return 1
  local now
  now=$(date +%s)
  # 末尾から逆順に読む。キーが一致した最初の行を採用
  local line
  line=$(tac "$CACHE_FILE" 2>/dev/null | jq -c --arg k "$key" 'select(.key==$k)' 2>/dev/null | head -1)
  [ -z "$line" ] && return 1
  local ts
  ts=$(echo "$line" | jq -r '.ts')
  if [ "$((now - ts))" -gt "$CACHE_TTL_SECS" ]; then
    return 1
  fi
  echo "$line"
  return 0
}

judge_cache_record() {
  local key="$1" can="$2" conf="$3" reason="$4"
  mkdir -p "$CACHE_DIR"
  jq -nc \
    --arg k "$key" --arg can "$can" --arg conf "$conf" --arg r "$reason" \
    --argjson ts "$(date +%s)" \
    '{key:$k, ts:$ts, can:$can, conf:$conf, reason:$r}' \
    >> "$CACHE_FILE"
}

# ---- 引数パース ----
REPO=""
NUM=""
URL=""
BRANCH=""
BASE=""
TITLE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --number) NUM="$2"; shift 2 ;;
    --url) URL="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$REPO" ] || [ -z "$NUM" ] || [ -z "$BRANCH" ]; then
  log "ERROR: missing required args"
  echo "ERROR_BAD_ARGS"
  exit 1
fi

log "[$REPO#$NUM] start (branch=$BRANCH base=$BASE)"

# ---- 関数定義 ----

find_local_clone() {
  local repo="$1"
  local owner="${repo%/*}"
  local name="${repo#*/}"

  # ~/dotfiles 直接マッチ
  if [ "$repo" = "EdV4H/dotfiles" ] && [ -d "$HOME/dotfiles/.git" ]; then
    echo "$HOME/dotfiles"
    return 0
  fi

  # ~/Projects/<name> または ~/Projects/<owner>/<name>
  for candidate in "$HOME/Projects/$name" "$HOME/Projects/$owner/$name"; do
    if [ -d "$candidate/.git" ]; then
      local url
      url=$(git -C "$candidate" remote get-url origin 2>/dev/null || echo "")
      if echo "$url" | grep -qE "[:/]$repo(\.git)?$"; then
        echo "$candidate"
        return 0
      fi
    fi
  done

  # find で深掘り
  local found
  found=$(find "$HOME/Projects" -maxdepth 3 -name .git -type d 2>/dev/null | while read -r gitdir; do
    local dir="${gitdir%/.git}"
    local url
    url=$(git -C "$dir" remote get-url origin 2>/dev/null || echo "")
    if echo "$url" | grep -qE "[:/]$repo(\.git)?$"; then
      echo "$dir"
      break
    fi
  done | head -1)

  if [ -n "$found" ]; then
    echo "$found"
    return 0
  fi

  return 1
}

shallow_clone() {
  local repo="$1"
  local clone_root="/tmp/pr-conflict-check"
  local target="$clone_root/${repo//\//-}"

  mkdir -p "$clone_root"

  # clone の健全性を `git rev-parse` で確認 (.git ディレクトリが空殻 / 壊れている場合は再 clone)
  if [ -d "$target/.git" ] && ! git -C "$target" rev-parse --git-dir >/dev/null 2>&1; then
    log "existing clone is broken, removing: $target"
    rm -rf "$target"
  fi

  if [ ! -d "$target/.git" ]; then
    log "shallow cloning $repo to $target"
    # --no-single-branch で全ブランチを取る (PR ブランチも含むため)
    if ! gh repo clone "$repo" "$target" -- --depth 50 --no-single-branch >> "$LOG_FILE" 2>&1; then
      log "ERROR: shallow clone failed for $repo"
      rm -rf "$target" 2>/dev/null
      return 1
    fi
  fi
  echo "$target"
}

# zellij を起動する wrapper。TMPDIR が claude-code の独自値 (例: /tmp/claude-501) を
# 指している場合、zellij はそこに socket を探しに行って "There is no active session!" で
# 失敗する。zellij のサーバが置く socket は default の TMPDIR 配下なので、明示的に剥がす。
zj() {
  env -u TMPDIR zellij "$@"
}

# アクティブな zellij セッション名を取得
# 優先順: (current) のセッション → 最も最近作成されたセッション
zellij_session() {
  local sessions
  sessions=$(zj list-sessions --no-formatting 2>/dev/null | grep -v EXITED || true)
  if [ -z "$sessions" ]; then
    return 1
  fi
  # (current) があればそれを優先
  local current_session
  current_session=$(echo "$sessions" | grep '(current)' | awk '{print $1}' | head -1)
  if [ -n "$current_session" ]; then
    echo "$current_session"
    return 0
  fi
  # なければ list の最初 (zellij は新しい順で出すとは限らないが、launchd 起動時は1つしかないことが多い)
  echo "$sessions" | head -1 | awk '{print $1}'
}

# zellij タブを開いて Claude セッションを起動 (人間委譲用)
# usage: open_human_tab <work_dir> <handoff_reason>
open_human_tab() {
  local work_dir="$1"
  local handoff_reason="$2"
  local TAB="Conflict: $REPO#$NUM"

  local session
  if ! session=$(zellij_session); then
    log "  ERROR: no active zellij session, cannot open tab"
    log "  human handoff details: work_dir=$work_dir reason=$handoff_reason"
    return
  fi
  log "  using zellij session: $session"

  local handoff_prompt
  handoff_prompt=$(cat <<EOF
PR #$NUM ($REPO) のコンフリクトを自動解決できませんでした。

URL: $URL
タイトル: $TITLE
作業ディレクトリ: $work_dir
ブランチ: $BRANCH
ベース: $BASE

自動判定の結果:
$handoff_reason

現在の状態:
- $work_dir に checkout 済み (worktree)
- rebase は abort 済み

あなた (Claude Code) のサポート方針:
1. コンフリクトの全体像を1分で要約 (どのファイル / 双方の変更の意図 / 推奨方針)
2. ユーザーが OK したら \`git rebase origin/$BASE\` をやり直して conflict 解決
3. 解決後 \`git rebase --continue\` → \`git push --force-with-lease\` まで実行
4. 完了したらメインリポジトリで \`git worktree remove $work_dir\` を実行して掃除
5. このタブを閉じるときは \`close-conflict-tab $REPO $NUM\` を実行する (絶対に \`zellij action close-tab\` を直接呼ばない: フォーカスのタブを巻き込んで閉じる事故が起きる)
EOF
)

  # 既存タブがあれば focus のみ
  local existing
  existing=$(zj --session "$session" action query-tab-names 2>/dev/null | grep -Fx "$TAB" || true)
  if [ -n "$existing" ]; then
    log "  zellij tab '$TAB' already exists, focusing"
    zj --session "$session" action go-to-tab-name "$TAB" 2>>"$LOG_FILE" || true
    return
  fi

  # prompt は長くなりがちなので一時ファイルに書き出して、zellij には短いコマンドだけ送る
  # (write-chars に長文を流すと途中で切れる/欠落することがある)
  local prompt_dir="/tmp/pr-conflict-check/prompts"
  mkdir -p "$prompt_dir"
  local prompt_file="$prompt_dir/${REPO//\//-}-${NUM}.prompt"
  printf '%s\n' "$handoff_prompt" > "$prompt_file"
  log "  prompt written to: $prompt_file"

  # 新規タブ作成して claude 起動
  log "  opening new zellij tab: $TAB"
  zj --session "$session" action new-tab --name "$TAB" --layout default 2>>"$LOG_FILE" || true
  # ccd = `command claude --dangerously-skip-permissions` (zsh alias, wrapper を bypass)
  zj --session "$session" action write-chars "cd $(printf '%q' "$work_dir") && ccd \"\$(cat $(printf '%q' "$prompt_file"))\"" 2>>"$LOG_FILE" || true
  # Enter (0x0d)
  zj --session "$session" action write 13 2>>"$LOG_FILE" || true
}

# ---- ローカル準備 ----
# main repo を見つけて、そこから worktree を作って作業する
# (main repo が dirty でも干渉しない / 複数PRを並行処理しても衝突しない)

MAIN_REPO=""
if MAIN_REPO=$(find_local_clone "$REPO"); then
  log "found local clone: $MAIN_REPO"
else
  if ! MAIN_REPO=$(shallow_clone "$REPO") || [ -z "$MAIN_REPO" ]; then
    log "ERROR: failed to obtain a working clone for $REPO"
    echo "ERROR_CLONE_FAILED"
    exit 0
  fi
  log "using shallow clone: $MAIN_REPO"
fi

# 使った main_repo を記録 (起動時の prune で対象を見つけるため)
mkdir -p "$CACHE_DIR"
KNOWN_REPOS_FILE="$CACHE_DIR/known-repos.txt"
if ! grep -Fxq "$MAIN_REPO" "$KNOWN_REPOS_FILE" 2>/dev/null; then
  echo "$MAIN_REPO" >> "$KNOWN_REPOS_FILE"
fi

# worktree のパス: <main_repo>/.claude/worktrees/pr-conflict/<branch_safe>
BRANCH_SAFE="${BRANCH//\//-}"
WORK="$MAIN_REPO/.claude/worktrees/pr-conflict/$BRANCH_SAFE"

# 既存 worktree があれば一旦削除 (前回の中途半端な状態をクリア)
if [ -d "$WORK" ]; then
  log "removing stale worktree: $WORK"
  git -C "$MAIN_REPO" worktree remove --force "$WORK" >> "$LOG_FILE" 2>&1 || true
  rm -rf "$WORK" 2>/dev/null || true
fi

# fetch は main repo で行う (worktree は object を共有)
# PR branch と base branch を明示的に fetch (shallow clone で single-branch だった場合の保険)
git -C "$MAIN_REPO" fetch origin "$BRANCH":"refs/remotes/origin/$BRANCH" "$BASE":"refs/remotes/origin/$BASE" --quiet 2>>"$LOG_FILE" || {
  # fallback: 全fetchを試す (古い設定のリモートがある場合)
  git -C "$MAIN_REPO" fetch origin --quiet 2>>"$LOG_FILE" || {
    log "ERROR: fetch failed in $MAIN_REPO"
    echo "ERROR_FETCH_FAILED"
    exit 0
  }
}

# worktree を作る (detached HEAD で origin/<branch> から)
# -B でローカルブランチを束縛すると、別の worktree が同じブランチを掴んでいるときに必ず失敗する。
# 自動化は読み書きしかしないので branch を束縛する必要はなく、push 時に
# `HEAD:refs/heads/<branch>` で送り、--force-with-lease=<ref>:<expect> で安全性を担保する。
log "creating worktree (detached): $WORK -> origin/$BRANCH"
mkdir -p "$(dirname "$WORK")"
if ! git -C "$MAIN_REPO" worktree add --detach "$WORK" "origin/$BRANCH" >> "$LOG_FILE" 2>&1; then
  log "ERROR: worktree add failed"
  echo "ERROR_WORKTREE_FAILED"
  exit 0
fi

cd "$WORK"

# push 時に --force-with-lease で「remote が今我々が分岐した OID と同じこと」を要求する。
# 別誰かが間に push していた場合は、自動 push が reject されて壊さない。
EXPECTED_REMOTE_OID=$(git -C "$MAIN_REPO" rev-parse "origin/$BRANCH" 2>/dev/null || echo "")

cleanup() {
  cd "$MAIN_REPO" 2>/dev/null || return
  git worktree remove --force "$WORK" >> "$LOG_FILE" 2>&1 || true
  rm -rf "$WORK" 2>/dev/null || true
}

# detached HEAD から PR ブランチへ push する。
# 別の worktree がブランチを掴んでいても影響なし (我々はローカルブランチを更新しない)。
#
# --no-verify: 自動化は rebase で再書き起こしただけでコミット内容は変えていないので、
# 親 repo の pre-push hook (biome/turbo 等) が要求する node_modules を持たない
# worktree で hook を走らせると not found で必ず失敗する。 内容を変えていない以上
# hook が止めるべき品質問題は混入しないので skip する。
do_push() {
  local ref="refs/heads/$BRANCH"
  local lease_arg
  if [ -n "$EXPECTED_REMOTE_OID" ]; then
    lease_arg="--force-with-lease=$ref:$EXPECTED_REMOTE_OID"
  else
    lease_arg="--force-with-lease"
  fi
  git push --no-verify "$lease_arg" origin "HEAD:$ref"
}

# ---- 1. API経由 rebase 試行 ----
log "trying gh pr update-branch --rebase"
if gh pr update-branch "$NUM" -R "$REPO" --rebase >> "$LOG_FILE" 2>&1; then
  log "  → API rebase succeeded"
  cleanup
  echo "AUTO_FIXED"
  exit 0
fi
log "  → API rebase failed, falling back to local"

# ---- 2. ローカル rebase 試行 ----
git fetch origin "$BASE" --quiet

if git rebase "origin/$BASE" >> "$LOG_FILE" 2>&1; then
  log "  → local rebase succeeded (no conflicts)"
  if do_push >> "$LOG_FILE" 2>&1; then
    cleanup
    echo "AUTO_FIXED"
    exit 0
  else
    log "  ERROR: push failed"
    cleanup
    echo "ERROR_PUSH_FAILED"
    exit 0
  fi
fi

# ---- 3. conflict 発生 ----
CONFLICTS=$(git diff --name-only --diff-filter=U)
log "conflicts: $(echo "$CONFLICTS" | tr '\n' ' ')"

# ---- 3a. lockfile-only ルート ----
LOCKFILES_RE='^(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|Cargo\.lock|poetry\.lock|uv\.lock|Gemfile\.lock|go\.sum|flake\.lock)$'
all_lockfiles=true
while IFS= read -r f; do
  [ -z "$f" ] && continue
  basename=$(basename "$f")
  if ! echo "$basename" | grep -qE "$LOCKFILES_RE"; then
    all_lockfiles=false
    break
  fi
done <<< "$CONFLICTS"

if [ "$all_lockfiles" = "true" ]; then
  log "  → lockfile-only route"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    basename=$(basename "$f")
    case "$basename" in
      package-lock.json|pnpm-lock.yaml|yarn.lock)
        git checkout --theirs "$f" 2>>"$LOG_FILE" || true
        if [ -f "$(dirname "$f")/pnpm-lock.yaml" ]; then
          (cd "$(dirname "$f")" && pnpm install --no-frozen-lockfile) >> "$LOG_FILE" 2>&1 || true
        elif [ -f "$(dirname "$f")/yarn.lock" ]; then
          (cd "$(dirname "$f")" && yarn install) >> "$LOG_FILE" 2>&1 || true
        else
          (cd "$(dirname "$f")" && npm install) >> "$LOG_FILE" 2>&1 || true
        fi
        ;;
      Cargo.lock)
        git checkout --theirs "$f" 2>>"$LOG_FILE" || true
        (cd "$(dirname "$f")" && cargo update) >> "$LOG_FILE" 2>&1 || true
        ;;
      poetry.lock)
        git checkout --theirs "$f" 2>>"$LOG_FILE" || true
        (cd "$(dirname "$f")" && poetry lock --no-update) >> "$LOG_FILE" 2>&1 || true
        ;;
      uv.lock)
        git checkout --theirs "$f" 2>>"$LOG_FILE" || true
        (cd "$(dirname "$f")" && uv lock) >> "$LOG_FILE" 2>&1 || true
        ;;
      Gemfile.lock)
        git checkout --theirs "$f" 2>>"$LOG_FILE" || true
        (cd "$(dirname "$f")" && bundle install) >> "$LOG_FILE" 2>&1 || true
        ;;
      go.sum)
        git checkout --theirs "$f" 2>>"$LOG_FILE" || true
        (cd "$(dirname "$f")" && go mod tidy) >> "$LOG_FILE" 2>&1 || true
        ;;
      flake.lock)
        git checkout --theirs "$f" 2>>"$LOG_FILE" || true
        (cd "$(dirname "$f")" && nix flake update) >> "$LOG_FILE" 2>&1 || true
        ;;
    esac
    git add "$f" 2>>"$LOG_FILE" || true
  done <<< "$CONFLICTS"

  # 残ったコンフリクトがないか確認
  if [ -n "$(git diff --name-only --diff-filter=U)" ]; then
    log "  ERROR: lockfile route left conflicts"
    cleanup
    echo "ERROR_LOCKFILE_FAILED"
    exit 0
  fi

  if ! GIT_EDITOR=true git rebase --continue >> "$LOG_FILE" 2>&1; then
    log "  ERROR: rebase --continue failed"
    cleanup
    echo "ERROR_REBASE_CONTINUE"
    exit 0
  fi

  if ! do_push >> "$LOG_FILE" 2>&1; then
    log "  ERROR: push failed"
    cleanup
    echo "ERROR_PUSH_FAILED"
    exit 0
  fi

  cleanup
  echo "AUTO_FIXED"
  exit 0
fi

# ---- 3b. risk list 判定 ----
risk_match=false
RISK_PATTERNS='migrations?/|\.env|secrets/|credentials/|terraform/|\.tf$|\.tfvars$|schema\.prisma$|\.sql$'
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if echo "$f" | grep -qE "$RISK_PATTERNS"; then
    risk_match=true
    break
  fi
done <<< "$CONFLICTS"

if [ "$risk_match" = "true" ]; then
  log "  → risk file detected, handing off to human"
  git rebase --abort 2>/dev/null || true
  open_human_tab "$WORK" "RISK_FILES detected: $(echo "$CONFLICTS" | tr '\n' ' ')"
  echo "HUMAN_NEEDED"
  exit 0
fi

# ---- 3c. Claude 判定 ----
# 同一 commit の judge 結果が cache にあれば再利用 (judge は1回20分超など重い)
HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
CACHE_KEY="$REPO#$NUM@$HEAD_SHA"
CACHED=$(judge_cache_lookup "$CACHE_KEY" || true)
# can/conf が空の壊れたキャッシュは無視して再 judge する (過去の bug 由来の残骸対策)
if [ -n "$CACHED" ]; then
  CACHED_CAN=$(echo "$CACHED" | jq -r '.can')
  CACHED_CONF=$(echo "$CACHED" | jq -r '.conf')
  if [ -z "$CACHED_CAN" ] || [ "$CACHED_CAN" = "null" ] || [ -z "$CACHED_CONF" ] || [ "$CACHED_CONF" = "null" ]; then
    log "  judge: cache hit but empty (key=$CACHE_KEY) - ignoring and re-judging"
    CACHED=""
  fi
fi
if [ -n "$CACHED" ]; then
  CAN=$(echo "$CACHED" | jq -r '.can')
  CONF=$(echo "$CACHED" | jq -r '.conf')
  REASON=$(echo "$CACHED" | jq -r '.reason')
  log "  judge: cache hit (key=$CACHE_KEY, can=$CAN conf=$CONF)"
  # cache hit で HIGH 自動解決不可の場合、毎日 zellij タブを開き直すのを避けるため早期 exit。
  # ただし zellij タブが「実は開かれていなかった」状態を救うため、タブの存在を確認してから skip する。
  if [ "$CAN" != "true" ] || [ "$CONF" != "HIGH" ]; then
    EXISTING_TAB=""
    SESSION=$(zellij_session 2>/dev/null || true)
    if [ -n "$SESSION" ]; then
      EXISTING_TAB=$(zj --session "$SESSION" action query-tab-names 2>/dev/null | grep -Fx "Conflict: $REPO#$NUM" || true)
    fi
    if [ -n "$EXISTING_TAB" ]; then
      log "  → cached non-HIGH judge + zellij tab still open, skipping"
      git rebase --abort 2>/dev/null || true
      cleanup
      echo "SKIPPED_CACHED"
      exit 0
    fi
    log "  → cached non-HIGH judge but zellij tab missing; re-open it"
    git rebase --abort 2>/dev/null || true
    open_human_tab "$WORK" "判定 (cached): can_auto=$CAN confidence=$CONF reason=$REASON"
    echo "HUMAN_NEEDED"
    exit 0
  fi
else
  log "  → asking Claude to judge (timeout=${JUDGE_TIMEOUT}s)"

  JUDGE_PROMPT=$(cat <<EOF
あなたは Git conflict resolution の判定エージェントです。
以下のコンフリクトを安全に自動解決できるか判定してください。

リポジトリ: $REPO
PR: #$NUM "$TITLE"
コンフリクトファイル:
$CONFLICTS

各ファイルの内容 (コンフリクトマーカー含む):
$(while IFS= read -r f; do
  [ -z "$f" ] && continue
  echo "=== $f ==="
  cat "$f" 2>/dev/null | head -200
  echo ""
done <<< "$CONFLICTS")

base ($BASE) からの最近のコミット:
$(git log --oneline "origin/$BASE" "^HEAD~10" -- $CONFLICTS 2>/dev/null | head -20)

JSON のみ出力してください (コードフェンスなし、余計なテキストなし):
{"can_auto_resolve": true, "confidence": "HIGH", "reason": "..."}

判定基準:
- import/use の並び順だけ → HIGH
- format / whitespace 差分のみ → HIGH
- 同じ箇所に意味のある変更が両側から → can_auto_resolve=false
- migration / security / auth / DB schema → false
- 迷ったら false
EOF
)

  JUDGE_RAW=$(run_with_timeout "$JUDGE_TIMEOUT" claude --dangerously-skip-permissions -p "$JUDGE_PROMPT" 2>>"$LOG_FILE" || echo "")
  JUDGE=$(echo "$JUDGE_RAW" | sed -n '/^{/,/^}/p')

  if [ -z "$JUDGE" ]; then
    # 空応答 / timeout / prompt 巨大すぎ → 自動解決不可。 false/LOW で確定させる。
    log "  judge: timeout or empty response, treating as can_auto=false"
    CAN="false"
    CONF="LOW"
    REASON="empty judge response (likely timeout or prompt too large)"
  else
    log "  judge: $JUDGE"
    CAN=$(echo "$JUDGE" | jq -r '.can_auto_resolve // false' 2>/dev/null || echo "false")
    CONF=$(echo "$JUDGE" | jq -r '.confidence // "LOW"' 2>/dev/null || echo "LOW")
    REASON=$(echo "$JUDGE" | jq -r '.reason // ""' 2>/dev/null || echo "")
    # CAN が "null" や空のまま入ってきた場合の防御
    [ -z "$CAN" ] || [ "$CAN" = "null" ] && CAN="false"
    [ -z "$CONF" ] || [ "$CONF" = "null" ] && CONF="LOW"
  fi

  # cache に記録 (次回同じ HEAD なら再 judge を回避)
  judge_cache_record "$CACHE_KEY" "$CAN" "$CONF" "$REASON"
fi

# ---- 3c-1. Claude 自動修正 ----
if [ "$CAN" = "true" ] && [ "$CONF" = "HIGH" ]; then
  log "  → Claude HIGH confidence, attempting auto-resolve"

  RESOLVE_PROMPT=$(cat <<EOF
$WORK で \`git rebase origin/$BASE\` 中、conflict が発生中です。

リポジトリ: $REPO / PR #$NUM
コンフリクトファイル:
$CONFLICTS

タスク:
1. 各ファイルの <<<<<<< / ======= / >>>>>>> マーカーを確認
2. 両側の意図を読み取り、両方の変更を保つようマージ (片側だけ採用は最終手段)
3. すべて解決したら \`git add\` する
4. \`git rebase --continue\` は実行しないでください (呼び出し元が行います)

制約:
- テスト/lint 実行不要
- 新規ロジック追加禁止
- 判断に迷ったら "GIVE_UP: <理由>" と1行だけ出力して終了

最後に解決サマリ (ファイルごと1行) を出力してください。
EOF
)

  cd "$WORK"
  log "  → auto-resolve (timeout=${RESOLVE_TIMEOUT}s)"
  AUTO_OUT=$(run_with_timeout "$RESOLVE_TIMEOUT" claude --dangerously-skip-permissions -p "$RESOLVE_PROMPT" 2>>"$LOG_FILE" || echo "")
  log "  auto-resolve output: $(echo "$AUTO_OUT" | tail -20)"

  if echo "$AUTO_OUT" | grep -q "^GIVE_UP"; then
    log "  → Claude gave up"
  elif [ -z "$(git diff --name-only --diff-filter=U)" ]; then
    if ! GIT_EDITOR=true git rebase --continue >> "$LOG_FILE" 2>&1; then
      log "  ERROR: rebase --continue failed after Claude resolve"
      cleanup
      echo "ERROR_REBASE_CONTINUE"
      exit 0
    fi
    if ! do_push >> "$LOG_FILE" 2>&1; then
      log "  ERROR: push failed"
      cleanup
      echo "ERROR_PUSH_FAILED"
      exit 0
    fi
    cleanup
    echo "AUTO_FIXED"
    exit 0
  else
    log "  → Claude left conflicts, falling through to human handoff"
  fi
fi

# ---- 3d. 人間委譲 ----
log "  → handing off to human (zellij tab)"
git rebase --abort 2>/dev/null || true

open_human_tab "$WORK" "判定: can_auto=$CAN confidence=$CONF reason=$REASON"
echo "HUMAN_NEEDED"
