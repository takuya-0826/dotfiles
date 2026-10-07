#!/usr/bin/env bash
# Mark current zellij tab as "thinking" when user submits a prompt
# Called by Claude Code's UserPromptSubmit hook
[ "$ZELLIJ" != "0" ] && exit 0

NAME_FILE="/tmp/zellij-tab-name-${ZELLIJ_PANE_ID}"
INDEX_FILE="/tmp/zellij-tab-index-${ZELLIJ_PANE_ID}"

original_name=$(cat "$NAME_FILE" 2>/dev/null)
my_tab_index=$(cat "$INDEX_FILE" 2>/dev/null)
[ -z "$original_name" ] || [ -z "$my_tab_index" ] && exit 0

# Find currently focused tab index (1-based)
focused_index=0
i=1
while IFS= read -r line; do
  if echo "$line" | grep -q 'focus=true'; then
    focused_index=$i
    break
  fi
  i=$((i + 1))
done < <(zellij action dump-layout 2>/dev/null | grep "^    tab ")

[ "$focused_index" -eq 0 ] && exit 0

# Remove done marker
rm -f "/tmp/zellij-tab-done-${ZELLIJ_PANE_ID}"

# Go to our tab, rename, go back
if [ "$focused_index" -ne "$my_tab_index" ]; then
  zellij action go-to-tab "$my_tab_index"
  sleep 0.1
  zellij action rename-tab "🤖 $original_name"
  sleep 0.1
  zellij action go-to-tab "$focused_index"
else
  zellij action rename-tab "🤖 $original_name"
fi
