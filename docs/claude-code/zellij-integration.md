# Claude Code + Zellij 統合

> Zellij のタブ名を Claude Code の状態に連動させ、複数プロジェクトの進捗を一目で把握する。

## 課題

Claude Code を複数タブで並行実行していると、どのタブが処理中でどのタブが完了したか分からない。タブを切り替えて確認する手間が生産性を下げていた。

## 解決策

Claude Code の **Hooks** を使い、タブ名に絵文字プレフィックスを自動付与する仕組みを構築した。

| 状態 | タブ表示 | トリガー |
|------|---------|---------|
| 待機中 | `Alchemy` | 初期状態 |
| 思考中 | `🤖 Alchemy` | `UserPromptSubmit` Hook |
| 完了 | `✅ Alchemy` | `Stop` Hook |

さらに、タスク完了時には macOS 通知を送信し、別の作業をしていても見逃さない。

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────┐
│  Zellij                                                 │
│  ┌──────────┬──────────┬──────────┬──────────┐         │
│  │🤖 Alchemy│✅ English │ Widget   │ dotfiles │  ← タブ │
│  └──────────┴──────────┴──────────┴──────────┘         │
│                                                         │
│  ┌─────────────────────────────────────────────┐       │
│  │  Claude Code                                 │       │
│  │  ┌─────────┐   ┌──────────────────┐         │       │
│  │  │ Hooks   │──▶│ zellij-tab-*.sh  │──▶ zellij action rename-tab │
│  │  └─────────┘   └──────────────────┘         │       │
│  │                 ┌──────────────────┐         │       │
│  │                 │ notify-done.sh   │──▶ macOS 通知   │
│  │                 └──────────────────┘         │       │
│  └─────────────────────────────────────────────┘       │
│                                                         │
│  /tmp/zellij-tab-name-{PANE_ID}  ← タブ名キャッシュ      │
│  /tmp/zellij-tab-index-{PANE_ID} ← タブ番号キャッシュ     │
└─────────────────────────────────────────────────────────┘
```

## セットアップ

### 1. Hooks の設定

`~/.claude/settings.json` に以下を追加:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/zellij-tab-thinking.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/zellij-tab-done.sh"
          },
          {
            "type": "command",
            "command": "~/.claude/hooks/notify-done.sh"
          }
        ]
      }
    ]
  }
}
```

### 2. Hook スクリプト

3つのスクリプトを `~/.claude/hooks/` に配置する。

**`zellij-tab-thinking.sh`** — プロンプト送信時にタブ名を `🤖 <name>` に変更:

```bash
#!/usr/bin/env bash
[ "$ZELLIJ" != "0" ] && exit 0

NAME_FILE="/tmp/zellij-tab-name-${ZELLIJ_PANE_ID}"
INDEX_FILE="/tmp/zellij-tab-index-${ZELLIJ_PANE_ID}"

original_name=$(cat "$NAME_FILE" 2>/dev/null)
my_tab_index=$(cat "$INDEX_FILE" 2>/dev/null)
[ -z "$original_name" ] || [ -z "$my_tab_index" ] && exit 0

# 現在フォーカスされているタブのインデックスを取得
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

rm -f "/tmp/zellij-tab-done-${ZELLIJ_PANE_ID}"

# 自分のタブに移動 → リネーム → 元のタブに戻る
if [ "$focused_index" -ne "$my_tab_index" ]; then
  zellij action go-to-tab "$my_tab_index"
  sleep 0.1
  zellij action rename-tab "🤖 $original_name"
  sleep 0.1
  zellij action go-to-tab "$focused_index"
else
  zellij action rename-tab "🤖 $original_name"
fi
```

**`zellij-tab-done.sh`** — 処理完了時にタブ名を `✅ <name>` に変更:

```bash
#!/usr/bin/env bash
[ "$ZELLIJ" != "0" ] && exit 0

NAME_FILE="/tmp/zellij-tab-name-${ZELLIJ_PANE_ID}"
INDEX_FILE="/tmp/zellij-tab-index-${ZELLIJ_PANE_ID}"

original_name=$(cat "$NAME_FILE" 2>/dev/null)
my_tab_index=$(cat "$INDEX_FILE" 2>/dev/null)
[ -z "$original_name" ] || [ -z "$my_tab_index" ] && exit 0

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

rm -f "/tmp/zellij-tab-thinking-${ZELLIJ_PANE_ID}"
touch "/tmp/zellij-tab-done-${ZELLIJ_PANE_ID}"

if [ "$focused_index" -ne "$my_tab_index" ]; then
  zellij action go-to-tab "$my_tab_index"
  sleep 0.1
  zellij action rename-tab "✅ $original_name"
  sleep 0.1
  zellij action go-to-tab "$focused_index"
else
  zellij action rename-tab "✅ $original_name"
fi
```

**`notify-done.sh`** — macOS バナー通知:

