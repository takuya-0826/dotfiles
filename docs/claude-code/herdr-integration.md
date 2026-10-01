# Claude Code + herdr 統合

> 複数プロジェクトで並行して走る Claude Code の状態を、herdr のサイドバーで一目で把握する。

## 課題

Claude Code を複数タブで並行実行していると、どのタブが処理中でどのタブが完了したか分からない。タブを切り替えて確認する手間が生産性を下げていた。

## 解決策

以前は zellij + Claude Code Hooks で、タブ名に `🤖` / `✅` の絵文字プレフィックスを自動付与していた。
**herdr はエージェントの状態を一級市民として扱う**ため、この仕組みは丸ごと不要になった。

| 状態 | サイドバー表示 | 検出元 |
|------|--------------|--------|
| 待機中 | `idle` | herdr のエージェント検出 |
| 処理中 | `working` | 同上 (+ Claude Code integration) |
| 入力待ち | `blocked` | 同上 |

`blocked`（ユーザーの確認待ちで止まっている）は絵文字方式では表現できなかった状態で、
「完了したと思ったら許可を聞かれて止まっていた」を潰せるのが実質的な差分。

## アーキテクチャ

```
┌──────────────────────────────────────────────────────────┐
│  herdr                                                   │
│ ┌────────────┐ ┌───────────────────────────────────────┐ │
│ │ サイドバー  │ │  タブ: Alchemy                        │ │
│ │            │ │ ┌───────────────────────────────────┐ │ │
│ │ ● Alchemy  │ │ │  Claude Code                      │ │ │
│ │   working  │ │ │   │                               │ │ │
│ │ ○ English  │ │ │   ├─ integration hook             │ │ │
│ │   idle     │◀──────┤   (herdr pane report-agent)   │ │ │
│ │ ! Widget   │ │ │   │                               │ │ │
│ │   blocked  │ │ │   └─ notify-done.sh ──▶ macOS 通知 │ │ │
│ └────────────┘ │ └───────────────────────────────────┘ │ │
│                └───────────────────────────────────────┘ │
│  server が state を保持 → detach/reattach しても消えない    │
└──────────────────────────────────────────────────────────┘
```

状態は herdr server が持つので、`/tmp` のマーカーファイルも、タブ番号のキャッシュも要らない。

## セットアップ

### 1. herdr integration を入れる

```bash
herdr integration install claude
herdr integration status
```

`~/.claude/settings.json` に hook が書き込まれる。**これは nix 管理外**なので、
新しい PC では 1 回だけ手動で実行する必要がある（CLAUDE.md の「PC 移行手順」step 8）。

対応エージェントは claude 以外にも codex / copilot / cursor / opencode などがある
（`herdr integration install --help` で一覧）。

### 2. macOS 通知 (任意)

完了時にバナーを出す `notify-done.sh` は herdr 移行後もそのまま使える。
`~/.claude/settings.json` の `Stop` hook に登録する:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/notify-done.sh" }
        ]
      }
    ]
  }
}
```

```bash
#!/usr/bin/env bash
ROLE=${CLAUDE_ROLE:-$(basename "$PWD")}
/Applications/Utilities/Notifier.app/Contents/MacOS/Notifier \
  --type banner \
  --title "$ROLE" \
  --subtitle "タスク完了" \
  --message "${ROLE}のタスクが完了しました" \
  --sound default \
  --messageaction "/usr/bin/open /Applications/WezTerm.app"
```

> **Note**: macOS 通知には [Notifier.app](https://github.com/vjeantet/alerter) が必要です。

herdr 自身も `[ui.toast]` / `[ui.sound]` で通知を出せるので、そちらに寄せてもよい
（既定は `delivery = "off"`）。

### 3. サイドバーの表示項目

`~/.config/herdr/config.toml`（nix 管理: `nix/home-manager/programs/herdr/config.toml`）で
エージェント行の構成を変えられる。この dotfiles では claude だけ端末タイトルも出している:

```toml
[ui.sidebar.agents]
rows = [["state_icon", "workspace", "tab"], ["agent"]]

