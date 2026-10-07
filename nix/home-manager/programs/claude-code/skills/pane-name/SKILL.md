---
name: pane-name
version: 1.0.0
description: "Zellij: Set pane name based on current work context."
---

# pane-name

Set the current Zellij pane name based on the work context.

## Behavior

1. Analyze the current conversation context, working directory, git branch, and task to determine a **short, descriptive pane name** (1-3 words, max 20 chars).
2. Run the following command to update the pane name:

```bash
zellij action rename-pane "<NEW_NAME>"
```

## Guidelines for naming

- Keep it short: 1-3 words, max 20 characters
- Use the role, project, or feature name
- Examples: `Architect`, `Developer`, `API Tests`, `DB Migration`, `dotfiles`
- If a git branch name is descriptive, use a shortened version of it
- Avoid prefixes like "Working on" or "Task:"
- Use English

## When called without context

If there is not enough context to determine a good name, check:
1. `git branch --show-current` for the current branch name
2. The working directory name (`basename $PWD`)
3. Ask the user what this pane is for
