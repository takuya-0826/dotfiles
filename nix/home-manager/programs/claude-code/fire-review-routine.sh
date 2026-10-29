#!/usr/bin/env bash
set -euo pipefail

# gh-review-watcher から呼ばれる: Claude Code のルーティン「PRレビュー一次請け」を
# API トリガー (/fire) で起動し、PR の情報を fire payload として渡す。
# レビューは claude.ai のクラウドセッションで走り、結果はそのセッションで見る。
# usage: fire-review-routine <url> <number> <repo>
#
# 必要なもの:
#   - ルーティンの API トークン。macOS キーチェーンに入れておく:
#       security add-generic-password -U -a "$USER" -s claude-routine-pr-review -w '<sk-ant-oat01-...>'
#     ($REVIEW_ROUTINE_TOKEN があればそちらを優先)
#   - ルーティン ID は $REVIEW_ROUTINE_ID で上書き可 (既定は「PRレビュー一次請け」)。
#
# 起動に失敗したとき (トークン無し・HTTP エラー) は従来どおり open-review-tab で
# zellij タブにフォールバックする。止めたいなら REVIEW_ROUTINE_FALLBACK=none。

URL="${1:-}"
NUMBER="${2:-}"
REPO="${3:-}"

if [ -z "$URL" ] || [ -z "$NUMBER" ] || [ -z "$REPO" ]; then
  echo "usage: $(basename "$0") <url> <number> <repo>" >&2
  exit 2
fi

HOOK_LOG="${GH_REVIEW_WATCHER_LOG:-/tmp/gh-review-watcher-hooks.log}"
ROUTINE_ID="${REVIEW_ROUTINE_ID:-trig_01CARoNh7G8ZVkkaypkQXtis}"
KEYCHAIN_SERVICE="${REVIEW_ROUTINE_KEYCHAIN_SERVICE:-claude-routine-pr-review}"
FALLBACK="${REVIEW_ROUTINE_FALLBACK:-tab}"

log() { printf '[ROUTINE] %s#%s %s\n' "$REPO" "$NUMBER" "$*" | tee -a "$HOOK_LOG" >&2; }

fallback() {
  log "$1"
  if [ "$FALLBACK" = "tab" ]; then
    log "fallback: open-review-tab"
    exec open-review-tab "$URL" "$NUMBER" "$REPO"
  fi
  exit 1
}

TOKEN="${REVIEW_ROUTINE_TOKEN:-}"
if [ -z "$TOKEN" ] && command -v security >/dev/null 2>&1; then
  TOKEN=$(security find-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null || true)
fi
[ -n "$TOKEN" ] || fallback "no API token (keychain service '$KEYCHAIN_SERVICE' / \$REVIEW_ROUTINE_TOKEN)"

# ルーティン側のプロンプトが <routine-fire-payload> を参照してこの PR を対象にする。
TEXT=$(printf 'レビュー対象の PR:\n- repo: %s\n- number: %s\n- url: %s\n' "$REPO" "$NUMBER" "$URL")
BODY=$(jq -n --arg text "$TEXT" '{text: $text}')

RESP_FILE=$(mktemp)
trap 'rm -f "$RESP_FILE"' EXIT

HTTP_CODE=$(curl -sS -o "$RESP_FILE" -w '%{http_code}' --max-time 30 \
  -X POST "https://api.anthropic.com/v1/claude_code/routines/${ROUTINE_ID}/fire" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "anthropic-beta: experimental-cc-routine-2026-04-01" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d "$BODY") || HTTP_CODE="curl-error"

if [ "$HTTP_CODE" != "200" ]; then
  fallback "fire failed (HTTP $HTTP_CODE): $(head -c 300 "$RESP_FILE" 2>/dev/null)"
fi

SESSION_URL=$(jq -r '.claude_code_session_url // empty' "$RESP_FILE")
log "fired: ${SESSION_URL:-(no session url)}"
