#!/usr/bin/env bash
# Show a dev server's captured output (tee'd to a file by dev-serve-run).
# The pane may be off-screen, so this is how you check "did it start? any errors?"
#
# usage: dev-logs <name> [lines]   # default 60
#        dev-logs <name> -f        # follow (interactive only; blocks)
set -uo pipefail

statedir="${DEV_SERVERS_DIR:-/tmp/claude/dev-servers}"  # stable, sandbox-writable (see dev-up)
name="${1:-}"
[ -z "$name" ] && { echo "usage: dev-logs <name> [lines|-f]" >&2; exit 64; }

log="$statedir/$name.log"
[ -f "$log" ] || { echo "dev-logs: no log for dev:$name ($log)" >&2; exit 1; }

if [ "${2:-}" = "-f" ]; then
  exec tail -f "$log"
fi
tail -n "${2:-60}" "$log"
