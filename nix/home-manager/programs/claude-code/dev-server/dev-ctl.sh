#!/usr/bin/env bash
# dev-ctl — sandbox-escape front-end for the herdr-touching dev-server commands.
#
# Why: Claude Code's Bash sandbox blocks the herdr control socket (and `kill -0`
# on other pids), so `dev-up` / `dev-down` / a reliable `dev-list` do NOT work when
# Claude runs them directly. But scripts under ~/.claude/scripts/ run OUTSIDE the
# sandbox when invoked BY DIRECT PATH. So Claude drives dev servers through this:
#
#     ~/.claude/scripts/dev-ctl up   --keep --tab weboard -- pnpm dev:proxy --filter weboard
#     ~/.claude/scripts/dev-ctl list
#     ~/.claude/scripts/dev-ctl logs weboard
#     ~/.claude/scripts/dev-ctl down weboard
#     ~/.claude/scripts/dev-ctl supervise
#
# From a real herdr shell you can still call dev-up/dev-down/dev-list directly.
# (This file is installed by home-manager to ~/.claude/scripts/dev-ctl.)
set -uo pipefail

# mise shims first so `pnpm`/`node` resolve for whatever server we (re)start;
# ~/.local/bin has the dev-* commands; nix-profile has herdr/jq.
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$HOME/.nix-profile/bin:$PATH"

sub="${1:-}"
shift 2>/dev/null || true

case "$sub" in
  up)        exec dev-up "$@" ;;
  down)      exec dev-down "$@" ;;
  logs)      exec dev-logs "$@" ;;
  list)      exec dev-list "$@" ;;   # runs outside the sandbox → alive/dead is accurate
  supervise) exec dev-up --tab supervisor -- dev-supervise ;;
  ""|-h|--help|help)
    cat >&2 <<'USAGE'
usage: dev-ctl <subcommand> [args...]
  up [--keep] [--tab|--split] <name> -- <cmd...>   start a dev server (herdr)
  down <name>                                      stop it
  logs <name> [lines]                              tail its output
  list                                             list servers (accurate state)
  supervise                                        start the auto-restart watchdog
Run BY DIRECT PATH so it executes outside the Claude sandbox:
  ~/.claude/scripts/dev-ctl up --keep --tab weboard -- pnpm dev:proxy --filter weboard
USAGE
    exit 64 ;;
  *) echo "dev-ctl: unknown subcommand '$sub' (try: up down logs list supervise)" >&2; exit 64 ;;
esac