[ui.sidebar.agents.rows_by_agent]
claude = [["state_icon", "workspace", "tab"], ["terminal_title_stripped"], ["agent"]]
```

## スクリプトから herdr を触る

CLI はすべて socket API の薄いラッパーで、**エンベロープ付き JSON** を返す。

```bash
# タブ一覧 (配列は .result.tabs[] の下)
herdr tab list | jq -r '.result.tabs[] | "\(.tab_id)\t\(.label)"'

# タブを開いてコマンドを走らせる (2 段: create → run)
created=$(herdr tab create --label "Review: repo#123" --cwd ~/Projects/foo --no-focus)
pane=$(printf '%s' "$created" | jq -r '.result.root_pane.pane_id')
herdr pane run "$pane" "review-pr ..."     # Enter まで送る
herdr pane send-text "$pane" "claude -c"   # 打ち込むだけ (旧 start_suspended 相当)

# 閉じるのは必ず ID 指定 (ID 必須なので誤爆しない)
herdr tab close "$tab_id"
herdr pane close "$pane_id"

# 自分のペイン / タブ
echo "$HERDR_PANE_ID $HERDR_TAB_ID $HERDR_WORKSPACE_ID"
```

ヘルパー（このリポジトリで用意しているもの）:

| コマンド | 役割 |
|---------|------|
| `herdr-tab-id <label>` | label 一致のタブ ID を引く（無ければ空 + exit 1） |
| `open-review-tab <url> <num> <repo>` | `Review: <repo>#<num>` タブを開いて review-pr を実行 |
| `close-merged-review-tab <num> <repo>` | 同タブを閉じる（gh-review-watcher の on_remove） |
| `close-conflict-tab <repo> <num>` | `Conflict: <repo>#<num>` タブを閉じる |
| `herdr-bootstrap <work\|cockpit>` | ワークスペースを組み直す |

## 主要ファイル

| ファイル | 役割 |
|---------|------|
| [`nix/home-manager/programs/herdr/config.toml`](../../nix/home-manager/programs/herdr/config.toml) | herdr 設定（テーマ / サイドバー / セッション復帰） |
| [`nix/home-manager/programs/herdr/herdr-tab-id.sh`](../../nix/home-manager/programs/herdr/herdr-tab-id.sh) | label → tab_id の解決 |
| [`nix/home-manager/programs/herdr/bootstrap.sh`](../../nix/home-manager/programs/herdr/bootstrap.sh) | work / cockpit ワークスペースの構築 |
| [`nix/home-manager/programs/claude-code/notify-done.sh`](../../nix/home-manager/programs/claude-code/notify-done.sh) | macOS 通知送信 |
| [`nix/home-manager/programs/claude-code/open-review-tab.sh`](../../nix/home-manager/programs/claude-code/open-review-tab.sh) | レビュータブの起動 |

## Tips & 注意点

- **タブ/ペインはコマンドが終了しても消えない。** zellij の `--close-on-exit` に相当する
  機能が無いので、自動で開いたタブは明示的に閉じる（`close-merged-review-tab` 等）。
- **socket は固定パス** (`~/.config/herdr/[sessions/<name>/]herdr.sock`)。zellij のように
  `$TMPDIR` で見失わないため、launchd からも Claude Code の Bash サンドボックスからも届く。
- **detach しても死なない。** `prefix+q` で抜けても server は走り続け、`herdr` で戻れる。
  server ごと落ちた場合は workspace/tab/pane/cwd が復元される（プロセスは再起動）。
  `[session] resume_agents_on_restore` が true なら claude は会話セッションごと復帰する。
- **`herdr integration install claude` は nix 管理外**。`~/.claude/settings.json` を直接
  書き換えるので、新 PC では手動実行が要る。
- **旧 zellij 構成からの移行時**に消したもの: `claude-zellij` ラッパー、
  `zellij-tab-thinking.sh` / `zellij-tab-done.sh`、`/tmp/zellij-tab-*` マーカー。
  タブ名は `/tab-name` skill が付けるだけになり、状態は herdr が持つ。
