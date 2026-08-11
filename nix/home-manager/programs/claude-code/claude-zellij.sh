#!/usr/bin/env bash
# Wrapper script to launch Claude Code inside zellij with tab name tracking
# Usage: claude-zellij <tab-name> [claude args...]
# Saves the tab name and index so hooks can rename the tab on thinking/done
#
# 登録の実体は zellij-tab-register に切り出した (2026-08-11)。
# claude-resume-latest --tab からも同じ登録を使うため。

tab_name="$1"
shift

zellij-tab-register "$tab_name"

exec claude "$@"
