#!/usr/bin/env bash
# Wrapper script to launch Claude Code inside zellij with tab name tracking
# Usage: claude-zellij <tab-name> [claude args...]
# Saves the tab name and index so hooks can rename the tab on thinking/done

tab_name="$1"
shift

if [ "$ZELLIJ" = "0" ] && [ -n "$ZELLIJ_PANE_ID" ] && [ -n "$tab_name" ]; then
  echo "$tab_name" > "/tmp/zellij-tab-name-${ZELLIJ_PANE_ID}"

  # Find our tab index (1-based) by matching tab name in query-tab-names
  i=1
  while IFS= read -r name; do
    if [ "$name" = "$tab_name" ]; then
      echo "$i" > "/tmp/zellij-tab-index-${ZELLIJ_PANE_ID}"
      break
    fi
    i=$((i + 1))
  done < <(zellij action query-tab-names)
fi

exec claude "$@"