```bash
#!/usr/bin/env bash
ROLE=${CLAUDE_ROLE:-$(basename "$PWD")}
@notifyDesktop@ \
  -title "$ROLE" \
  -subtitle "タスク完了" \
  -message "${ROLE}のタスクが完了しました" \
  -sound default \
  -activate com.github.wez.wezterm || true
exit 0
```

`@notifyDesktop@` は `nix/home-manager/default.nix` の `replaceVars` が build 時に
`notify-desktop` の nix store path へ置換する。

> **Note**: 通知の実体は nixpkgs の `terminal-notifier`。 `notify-desktop`
> (`writeShellApplication` + `runtimeInputs`) 経由で呼ぶ。
>
> 2026-07-31 以前は Nix 管理外の手動インストールアプリ
> `/Applications/Utilities/Notifier.app` を各スクリプトに直書きしていたが、
> アプリを消した時点で通知が全滅し、 Stop hook が毎回
> `No such file or directory` を吐く状態になった。 どの `.nix` にも Brewfile にも
> 宣言が無かったため設定からは原因が見えなかった。 **通知手段は必ず
> `notify-desktop` を経由し、 GUI アプリの絶対パスを直書きしないこと。**

### 3. claude-zellij ラッパースクリプト

Zellij レイアウトから Claude Code を起動する際に、タブ名とインデックスをキャッシュするラッパー:

```bash
#!/usr/bin/env bash
# Usage: claude-zellij <tab-name> [claude args...]
tab_name="$1"
shift

if [ "$ZELLIJ" = "0" ] && [ -n "$ZELLIJ_PANE_ID" ] && [ -n "$tab_name" ]; then
  echo "$tab_name" > "/tmp/zellij-tab-name-${ZELLIJ_PANE_ID}"

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
```

`~/.local/bin/claude-zellij` に配置し、実行権限を付与。

### 4. Nix で自動配置（このdotfilesの方法）

Home Manager で全ファイルを自動配置している:

```nix
# Claude Code hooks
home.file.".claude/hooks/notify-done.sh" = {
  source = ./programs/claude-code/notify-done.sh;
  executable = true;
};
home.file.".claude/hooks/zellij-tab-thinking.sh" = {
  source = ./programs/claude-code/zellij-tab-thinking.sh;
  executable = true;
};
home.file.".claude/hooks/zellij-tab-done.sh" = {
  source = ./programs/claude-code/zellij-tab-done.sh;
  executable = true;
};
home.file.".local/bin/claude-zellij" = {
  source = ./programs/claude-code/claude-zellij.sh;
  executable = true;
};
```

## 主要ファイル

| ファイル | 役割 |
|---------|------|
| [`nix/home-manager/programs/claude-code/zellij-tab-thinking.sh`](../../nix/home-manager/programs/claude-code/zellij-tab-thinking.sh) | 思考中マーカー付与 |
| [`nix/home-manager/programs/claude-code/zellij-tab-done.sh`](../../nix/home-manager/programs/claude-code/zellij-tab-done.sh) | 完了マーカー付与 |
| [`nix/home-manager/programs/claude-code/notify-done.sh`](../../nix/home-manager/programs/claude-code/notify-done.sh) | macOS 通知送信 |
| [`nix/home-manager/programs/claude-code/claude-zellij.sh`](../../nix/home-manager/programs/claude-code/claude-zellij.sh) | タブ名キャッシュ + Claude 起動 |
| [`nix/home-manager/programs/zellij/layouts/cockpit.kdl`](../../nix/home-manager/programs/zellij/layouts/cockpit.kdl) | Cockpit レイアウト定義 |

## カスタマイズ

### 絵文字を変更する

`zellij-tab-thinking.sh` と `zellij-tab-done.sh` 内の絵文字を好みに変更:

```bash
# 例: スピナー風
zellij action rename-tab "⏳ $original_name"  # thinking
zellij action rename-tab "✅ $original_name"  # done
```

### 通知の挙動を変更する

`notify-done.sh` で通知のタイトルやサウンドを変更可能。`CLAUDE_ROLE` 環境変数でロール名を指定できる。

### Zellij 以外のターミナルマルチプレクサ

tmux を使う場合は、`zellij action rename-tab` を `tmux rename-window` に置き換えることで同様の仕組みを構築可能。

## Tips & 注意点

- **`/tmp` ファイルの寿命**: macOS 再起動でクリアされる。Zellij セッションを再起動したら `claude-zellij` 経由で起動し直す必要がある
- **タブ移動のちらつき**: Hook 内でタブを一瞬切り替えてリネームするため、タイミングによって画面がちらつくことがある。`sleep 0.1` で緩和しているが完全ではない
- **Zellij のバージョン**: `zellij action dump-layout` と `zellij action query-tab-names` が必要。Zellij 0.40+ を推奨
- **Hook の実行タイミング**: `UserPromptSubmit` はプロンプト送信直後、`Stop` は応答完了後に発火する。ストリーミング中はマーカーが変わらない
