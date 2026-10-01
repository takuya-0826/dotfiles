#!/usr/bin/env bash
# Start a long-running dev server inside a herdr pane/tab so it SURVIVES.
#
# Why: a `!`-backgrounded or `run_in_background` process is a child of the
# Claude Code harness and gets reaped with SIGTERM (exit 143) after a while.
# A pane/tab command is a child of the herdr server instead, outside the
# harness's process tree, so it keeps running until you `dev-down` it.
#
# usage: dev-up [--keep] [--tab|--split] <name> [--] <cmd> [args...]
#   --tab    (default) a new tab named  dev:<name>  (focus stays where you are)
#   --split  split the pane you are in
#   --keep   mark this server "supervised" so `dev-supervise` auto-restarts it if
#            it dies. Real dev servers (pnpm/vite) get SIGTERM'd after a while by
#            something that targets servers specifically; --keep makes them self-heal.
#
# examples:
#   dev-up weboard -- pnpm dev:proxy --filter weboard
#   dev-up --keep --tab api -- pnpm --filter api dev
set -euo pipefail

# /tmp/claude is a STABLE, sandbox-writable path shared across every context that
# touches this state — Claude Code's Bash sandbox, your real shell, and the herdr
# pane (dev-serve-run). $TMPDIR is NOT usable: it differs per context, so dev-up
# and dev-down would compute different dirs and never see each other's state.
statedir="${DEV_SERVERS_DIR:-/tmp/claude/dev-servers}"
runner_bin="${DEV_SERVE_RUN:-$HOME/.local/bin/dev-serve-run}"
place=tab
keep=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tab)   place=tab;   shift ;;
    --split) place=split; shift ;;
    --keep)  keep=1;      shift ;;
    --stack|--float)
      echo "dev-up: $1 is gone — herdr has no stacked or floating panes." >&2
      echo "  use --tab (default) or --split instead." >&2
      exit 64 ;;
    --) shift; break ;;
    --*) echo "dev-up: unknown flag $1" >&2; exit 64 ;;
    *) break ;;
  esac
done

name="${1:-}"
[ -z "$name" ] && { echo "usage: dev-up [--tab|--split] <name> -- <cmd...>" >&2; exit 64; }
shift
[ "${1:-}" = "--" ] && shift
[ "$#" -eq 0 ] && { echo "dev-up: no command given" >&2; exit 64; }

case "$name" in
  *[!A-Za-z0-9._-]*) echo "dev-up: name may only contain [A-Za-z0-9._-]" >&2; exit 64 ;;
esac

# Preflight: can we reach the herdr server at all? Unlike zellij there is no
# $TMPDIR trap here — the socket lives at a fixed path (~/.config/herdr/…) and
# panes also get $HERDR_SOCKET_PATH — so a sandboxed shell reaches the same
# server as your real one. A failure here means no server is running.
if ! herdr tab list >/dev/null 2>&1; then
  echo "dev-up: can't reach a herdr server. Start one with \`herdr\` first." >&2
  exit 69
fi

# --split needs a pane to split, which means running from inside herdr.
if [ "$place" = split ] && [ -z "${HERDR_PANE_ID:-}" ]; then
  echo "dev-up: --split needs \$HERDR_PANE_ID (run it inside a herdr pane), or use --tab." >&2
  exit 69
fi

[ -x "$runner_bin" ] && : || runner_bin="dev-serve-run"  # fall back to PATH lookup

mkdir -p "$statedir"
meta="$statedir/$name.meta"
log="$statedir/$name.log"
pidfile="$statedir/$name.pid"

if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null; then
  echo "dev-up: dev:$name already running (pgid=$(cat "$pidfile")). Run 'dev-down $name' first." >&2
  exit 1
fi

