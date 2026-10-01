#!/usr/bin/env bash
# Watchdog: restart any dev-up server marked --keep (keep=1) that has died.
#
# Why this works: real dev servers (pnpm/vite/node) get SIGTERM'd after a while by
# something that targets *servers* specifically — trivial processes are spared
# (verified: bare sleep-loops in the same multiplexer survive 70+ min while pnpm
# dev dies with 143). This watchdog loop is itself trivial, so it survives, and it
# re-launches dead supervised servers via dev-up.
#
# Run it ONCE inside your herdr session, in its own tab:
#     dev-up --tab supervisor -- dev-supervise
# Then start servers with --keep:
#     dev-up --keep --tab weboard -- pnpm dev:proxy --filter weboard
# Stop supervising one with `dev-down <name>` (removes its keep marker).
set -uo pipefail

statedir="${DEV_SERVERS_DIR:-/tmp/claude/dev-servers}"
interval="${DEV_SUPERVISE_INTERVAL:-15}"   # seconds between checks
win=120          # restart-rate window (s)
maxrestarts=5    # more than this within $win → cool down (avoid crash-loops)
cooldown=300     # backoff (s) after hitting the rate limit
mkdir -p "$statedir"

metaval() { grep -m1 "^$1=" "$2" 2>/dev/null | cut -d= -f2-; }
now()     { date +%s; }
log()     { echo "[$(date '+%m-%d %H:%M:%S')] $*"; }

# Single-instance guard: only one watchdog should run.
lock="$statedir/.supervise.pid"
if [ -f "$lock" ] && kill -0 "$(cat "$lock" 2>/dev/null)" 2>/dev/null; then
  log "another dev-supervise is already running (pid $(cat "$lock")); exiting"
  exit 0
fi
echo "$$" > "$lock"
trap 'rm -f "$lock"' EXIT

herdr tab list >/dev/null 2>&1 || log "WARNING: no reachable herdr server — dev-up restarts will fail"

log "dev-supervise start (interval=${interval}s, dir=$statedir)"
while true; do
  for m in "$statedir"/*.meta; do
    [ -e "$m" ] || continue
    name=$(basename "$m" .meta)
    [ "$(metaval keep "$m")" = "1" ] || continue

    pidf="$statedir/$name.pid"
    if [ -f "$pidf" ] && kill -0 "$(cat "$pidf" 2>/dev/null)" 2>/dev/null; then
      continue   # still alive
    fi

    t=$(now)

    # In a backoff window? skip.
    cdf="$statedir/$name.cooldown"
    if [ -f "$cdf" ] && [ "$t" -lt "$(cat "$cdf" 2>/dev/null || echo 0)" ]; then
      continue
    fi

    # Restart-rate limiting: prune restart timestamps to the window, count them.
    rstf="$statedir/$name.rst"
    if [ -f "$rstf" ]; then
      awk -v t="$t" -v w="$win" '($1+0)>=t-w' "$rstf" > "$rstf.tmp" 2>/dev/null && mv "$rstf.tmp" "$rstf"
    fi
    cnt=$([ -f "$rstf" ] && wc -l < "$rstf" | tr -d ' ' || echo 0)
    if [ "${cnt:-0}" -ge "$maxrestarts" ]; then
      echo "$((t + cooldown))" > "$cdf"
      : > "$rstf"
      log "$name: too many restarts (${cnt} in ${win}s) → backing off ${cooldown}s"
      continue
    fi

    kind=$(metaval kind "$m"); cwd=$(metaval cwd "$m")
    # --split can only be respawned from inside the original pane, and stale
    # zellij-era metas may still say stack/float. Anything that isn't a plain
    # tab restarts as a tab — the watchdog usually runs in its own tab anyway.
    [ "$kind" = tab ] || kind=tab
    argvf="$statedir/$name.argv"
    [ -e "$argvf" ] || { log "$name: no argv file, cannot restart"; continue; }
    argv=(); while IFS= read -r -d '' a; do argv+=("$a"); done < "$argvf"
    [ "${#argv[@]}" -gt 0 ] || { log "$name: empty argv, skip"; continue; }

    echo "$t" >> "$rstf"
    log "restart dev:$name ($kind) in $cwd : ${argv[*]}"
    # --keep so the respawned server stays supervised.
    ( cd "$cwd" 2>/dev/null && dev-up --keep "--$kind" "$name" -- "${argv[@]}" ) \
      >> "$statedir/dev-supervise.log" 2>&1 || log "$name: restart command failed"
  done
  sleep "$interval"
done
