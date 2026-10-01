#!/usr/bin/env bash
# Stop a dev server started by `dev-up`: kill its process group, then remove
# the herdr pane/tab it lives in.
#
# The surface is always closed BY ID, taken from the .meta `dev-up` wrote —
# herdr's `tab close` / `pane close` require an id, so there is no "close whatever
# is focused" form to get wrong.
#
# usage: dev-down <name>
set -uo pipefail

statedir="${DEV_SERVERS_DIR:-/tmp/claude/dev-servers}"  # stable, sandbox-writable (see dev-up)
name="${1:-}"
[ -z "$name" ] && { echo "usage: dev-down <name>" >&2; exit 64; }

meta="$statedir/$name.meta"
pidfile="$statedir/$name.pid"

# How long to let the server shut down before SIGKILL (ticks of 0.25s).
# 8s by default — roughly `docker stop`'s 10s grace, enough for a teardown that
# has to reach the network or a database. Override with DEV_DOWN_GRACE (seconds).
grace_ticks=$(( ${DEV_DOWN_GRACE:-8} * 4 ))
[ "$grace_ticks" -lt 1 ] && grace_ticks=1

metaval() { grep -m1 "^$1=" "$2" 2>/dev/null | cut -d= -f2-; }
kind=""; tabid=""; paneid=""
if [ -f "$meta" ]; then
  kind=$(metaval kind "$meta")
  tabid=$(metaval tabid "$meta")
  paneid=$(metaval paneid "$meta")
fi

# 1) kill the whole process tree via the recorded process-group id.
if [ -f "$pidfile" ]; then
  pgid="$(cat "$pidfile" 2>/dev/null)"
  if [ -n "$pgid" ]; then
    kill -TERM "-$pgid" 2>/dev/null || true
    # Wait for the processes IN THE GROUP to go away — not just the group leader.
    # The leader is dev-serve-run's bash, which dies on SIGTERM immediately while
    # its child is still shutting down. Watching only the leader's pid therefore
    # broke out of this loop at once and SIGKILLed the actual server ~0.3s in,
    # cutting off graceful teardown (flushing logs, closing pools, writing a
    # shutdown record). Servers that record their own stop never got to.
    for _ in $(seq "$grace_ticks"); do
      pgrep -g "$pgid" >/dev/null 2>&1 || break
      sleep 0.25
    done
    kill -KILL "-$pgid" 2>/dev/null || true
  fi
fi

# 2) remove the herdr surface.
#
# herdr has no `--close-on-exit`: the pane's shell outlives the command, so the
# surface ALWAYS has to be closed explicitly here (under zellij the pane usually
# disappeared on its own and this was just a fallback).
case "$kind" in
  tab)
    [ -n "$tabid" ] && herdr tab close "$tabid" >/dev/null 2>&1 || true
    ;;
  # stack/float are zellij-era kinds that can still be sitting in an old .meta.
  # The recorded id is then a zellij pane number, which herdr just rejects — the
  # process kill above is what matters, and the stale surface is the old
  # multiplexer's problem, not ours.
  split|stack|float)
    [ -n "$paneid" ] && herdr pane close "$paneid" >/dev/null 2>&1 || true
    ;;
esac

# Removing the meta also clears keep=1, so dev-supervise stops restarting it.
rm -f "$meta" "$pidfile" "$statedir/$name.argv" "$statedir/$name.spec"
echo "dev:$name stopped"
