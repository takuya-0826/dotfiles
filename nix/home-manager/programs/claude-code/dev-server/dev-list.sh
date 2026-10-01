#!/usr/bin/env bash
# List dev servers started by dev-up and whether each is still alive.
# usage: dev-list
set -uo pipefail

statedir="${DEV_SERVERS_DIR:-/tmp/claude/dev-servers}"  # stable, sandbox-writable (see dev-up)
shopt -s nullglob
metas=("$statedir"/*.meta)
if [ "${#metas[@]}" -eq 0 ]; then
  echo "(no dev servers)"
  exit 0
fi

metaval() { grep -m1 "^$1=" "$2" 2>/dev/null | cut -d= -f2-; }

printf '%-16s %-7s %-6s %-5s %s\n' NAME KIND STATE KEEP CMD
for m in "${metas[@]}"; do
  name="$(basename "$m" .meta)"
  kind="$(metaval kind "$m")"
  cmd="$(metaval cmd "$m")"
  keep="$(metaval keep "$m")"
  [ "$keep" = 1 ] && keep=yes || keep=no
  pidfile="$statedir/$name.pid"
  state="dead"
  if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null; then
    state="alive"
  fi
  printf '%-16s %-7s %-6s %-5s %s\n' "$name" "${kind:-?}" "$state" "$keep" "${cmd:-?}"
done
