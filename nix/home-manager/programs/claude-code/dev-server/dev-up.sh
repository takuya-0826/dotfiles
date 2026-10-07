#!/usr/bin/env bash
# Start a long-running dev server inside a zellij tab/pane so it SURVIVES.
#
# Why: a `!`-backgrounded or `run_in_background` process is a child of the
# Claude Code harness and gets reaped with SIGTERM (exit 143) after a while.
# A tab/pane command is a child of the zellij server instead, outside the
# harness's process tree, so it keeps running until you `dev-down` it.
#
# usage: dev-up [--keep] [--tab|--split] <name> [--] <cmd> [args...]
#   --tab    (default) a new tab named  dev:<name>  in the background session
#            "dev-servers" (created if missing; nothing steals your focus, and it
#            keeps running even with no zellij client open — e.g. when you work
#            from the Claude desktop app)
#   --split  split the pane you are in (must run inside zellij)
#   --keep   mark this server "supervised" so `dev-supervise` auto-restarts it if
#            it dies. Real dev servers (pnpm/vite) get SIGTERM'd after a while by
#            something that targets servers specifically; --keep makes them self-heal.
#
# examples:
#   dev-up weboard -- pnpm dev:proxy --filter weboard
#   dev-up --keep --tab api -- pnpm --filter api dev
#   zellij attach dev-servers      # look at the servers
set -euo pipefail

# /tmp/claude is a STABLE, sandbox-writable path shared across every context that
# touches this state — Claude Code's Bash sandbox, your real shell, and the zellij
# pane (dev-serve-run). $TMPDIR is NOT usable: it differs per context, so dev-up
# and dev-down would compute different dirs and never see each other's state.
statedir="${DEV_SERVERS_DIR:-/tmp/claude/dev-servers}"
runner_bin="${DEV_SERVE_RUN:-$HOME/.local/bin/dev-serve-run}"
dev_session="${DEV_SERVERS_SESSION:-dev-servers}"
place=tab
keep=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tab)   place=tab;   shift ;;
    --split) place=split; shift ;;
    --keep)  keep=1;      shift ;;
    --stack|--float)
      echo "dev-up: $1 is gone — use --tab (default) or --split." >&2
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

# --split needs a pane to split, which means running from inside zellij.
if [ "$place" = split ] && [ -z "${ZELLIJ:-}" ]; then
  echo "dev-up: --split needs to run inside a zellij pane; use --tab." >&2
  exit 69
fi

# Where the surface lives. zj normalises $TMPDIR so the socket is found from any
# shell (launchd, Claude's Bash via dev-ctl, your terminal).
if [ "$place" = tab ]; then
  session="$dev_session"
  zj ensure "$session" || { zj preflight dev-up; exit 69; }
else
  session="$ZELLIJ_SESSION_NAME"
  zj preflight dev-up || exit 69
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

# Restart hygiene: a tab started without --close-on-exit stays behind after its
# command dies (so you can read the exit status). Close the previous surface BY ID
# first so a restart — e.g. by dev-supervise — doesn't pile up dead tabs. Never a
# bare close-tab: that closes whatever tab is focused.
if [ -f "$meta" ]; then
  old_kind=$(grep -m1 '^kind=' "$meta" 2>/dev/null | cut -d= -f2-)
  old_session=$(grep -m1 '^session=' "$meta" 2>/dev/null | cut -d= -f2-)
  old_tabid=$(grep -m1 '^tabid=' "$meta" 2>/dev/null | cut -d= -f2-)
  old_paneid=$(grep -m1 '^paneid=' "$meta" 2>/dev/null | cut -d= -f2-)
  if [ -n "$old_session" ]; then
    if [ "$old_kind" = tab ] && [ -n "$old_tabid" ]; then
      zj -s "$old_session" action close-tab-by-id "$old_tabid" >/dev/null 2>&1 || true
    elif [ -n "$old_paneid" ]; then
      zj -s "$old_session" action close-pane --pane-id "$old_paneid" >/dev/null 2>&1 || true
    fi
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

case "$place" in
  tab)
    # new-tab prints the new tab's stable id. No --close-on-exit: if the server dies
    # the tab stays and shows why; dev-down / the next dev-up close it by id.
    tabid=$(zj -s "$session" action new-tab --name "dev:$name" --cwd "$cwd" -- \
      "$runner_bin" "$name" "$statedir" | tr -dc '0-9')
    paneid=""
    ;;
  split)
    paneid=$(zj -s "$session" action new-pane --direction down --close-on-exit \
      --name "dev:$name" --cwd "$cwd" -- "$runner_bin" "$name" "$statedir")
    tabid=""
    ;;
esac

if [ -z "${tabid}${paneid}" ]; then
  echo "dev-up: zellij did not return a tab/pane id (session $session)" >&2
  exit 70
fi

{
  echo "kind=$place"
  echo "session=$session"
  echo "tabid=$tabid"
  echo "paneid=$paneid"
  echo "cwd=$cwd"
  echo "keep=$keep"
  printf 'cmd=%s\n' "$*"
} > "$meta"

echo "dev:$name up ($place in zellij session '$session'$([ "$keep" = 1 ] && echo ', supervised'))  log: $log"
echo "  dev-logs $name    # tail output (use this to check it started / see errors)"
echo "  dev-down $name    # stop it$([ "$keep" = 1 ] && echo ' (and stop supervising)')"
[ "$place" = tab ] && echo "  zellij attach $session   # look at it"
[ "$keep" = 1 ] && echo "  (run 'dev-supervise' once — in a tab — so a watchdog restarts it if it dies)"
true
