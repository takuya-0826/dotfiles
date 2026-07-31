# notify-desktop — macOS デスクトップ通知の共通ヘルパー。
#
# 通知バイナリは Nix (writeShellApplication の runtimeInputs) で宣言されており、
# このスクリプトに絶対パスは一切書かない。
#
# 背景: かつて各スクリプトが /Applications/Utilities/Notifier.app/Contents/MacOS/Notifier
# を直書きしていた。 これは Nix 管理外の手動インストール GUI アプリで、 どの .nix
# にも Brewfile にも宣言が無かった。 そのためアプリが消えた瞬間に通知が全滅し、
# Claude Code の Stop hook が毎回 "No such file or directory" を吐く状態になった
# (しかも「消えている」ことが設定からは分からない)。 通知手段をここ一箇所に集約し、
# 実体を Nix に宣言させることで再発を防ぐ。
#
# 使い方: terminal-notifier のフラグをそのまま渡すパススルー。
#   notify-desktop -title "foo" -subtitle "bar" -message "baz" -sound default
#   notify-desktop ... -activate com.github.wez.wezterm   # クリックで WezTerm を前面化
#
# 保険: 万一 (nix store の GC 等で) 通知バイナリが解決できない場合でも、 呼び出し元
# である Stop hook / launchd ジョブをエラーにしないよう黙って exit 0 する。
# ただしこれはあくまで保険であって、 存在保証の本体は上記の Nix 宣言側にある。

if ! command -v terminal-notifier >/dev/null 2>&1; then
  exit 0
fi

terminal-notifier "$@" || exit 0
