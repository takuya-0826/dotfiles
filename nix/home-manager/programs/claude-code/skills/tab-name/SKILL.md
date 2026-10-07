---
name: tab-name
version: 1.0.0
description: "Zellij: Set tab name based on current work context."
---

# tab-name

Set the current Zellij tab name based on the work context.

## Behavior

1. Analyze the current conversation context, working directory, git branch, and task to determine a **short, descriptive tab name** (1-3 words, max 20 chars).
2. Run the following commands to update the tab name:

```bash
# Set the new tab name
zellij action rename-tab "<NEW_NAME>"

# Update the tab name cache so thinking/done hooks use the correct name
echo "<NEW_NAME>" > /tmp/zellij-tab-name-${ZELLIJ_PANE_ID}
```

## Guidelines for naming

- Keep it short: 1-3 words, max 20 characters
- Use the project or feature name, not generic terms
- Examples: `Auth Refactor`, `API Tests`, `DB Migration`, `CSS Fix`, `dotfiles`
- If a git branch name is descriptive, use a shortened version of it
- Avoid prefixes like "Working on" or "Task:"
- Use English

## When called without context

If there is not enough context to determine a good name, check:
1. `git branch --show-current` for the current branch name
2. The working directory name (`basename $PWD`)
3. Ask the user what they're working on
