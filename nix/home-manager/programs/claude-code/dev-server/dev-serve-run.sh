#!/usr/bin/env bash
# Internal wrapper launched *inside* a herdr pane/tab by `dev-up`.
#
# Why it exists:
#  - It records this shell's PID as the process-group leader so `dev-down` can
#    stop the whole tree (pnpm -> node -> vite ...) with `kill -TERM -<pgid>`.
#    Job control is off in scripts, so every child stays in this pgid == $$.
#  - It tees output to a logfile so `dev-logs` (and Claude, headless) can read
#    the server's output without stealing the herdr pane.
#
# argv: <name> [statedir]
#
# Everything else — the command, its cwd, and the caller's PATH — is read from
# the state dir, NOT from the command line.
#
# Why: herdr has no `new-pane -- cmd`; `dev-up` starts this by TYPING a command
# into the pane's shell (`herdr pane run`). Long lines get truncated on the way
# in — a full forwarded $PATH pushed the line past ~1KB and it arrived cut in
# half, so nothing ran and the log stayed empty. Keeping the typed line down to
# `dev-serve-run <name> <statedir>` makes that impossible regardless of how long
# the command or the caller's PATH is.
#
# The caller's PATH is still forwarded (via the spec file) because this runs in a
# shell spawned by the herdr server, not by the caller. herdr does start panes as
# login shells (so mise / Homebrew / corepack tools are normally on PATH anyway),
# but that depends on `terminal.shell_mode`, and under zellij a missing PATH meant
# "command not found" (exit 127). Forwarding keeps this independent of the setting.
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
# and under zellij the pane then tore down and took the still-shutting-down server
# with it — measured gone within 200ms, long before any SIGKILL, so graceful
# teardown (flushing logs, closing pools, writing a shutdown record) never got to
# finish. herdr panes outlive their command, so that particular teardown race is
# gone, but the wrapper still has to survive the group kill to keep waiting on the
# child (and to report its real exit status).
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