# Restart hygiene: herdr panes do NOT vanish when their command exits (there is no
# --close-on-exit), so a previous run of the same name always leaves its surface
# behind. Close it BY ID first so a restart — e.g. by dev-supervise — doesn't pile
# up dead tabs/panes.
if [ -f "$meta" ]; then
  old_kind=$(grep -m1 '^kind=' "$meta" 2>/dev/null | cut -d= -f2-)
  old_tabid=$(grep -m1 '^tabid=' "$meta" 2>/dev/null | cut -d= -f2-)
  old_paneid=$(grep -m1 '^paneid=' "$meta" 2>/dev/null | cut -d= -f2-)
  if [ "$old_kind" = tab ] && [ -n "$old_tabid" ]; then
    herdr tab close "$old_tabid" >/dev/null 2>&1 || true
  elif [ -n "$old_paneid" ]; then
    herdr pane close "$old_paneid" >/dev/null 2>&1 || true
  fi
fi

cwd="$PWD"
: > "$log"

# Record argv (NUL-delimited) so dev-serve-run can run it and dev-supervise can
# respawn with the exact command, and the cwd/PATH it should run under.
printf '%s\0' "$@" > "$statedir/$name.argv"
{
  printf 'cwd=%s\n' "$cwd"
  printf 'path=%s\n' "$PATH"
} > "$statedir/$name.spec"

# herdr's `pane run` TYPES the command into the pane's shell — there is no argv
# form like zellij's `new-pane -- cmd` — and a long line gets TRUNCATED on the way
# in (a forwarded $PATH alone pushed it past ~1KB and it arrived cut in half, so
# nothing ran). Hence everything real lives in the state dir and the typed line
# stays short. It is still quoted, because $statedir can contain spaces.
runcmd=$(printf '%q ' "$runner_bin" "$name" "$statedir")

# Resolve (creating if needed) a dedicated workspace to group all dev servers, so
# they don't clutter your working space. Override the label with $DEV_SERVERS_WORKSPACE.
dev_ws_id() {
  local label="${DEV_SERVERS_WORKSPACE:-dev-servers}" id
  id=$(herdr workspace list 2>/dev/null | jq -r --arg l "$label" \
        '.result.workspaces[]? | select(.label==$l) | .workspace_id' | head -1)
  if [ -z "$id" ]; then
    herdr workspace create --label "$label" --no-focus >/dev/null 2>&1 || true
    id=$(herdr workspace list 2>/dev/null | jq -r --arg l "$label" \
          '.result.workspaces[]? | select(.label==$l) | .workspace_id' | head -1)
  fi
  printf '%s' "$id"
}

case "$place" in
  tab)
    wsopt=(); wsid=$(dev_ws_id); [ -n "$wsid" ] && wsopt=(--workspace "$wsid")
    created=$(herdr tab create "${wsopt[@]}" --label "dev:$name" --cwd "$cwd" --no-focus)
    tabid=$(printf '%s' "$created" | jq -r '.result.tab.tab_id')
    paneid=$(printf '%s' "$created" | jq -r '.result.root_pane.pane_id')
    ;;
  split)
    created=$(herdr pane split --pane "$HERDR_PANE_ID" --direction down --cwd "$cwd" --no-focus)
    tabid=$(printf '%s' "$created" | jq -r '.result.pane.tab_id')
    paneid=$(printf '%s' "$created" | jq -r '.result.pane.pane_id')
    ;;
esac

if [ -z "${paneid:-}" ] || [ "$paneid" = null ]; then
  echo "dev-up: herdr did not return a pane id:" >&2
  printf '%s\n' "$created" >&2
  exit 70
fi

herdr pane rename "$paneid" "dev:$name" >/dev/null 2>&1 || true
herdr pane run "$paneid" "$runcmd" >/dev/null

{
  echo "kind=$place"
  echo "tabid=$tabid"
  echo "paneid=$paneid"
  echo "cwd=$cwd"
  echo "keep=$keep"
  printf 'cmd=%s\n' "$*"
} > "$meta"

echo "dev:$name up ($place$([ "$keep" = 1 ] && echo ', supervised'))  log: $log"
echo "  dev-logs $name    # tail output (use this to check it started / see errors)"
echo "  dev-down $name    # stop it$([ "$keep" = 1 ] && echo ' (and stop supervising)')"
[ "$keep" = 1 ] && echo "  (run 'dev-supervise' once — in a tab — so a watchdog restarts it if it dies)"
true
