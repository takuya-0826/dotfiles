# Claude Code カスタムスキルガイド

> SKILL.md を書くだけで Claude Code にプロジェクト固有のワークフローを教える方法と、6つの自作スキルの解説。

## 課題

Claude Code は汎用的な AI アシスタントだが、チーム固有のワークフロー（PR作成手順、Renovate PR のマージポリシー、日報フォーマットなど）は毎回説明する必要があった。

## 解決策

Claude Code の **Skills** 機能を使い、`SKILL.md` ファイルとしてワークフローを定義。`/skill-name` で呼び出せるようにした。

## スキルの仕組み

### ディレクトリ構造

```
~/.claude/skills/           ← グローバルスキル
  renovate/
    SKILL.md
  update-pr/
    SKILL.md
  worktree-cleanup/
    SKILL.md
  tab-name/
    SKILL.md
  pane-name/
    SKILL.md
  daily-report/
    SKILL.md
```

プロジェクトローカルに置く場合は `.claude/skills/` にも配置可能。

### SKILL.md の構造

```markdown
---
name: skill-name
version: 1.0.0
description: "スキルの一文説明"
---

# skill-name

スキルの概要説明。

## Arguments

- Optional: 引数名 — 説明

## Behavior

### Step 1: タイトル

具体的な手順（コードブロック付き）

### Step 2: タイトル

...

## Notes

- 注意事項
```

**ポイント**:
- frontmatter の `name` がスラッシュコマンド名になる（`/renovate`）
- `## Behavior` セクションにステップバイステップの手順を書く
- bash コードブロックで具体的なコマンドを示す — Claude はこれを実行する
- 条件分岐やエラーハンドリングも自然言語で記述できる

## 自作スキル一覧

### 1. `/renovate` — Renovate PR 一括処理（自動修正つき）

Renovate が作成した依存関係更新 PR を自動で rebase → CI 待機 → squash merge する。CI が落ちた場合は原因を分析してコード修正を試み（最大2回）、修正内容は必ず PR コメントと最終サマリでレポートする。直せなければ GitHub Issue を作成してスキップ。

**使いどころ**: 週末や朝一に溜まった Renovate PR を一括処理

```
/renovate [owner/repo]   # 省略時はカレントの repo
```

主な処理フロー:
1. `gh pr list --author "app/renovate"` で対象 PR を取得
2. 各 PR を順番に処理（並行処理すると rebase 競合が起きるため）
3. `gh pr update-branch --rebase` → `gh pr checks --watch` → `gh pr merge --squash --auto`
4. CI 失敗時は失敗ログから原因を特定し、PR ブランチを checkout して修正 → push → CI 再待機（最大2回）
5. 修正した場合は PR コメント + 最終サマリで必ずレポート
6. 直らなければ `gh issue create` で Issue を作成してスキップ

→ 詳細: [`skills/renovate/SKILL.md`](../../nix/home-manager/programs/claude-code/skills/renovate/SKILL.md)

### 2. `/update-pr` — 既存 PR の更新

作業中の PR に追加変更をコミット・プッシュし、PR の説明も更新する。

**使いどころ**: レビュー指摘対応、追加実装の反映

```
/update-pr          # 現在のブランチの PR を自動検出
/update-pr 42       # PR #42 を指定
```

主な処理:
1. 現在のブランチに紐づく PR を特定
2. 変更を論理単位でコミット分割
3. プッシュ + PR タイトル/説明を必要に応じて更新
4. Copilot レビュー再依頼 + CI 監視

→ 詳細: [`skills/update-pr/SKILL.md`](../../nix/home-manager/programs/claude-code/skills/update-pr/SKILL.md)

### 3. `/worktree-cleanup` — Git Worktree のクリーンアップ

マージ済み or 不要になった worktree を安全に削除し、メインリポジトリに戻る。

**使いどころ**: PR がマージされた後の後片付け

```
/worktree-cleanup
```

主な処理:
1. 未コミット変更の確認（コミット/stash/破棄/中止を選択）
2. PR の状態確認
3. worktree 削除 → ブランチ削除（ローカル+リモート）
4. main を最新に更新
5. オプション: 次の worktree を作成（`.env` ファイルの自動コピー付き）

→ 詳細: [`skills/worktree-cleanup/SKILL.md`](../../nix/home-manager/programs/claude-code/skills/worktree-cleanup/SKILL.md)

### 4. `/tab-name` — Zellij タブ名の設定

