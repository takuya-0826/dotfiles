#!/usr/bin/env bash
set -uo pipefail

# launchd から数時間おきに叩かれる renovate skill のスケジュール実行 entrypoint。
# 設定した repo それぞれに対して `claude -p /renovate <repo>` を順に走らせる。
# 各 repo の処理は skill 内で完結する（rebase→CI待ち→auto-approve→merge、
# 落ちたら最大2回まで自動修正、直らなければ issue 化）。

export PATH=$HOME/.local/share/mise/shims:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/Users/takuyamatsumoto

# 非対話 (launchd) では claude のサブスク認証 (ログインキーチェーン) が読めず
# "Not logged in" になる。`claude setup-token` で発行した長寿命 OAuth トークンを
# gitignore 対象の秘密ファイルに置き、env で渡す (サブスクのまま・API 従量課金なし)。
# 発行手順:  claude setup-token  → 出力を下記ファイルに保存 (chmod 600)。
TOKEN_FILE="$HOME/.config/renovate/oauth-token"

# 対象リポジトリ。増やす時はここに足す。
REPOS=(
  "Atrae/wevox-mono-web"
  "EdV4H/usketch"
)

LOG_FILE="/tmp/renovate-scheduled.log"
CLAUDE="$HOME/.nix-profile/bin/claude"

log() { echo "$(date '+%Y-%m-%dT%H:%M:%S') $*" >> "$LOG_FILE"; }

# 多重起動防止（前回の実行が数時間かかって次の起動と重なる事故を防ぐ）。
# flock 相当を mkdir で実現（macOS には flock がない）。
LOCK_DIR="$HOME/.cache/renovate-scheduled/lock"
mkdir -p "$(dirname "$LOCK_DIR")"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  # 古い（6時間以上前の）ロックは異常終了の残骸とみなして奪う
  if [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +360 2>/dev/null)" ]; then
    log "=== stale lock を除去して続行 ==="
    rm -rf "$LOCK_DIR" && mkdir "$LOCK_DIR"
  else
    log "=== Skipped: 前回の実行がまだ走っている (lock あり) ==="
    exit 0
  fi
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

if [ ! -x "$CLAUDE" ]; then
  log "ERROR: claude が見つからない ($CLAUDE)"
  exit 1
fi

if [ -f "$TOKEN_FILE" ]; then
  CLAUDE_CODE_OAUTH_TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"
  export CLAUDE_CODE_OAUTH_TOKEN
else
  log "ERROR: OAuth トークン未設定 ($TOKEN_FILE)。"
  log "  対話で 'claude setup-token' を実行し、出力を上記ファイルに保存 (chmod 600) してください。"
  exit 1
fi

log "=== Starting renovate-scheduled (repos: ${REPOS[*]}) ==="

for repo in "${REPOS[@]}"; do
  log "--- $repo 処理開始 ---"
  # stdin は /dev/null に切る（claude が親の stdin を吸わないように）。
  # 出力はログへ。skill 側で PR ごとに rebase/CI待ち/approve/merge/fix を行う。
  "$CLAUDE" --dangerously-skip-permissions -p "/renovate $repo" \
    < /dev/null >> "$LOG_FILE" 2>&1 \
    && log "--- $repo 処理完了 ---" \
    || log "--- $repo 処理でエラー (exit $?) ---"
done

log "=== Done ==="
