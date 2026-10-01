#!/usr/bin/env bash
# Print the tab_id of the herdr tab whose label matches EXACTLY.
#
# usage: herdr-tab-id <label>
#   stdout: the tab_id (e.g. "w1:t3") — nothing if no tab matches
#   exit:   0 if found, 1 if not found, 2 on usage error
#
# Why a helper: several scripts (close-conflict-tab, close-merged-review-tab,
# review-pr, pr-conflict-resolve) need "find the tab called X". herdr's CLI
# returns the raw socket-API envelope, so the jq path is `.result.tabs[]` —
# not the bare array a `list --json` would give. Keeping that one detail in one
# place means a herdr schema change is a one-file fix.
#
# Session selection follows the herdr CLI itself: it uses $HERDR_SESSION when
# set (which it is inside any herdr pane), otherwise the default session.
set -uo pipefail

LABEL="${1:-}"
if [ -z "$LABEL" ]; then
  echo "usage: $(basename "$0") <label>" >&2
  exit 2
fi

_find() { jq -r --arg n "$LABEL" 'first(.result.tabs[]? | select(.label == $n) | .tab_id) // empty' 2>/dev/null; }

# Try the default listing first (one call, covers the common case), then scan each
# workspace — a tab may live in a dedicated space (dev-up's "dev-servers", review
# tabs' "reviews") that the default listing does not include.
TAB_ID=$(herdr tab list 2>/dev/null | _find)
if [ -z "$TAB_ID" ]; then
  for ws in $(herdr workspace list 2>/dev/null | jq -r '.result.workspaces[]?.workspace_id' 2>/dev/null); do
    TAB_ID=$(herdr tab list --workspace "$ws" 2>/dev/null | _find)
    [ -n "$TAB_ID" ] && break
  done
fi

[ -z "$TAB_ID" ] && exit 1
echo "$TAB_ID"
