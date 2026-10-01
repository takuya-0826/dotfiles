#!/usr/bin/env bash
# zellij-tab-register <tab-name>
#
# 「このペインはどのタブに属するか」を /tmp に書き出す。Claude Code の hook
# (zellij-tab-thinking.sh / zellij-tab-done.sh) がこれを読んでタブ名を
# 🤖 <name> / ✅ <name> に切り替える。
#
# 元は claude-zellij.sh の中に埋まっていたが、claude-resume-latest からも
# 同じ登録が要るようになったので切り出した (2026-08-11)。
#
# ★ この登録を通らない起動経路では、hook は毎回「ファイルが無い」で黙って
#   終了する。旧 zj-project の 4 レイアウトが `command "claude"` を直接呼んでいた
#   ため、🤖/✅ の切り替えは導入以来ずっと動いていなかった (/tmp/zellij-tab-*
#   が 0 件で確認)。レイアウトから claude を起動するときは必ずこれを通す。

tab_name="${1:-}"

[ -n "$tab_name" ] || exit 0
[ "${ZELLIJ:-}" = "0" ] || exit 0
[ -n "${ZELLIJ_PANE_ID:-}" ] || exit 0

echo "$tab_name" > "/tmp/zellij-tab-name-${ZELLIJ_PANE_ID}"

# タブ index (1 始まり) を名前一致で引く。hook はこれで対象タブを指定する。
i=1
while IFS= read -r name; do
  if [ "$name" = "$tab_name" ]; then
    echo "$i" > "/tmp/zellij-tab-index-${ZELLIJ_PANE_ID}"
    break
  fi
  i=$((i + 1))
done < <(zellij action query-tab-names)

exit 0
