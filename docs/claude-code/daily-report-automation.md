# 日報自動生成

> Git コミット + Claude Code セッションログ + Google Tasks を集約して Notion に日報を自動投稿する。

## 課題

毎日の日報作成に 15〜30 分かかっていた。何をやったか思い出すために git log を見たり、Slack を遡ったりする作業が面倒で、記述が雑になりがちだった。

## 解決策

3つのデータソースを自動収集し、Claude Code に日報を書かせて Notion に投稿する仕組みを作った。

```
┌──────────────────┐  ┌────────────────────────┐  ┌──────────────┐
│  Git Activity    │  │ Claude Code Sessions   │  │ Google Tasks │
│  (全リポジトリ)   │  │ (~/.claude/projects/)  │  │  (gws CLI)   │
└────────┬─────────┘  └───────────┬────────────┘  └──────┬───────┘
         │                        │                       │
         ▼                        ▼                       ▼
    ┌─────────────────────────────────────────────────────────┐
    │              daily-report.sh (launchd)                  │
    │              毎日 AM 3:00 自動実行                        │
    └───────────────────────────┬─────────────────────────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │   Claude Code (-p)    │
                    │   Notion MCP で投稿    │
                    └───────────────────────┘
```

## セットアップ

### 1. daily-report.sh スクリプト

`~/.local/bin/daily-report` として配置される。

主な処理:

```bash
# 1. ~/Projects 配下の git リポジトリを自動検出
find "$HOME/Projects" -maxdepth 3 -name .git -type d

# 2. 当日の git log を収集
git log --all \
  --since="$REPORT_DATE 00:00" \
  --until="$(date -v+1d +%Y-%m-%d) 00:00" \
  --author="takuya-0826" --author="takuya.matsumoto@atrae.co.jp" \
  --pretty=format:"- %h %s (%ar)"

# 3. Claude Code セッションログを収集
# ~/.claude/projects/ 内の .jsonl ファイルからユーザー/アシスタントメッセージを抽出
jq -r '
  select(.type == "user" or .type == "assistant") |
  select(.timestamp >= "REPORT_DATE") |
  .message.content[]? | select(.type == "text") |
  (.text | .[0:300])
' "$session_file"

# 4. Claude Code にプロンプトを渡して Notion に投稿
command claude -p --dangerously-skip-permissions "..."
```

### 2. launchd で自動実行

nix-darwin で `launchd.user.agents.daily-report` を定義:

```nix
# nix/nix-darwin/default.nix
launchd.user.agents.daily-report = {
  serviceConfig = {
    ProgramArguments = [
      "/bin/sh" "-c"
      "/Users/takuyamatsumoto/.local/bin/daily-report"
    ];
    StartCalendarInterval = [{ Hour = 3; Minute = 0; }];
    StandardOutPath = "/tmp/daily-report.out.log";
    StandardErrorPath = "/tmp/daily-report.err.log";
  };
};
```

### 3. 手動実行

```bash
# 今日の日報を生成
daily-report

# Claude Code のスキルとしても実行可能
/daily-report
/daily-report 2026-03-26  # 特定日
```

### 4. 必要な外部ツール

| ツール | 用途 | インストール |
|-------|------|------------|
| Claude Code | 日報テキスト生成 + Notion 投稿 | `nix` (home.packages) |
| Notion MCP | Notion API 連携 | Claude Code の MCP 設定 |
| gws (Google Workspace CLI) | Google Tasks 取得 | `nix` (flake input) |
| jq | JSON パース | `nix` (home.packages) |

## 日報のフォーマット

Notion に以下の構造で投稿される:

```markdown
## 📝 本日の活動

### プロジェクト名（コミット数 / セッション数）

**PR・機能名**
- 背景・問題の説明
- 原因分析（バグ修正の場合）
- 解決策・実装内容

## ✅ タスク状況
（Google Tasks の進行中・完了タスク）

## 🤖 Claude Codeとしての学び
- 技術的な発見・気づき
- うまくいったアプローチ
- 改善すべきだった点

## 💡 メモ
（振り返り・特記事項）
```

## 主要ファイル

| ファイル | 役割 |
|---------|------|
| [`nix/home-manager/programs/claude-code/daily-report.sh`](../../nix/home-manager/programs/claude-code/daily-report.sh) | 日報生成スクリプト本体 |
| [`nix/home-manager/programs/claude-code/skills/daily-report/SKILL.md`](../../nix/home-manager/programs/claude-code/skills/daily-report/SKILL.md) | 手動実行用スキル定義 |
| [`nix/nix-darwin/default.nix`](../../nix/nix-darwin/default.nix) | launchd エージェント定義 |

## カスタマイズ

### git author を変更する

`daily-report.sh` 内の `--author` フラグを自分の名前に変更:

```bash
git log --all \
  --author="Your Name" --author="your-github-username" \
  ...
```

### プロジェクトの検出パスを変更する

デフォルトでは `~/Projects`（3階層まで）と `~/dotfiles` を検索。変更する場合:

```bash
# daily-report.sh 内
find "$HOME/Projects" -maxdepth 3 -name .git -type d
# ↓ 例: ~/work 配下も追加
find "$HOME/Projects" "$HOME/work" -maxdepth 3 -name .git -type d
```

### Notion 以外のツールに投稿する

`daily-report.sh` の Claude へのプロンプトを変更すれば、Slack や Google Docs など他のツールにも対応可能。MCP サーバーが対応していれば切り替えは容易。

### 実行時刻を変更する

```nix
StartCalendarInterval = [{ Hour = 18; Minute = 0; }];  # 例: 夕方6時
```

## Tips & 注意点

- **ログの確認**: `/tmp/daily-report.log` で実行結果を確認できる
- **セッションログの容量**: `.jsonl` ファイルは大きくなりがちなので、`.[0:300]` でメッセージを300文字に切り詰めている
- **launchd の制限**: Mac がスリープ中は実行されない。朝 3:00 に設定しているのは、前日の深夜作業も含めるため
- **Claude の `-p` フラグ**: 非対話モードで実行。`--dangerously-skip-permissions` と組み合わせて自動実行に対応
- **既存日報の更新**: 同じ日に2回実行すると、Notion 上の既存ページを `replace_content` で上書きする
