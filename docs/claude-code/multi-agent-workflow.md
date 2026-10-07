# マルチエージェントワークフロー

> tmux で最大5つの Claude Code インスタンスを管理し、役割分担で並行開発するパターン。

## 課題

1つの Claude Code では、設計調査・実装・テスト・ドキュメントなどのタスクを順番にしか実行できない。大きなタスクでは待ち時間が長くなる。

## 解決策

tmux のペイン分割で複数の Claude Code を起動し、リーダー（人間 or Claude）が各ペインに役割を割り当てて並行作業する。

```
+------------------+------------------+
|     Leader       |    Architect     |
|    (Pane 0)      |    (Pane 1)      |
|   指揮・調整      |   設計・調査      |
+------------------+------------------+
|     Tester       |    Developer     |
|    (Pane 3)      |    (Pane 2)      |
|   品質保証        |   実装・開発      |
+--------+---------+------------------+
|ScrumMas|Document |                  |
|(Pane 5)|(Pane 4) |                  |
| 進行管理 | 文書作成 |                  |
+--------+---------+------------------+
```

## 5つのロール

| ロール | 担当 | 主なタスク |
|-------|------|----------|
| **Architect** | 設計・調査 | コードベース分析、依存関係調査、設計パターン提案 |
| **Developer** | 実装・開発 | 機能実装、バグ修正、リファクタリング、コミット |
| **Tester** | 品質保証 | テスト作成・実行、カバレッジ確認、バグ報告 |
| **Documenter** | 文書作成 | ドキュメント作成・更新、README、API仕様書 |
| **ScrumMaster** | 進行管理 | タスク管理、優先順位、進捗監視、ブロッカー解決 |

## セットアップ

### ペインの作成

```bash
# 1. Architect（水平分割）
tmux splitw -h
tmux select-pane -T "Architect"
tmux send-keys "claude --dangerously-skip-permissions" ENTER

# 2. Developer（垂直分割）
tmux splitw -v
tmux select-pane -T "Developer"
tmux send-keys "claude --dangerously-skip-permissions" ENTER

# 3. Tester（リーダーペインから分割）
tmux select-pane -t 0
tmux splitw -v
tmux select-pane -T "Tester"
tmux send-keys "claude --dangerously-skip-permissions" ENTER

# ペイン構成を確認
tmux list-panes -F "#{pane_index}: #{pane_title}"
```

### 指示の送信

tmux では**指示内容の送信と Enter キーの送信を分ける**必要がある:

```bash
# 指示内容を送信
tmux send-keys -t 1 "package.jsonを確認してください"
# Enter で実行
tmux send-keys -t 1 Enter
```

### 部下からの報告

部下にリーダーペイン（Pane 0）へ報告させる:

```bash
# Architect (Pane 1) にリーダーへの報告を指示
tmux send-keys -t 1 'tmux send-keys -t 0 "# Architectからの報告: 分析完了、問題なし"'
tmux send-keys -t 1 Enter
tmux send-keys -t 1 'tmux send-keys -t 0 Enter'
tmux send-keys -t 1 Enter
```

## 並行作業パターン

### 新機能開発

```bash
# Architect: 設計調査
tmux send-keys -t 1 "認証システムの現在のアーキテクチャを分析してください"
tmux send-keys -t 1 Enter

# Developer: 実装準備
tmux send-keys -t 2 "新機能のための基本的なファイル構造を作成してください"
tmux send-keys -t 2 Enter

# Tester: テスト準備
tmux send-keys -t 3 "新機能用のテストフレームワークを準備してください"
tmux send-keys -t 3 Enter
```

### バグ修正

```bash
# Architect: 原因調査
tmux send-keys -t 1 "エラーログを分析して根本原因を特定してください"
tmux send-keys -t 1 Enter

# Developer: 修正実装（Architectの調査後）
tmux send-keys -t 2 "Architectの報告に基づいてバグ修正を実装してください"
tmux send-keys -t 2 Enter

# Tester: 再現テスト
tmux send-keys -t 3 "バグの再現テストを作成してください"
tmux send-keys -t 3 Enter
```

## 状態確認

```bash
# 全ペインの構成を確認
tmux list-panes -F "#{pane_index}: #{pane_title} (#{pane_width}x#{pane_height})"

# 特定ペインの出力を確認
tmux capture-pane -t 1 -p | tail -20

# 全部下の状態を一括確認
for pane in $(tmux list-panes -F "#{pane_index}" | grep -v "0"); do
  echo "=== ペイン $pane ==="
  tmux capture-pane -t $pane -p | tail -10
  echo ""
done
```

## Gitmojiコミットガイドライン

Developer ロールは以下の gitmoji を使用:

| 絵文字 | コード | 用途 |
|-------|-------|------|
| ✨ | `:sparkles:` | 新機能追加 |
| 🐛 | `:bug:` | バグ修正 |
| ♻️ | `:recycle:` | リファクタリング |
| ⚡️ | `:zap:` | パフォーマンス改善 |
| 🔥 | `:fire:` | コード/ファイル削除 |
| ✅ | `:white_check_mark:` | テスト追加/修正 |
| 🔧 | `:wrench:` | 設定ファイル変更 |
| 📝 | `:memo:` | ドキュメント更新 |

```bash
git commit -m "✨ feat: ユーザー認証機能を追加"
git commit -m "🐛 fix: ログイン時のエラーハンドリングを修正"
```

## 主要ファイル

| ファイル | 役割 |
|---------|------|
| `~/.claude/CLAUDE.md` | マルチエージェント管理手順の定義 |

## カスタマイズ

### ロール数を減らす

小規模なタスクでは Architect + Developer の2ロールで十分:

```bash
tmux splitw -h
tmux select-pane -T "Developer"
tmux send-keys "claude --dangerously-skip-permissions" ENTER
```

### Zellij で使う場合

tmux の代わりに Zellij を使う場合は、`zellij action` コマンドに置き換える:

```bash
# ペイン名の設定
zellij action rename-pane "Architect"

# コマンドの送信
zellij action write-chars "指示内容"
zellij action write 10  # Enter キー
```

## Tips & 注意点

- **ペイン番号は動的**: 分割順で変わるため、指示前に `tmux list-panes` で確認する
- **Enter の2段階送信**: tmux の仕様で、テキストと Enter は別のコマンドとして送信する必要がある
- **Git の競合**: 複数の Claude が同じファイルを同時編集すると競合する。Developer ロールに実装を集約し、他のロールは読み取り中心にすると安全
- **リソース消費**: Claude Code 5インスタンスは CPU/メモリを大量に消費する。3ロール程度が現実的
- **CLAUDE.md での定義**: この管理パターンは `~/.claude/CLAUDE.md` に記述しており、リーダー役の Claude Code が自動的に参照する