作業コンテキストに基づいてタブ名を自動設定する。

```
/tab-name
```

- git ブランチ名、作業内容、ディレクトリ名から短い名前を生成
- `/tmp/zellij-tab-name-*` キャッシュも更新（thinking/done Hook と連携）

→ 詳細: [`skills/tab-name/SKILL.md`](../../nix/home-manager/programs/claude-code/skills/tab-name/SKILL.md)

### 5. `/pane-name` — Zellij ペイン名の設定

マルチペイン構成でペインの役割名を設定する。

```
/pane-name
```

→ 詳細: [`skills/pane-name/SKILL.md`](../../nix/home-manager/programs/claude-code/skills/pane-name/SKILL.md)

### 6. `/daily-report` — 日報自動生成

Git 活動ログ + Claude Code セッションログ + Google Tasks から日報を生成し、Notion に投稿する。

```
/daily-report            # 今日の日報
/daily-report 2026-03-26 # 特定日の日報
```

→ 詳細は [日報自動化ドキュメント](./daily-report-automation.md) を参照

## スキル作成のベストプラクティス

### 1. 具体的なコマンドを書く

```markdown
<!-- 良い例 -->
### Step 1: PR を取得
`​`​`bash
gh pr list --author "app/renovate" --state open --json number,title
`​`​`

<!-- 悪い例 -->
### Step 1: PR を取得
Renovate の PR を確認してください。
```

### 2. エラーハンドリングを自然言語で

```markdown
If `mergeable` is `CONFLICTING`, skip to Step 2e (file issue).
```

Claude は条件分岐を理解して適切に処理する。

### 3. ツール指定は frontmatter ではなく本文で

SKILL.md の frontmatter に `allowed-tools` を書けるが、本文のコードブロックで十分。Claude は `gh` コマンドがあれば Bash ツールを使う。

### 4. バックグラウンド実行の指示

```markdown
Run this command with the Bash tool's `run_in_background` option, then wait for the notification.
```

CI の待機など時間がかかる処理は明示的にバックグラウンド実行を指示する。

### 5. 出力フォーマットを定義する

```markdown
### Step 3: Summary
`​`​`
## Renovate PR Processing Complete
- Merged: N PRs
- Skipped: M PRs (issues filed)
`​`​`
```

## 主要ファイル

| ファイル | 役割 |
|---------|------|
| [`skills/renovate/SKILL.md`](../../nix/home-manager/programs/claude-code/skills/renovate/SKILL.md) | Renovate PR 一括処理 |
| [`skills/update-pr/SKILL.md`](../../nix/home-manager/programs/claude-code/skills/update-pr/SKILL.md) | 既存 PR 更新 |
| [`skills/worktree-cleanup/SKILL.md`](../../nix/home-manager/programs/claude-code/skills/worktree-cleanup/SKILL.md) | Worktree クリーンアップ |
| [`skills/tab-name/SKILL.md`](../../nix/home-manager/programs/claude-code/skills/tab-name/SKILL.md) | タブ名設定 |
| [`skills/pane-name/SKILL.md`](../../nix/home-manager/programs/claude-code/skills/pane-name/SKILL.md) | ペイン名設定 |
| [`skills/daily-report/SKILL.md`](../../nix/home-manager/programs/claude-code/skills/daily-report/SKILL.md) | 日報生成 |

## カスタマイズ

### 自分のスキルを作る

1. `~/.claude/skills/<skill-name>/SKILL.md` を作成
2. frontmatter に `name`, `version`, `description` を記述
3. `## Behavior` に手順を書く
4. Claude Code を再起動すると `/skill-name` で呼び出せる

### プロジェクト固有スキル

リポジトリの `.claude/skills/` に置くと、そのプロジェクトでのみ有効になる。チームで共有したいワークフローはこちらに配置する。

## Tips & 注意点

- **スキルのリロード**: SKILL.md を変更した場合、Claude Code の再起動が必要
- **スキルの競合**: 同名のスキルがグローバルとプロジェクトの両方にある場合、プロジェクト側が優先される
- **デバッグ**: スキルがうまく動かない場合、Claude に「`/skill-name` の SKILL.md を読んで手順を確認して」と依頼すると、どのステップで問題が起きているか特定できる
- **バージョニング**: `version` フィールドを使ってスキルの変更を追跡できるが、Claude 自体はバージョンを参照しない。人間向けのメタデータとして活用
