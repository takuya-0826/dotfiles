#!/usr/bin/env bash
# Claude Code の Stop hook: セッションが応答を終えたらデスクトップ通知する。
#
# 通知手段は notify-desktop (Nix 管理) に集約している。 ここに通知バイナリの
# 絶対パスを書かないこと。 下の呼び出し行のプレースホルダは replaceVars が
# build 時に nix store path へ置換する (default.nix の notifyDesktop を参照)。
# クリック先の WezTerm も nix-darwin の homebrew.casks で宣言済みなので、
# パスではなく bundle id で指す。
ROLE=${CLAUDE_ROLE:-$(basename "$PWD")}
@notifyDesktop@ \
  -title "$ROLE" \
  -subtitle "タスク完了" \
  -message "${ROLE}のタスクが完了しました" \
  -sound default \
  -activate com.github.wez.wezterm || true

# hook の失敗をセッションのエラーとして表面化させない。
exit 0
