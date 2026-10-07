#!/usr/bin/env bash
# Internal wrapper launched *inside* a zellij tab/pane by `dev-up`.
#
# Why it exists:
#  - It records this shell's PID as the process-group leader so `dev-down` can
#    stop the whole tree (pnpm -> node -> vite ...) with `kill -TERM -<pgid>`.
#    Job control is off in scripts, so every child stays in this pgid == $$.
#  - It tees output to a logfile so `dev-logs` (and Claude, headless) can read
#    the server's output without stealing the zellij pane.
#
# argv: <name> [statedir]
#
# Everything else — the command, its cwd, and the caller's PATH — is read from
# the state dir, NOT from the command line.
#
# Why: the state dir is the single source of truth that dev-supervise also uses to
# respawn the exact same command. (Under herdr the command also had to be TYPED into
# the pane, where long lines got truncated; zellij takes argv directly, but keeping
# the command line short costs nothing.)
#
# The caller's PATH is forwarded (via the spec file) because this runs in a shell
# spawned by the zellij server, not by the caller. A pane started from launchd or
# a background session does not get the user's mise/Homebrew PATH, and that used to
# end in "command not found" (exit 127).
set -u

name="${1:?dev-serve-run: missing name}"
statedir="${2:-${DEV_SERVERS_DIR:-/tmp/claude/dev-servers}}"

log="$statedir/$name.log"
pidfile="$statedir/$name.pid"
specfile="$statedir/$name.spec"
argvfile="$statedir/$name.argv"

[ -f "$specfile" ] || { echo "dev-serve-run: missing spec $specfile" >&2; exit 66; }
[ -f "$argvfile" ] || { echo "dev-serve-run: missing argv $argvfile" >&2; exit 66; }

specval() { grep -m1 "^$1=" "$specfile" 2>/dev/null | cut -d= -f2-; }
cwd=$(specval cwd)
caller_path=$(specval path)
[ -n "$cwd" ] || { echo "dev-serve-run: no cwd in $specfile" >&2; exit 66; }

# NUL-delimited so arguments with spaces/newlines survive the round trip.
set --
while IFS= read -r -d '' a; do set -- "$@" "$a"; done < "$argvfile"
if [ "$#" -eq 0 ]; then
  echo "dev-serve-run: no command in $argvfile" >&2
  exit 64
fi

# Use the same PATH the user had when they ran dev-up, so `pnpm dev` etc. resolve
# exactly as they do in their shell.
[ -n "$caller_path" ] && export PATH="$caller_path"

mkdir -p "$(dirname "$pidfile")"

# $$ is this non-interactive shell's PID and, with job control off, the process
# group leader for every child it spawns. Record it for `dev-down`.
echo "$$" > "$pidfile"

cd "$cwd" || { echo "dev-serve-run: cannot cd to $cwd" | tee -a "$log" >&2; exit 66; }

{
  echo "▶ dev:$name started $(date '+%Y-%m-%d %H:%M:%S')"
  echo "  cwd : $cwd"
  echo "  cmd : $*"
  echo "  pgid: $$"
  echo "  ---"
} | tee -a "$log"

# Mirror all further output to the logfile while keeping it visible in the pane.
# `trap '' TERM` before exec'ing tee makes tee inherit SIG_IGN, so the group kill
# below does not take the log pipe out from under a server that is still logging
# its shutdown — tee exits on its own once stdin closes.
exec > >(trap '' TERM; tee -a "$log") 2>&1

# Run the command in the BACKGROUND and wait for it, rather than in the foreground.
#
# Why: `dev-down` stops a server with `kill -TERM -<pgid>`, which hits this shell
# too. Running the command in the foreground, bash dies on that TERM immediately,
# and the zellij pane then tears down and takes the still-shutting-down server
# with it — measured gone within 200ms, long before any SIGKILL, so graceful
# teardown (flushing logs, closing pools, writing a shutdown record) never got to
# finish.
#
# So this shell survives the signal and waits for the child instead. It does NOT
# forward another TERM: the child already received its own from the group kill,
# and a server with a one-shot handler (Node's `process.once("SIGTERM", …)`) would
# die on the second signal — exactly the failure being fixed here.
#
# `<&0` keeps the pane's tty as the child's stdin. Without an explicit redirection
# bash gives a background job /dev/null, which would break interactive dev-server
# keys (Vite's `r` / `h`).
"$@" <&0 &
child=$!
# Set AFTER the fork, so the child keeps the default signal dispositions. `:` and
# not '' — an ignored disposition set before the fork would be inherited, making
# the server itself deaf to SIGTERM.
trap ':' TERM INT HUP
status=0
while kill -0 "$child" 2>/dev/null; do
  wait "$child"
  status=$?
done
echo "■ dev:$name exited (status=$status) $(date '+%Y-%m-%d %H:%M:%S')"
exit "$status"
