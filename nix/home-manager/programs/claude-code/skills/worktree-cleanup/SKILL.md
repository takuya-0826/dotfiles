---
name: worktree-cleanup
version: 1.0.0
description: "Clean up the current git worktree: commit/stash remaining work, switch back to main repo, and remove the worktree."
---

# worktree-cleanup

現在のworktreeでの作業を完了し、worktreeを削除してメインリポジトリに戻る。

## 引数

- なし（現在のworktreeを対象とする）

## Behavior

### Step 1: 現在の状態を確認

```bash
# worktreeで作業中か確認
git rev-parse --git-common-dir
git worktree list
pwd
```

現在のディレクトリがworktreeでない場合は「worktreeではありません」と報告して終了。

### Step 2: 未コミットの変更を確認

```bash
git status --short
```

未コミットの変更がある場合：
1. 変更内容を表示してユーザーに確認
2. 選択肢を提示:
   - **コミットする**: 変更をコミットしてからクリーンアップ
   - **stashする**: `git stash push -m "worktree-cleanup: <branch-name>"` で退避
   - **破棄する**: ユーザーが明示的に同意した場合のみ `git checkout -- .` で破棄
   - **中止する**: クリーンアップを中止

### Step 3: PRの状態を確認

```bash
BRANCH=$(git branch --show-current)
gh pr view "$BRANCH" --json state,mergeStateStatus,title,number 2>/dev/null
```

- PRがマージ済み → そのまま進む
- PRがオープン → ユーザーに「PRがまだオープンですが続行しますか？」と確認
- PRなし → そのまま進む

### Step 4: メインリポジトリのパスを取得

```bash
# worktreeのメインリポジトリのパスを取得
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
WORKTREE_PATH=$(pwd)
WORKTREE_BRANCH=$(git branch --show-current)
```

### Step 5: メインリポジトリに移動

```bash
cd "$MAIN_REPO"
```

### Step 6: worktreeを削除

```bash
git worktree remove "$WORKTREE_PATH"
```

`--force` が必要な場合はユーザーに確認してから使用。

### Step 7: ブランチの削除

マージ済みのブランチは削除する:

```bash
# ローカルブランチを安全に削除（-d はマージ済みのみ削除）
git branch -d "$WORKTREE_BRANCH" 2>/dev/null
```

`-d` で失敗した場合（未マージ）はユーザーに確認してから `-D` を使うか判断。

リモートブランチ:

```bash
# リモートに残っていれば確認して削除
git ls-remote --heads origin "$WORKTREE_BRANCH"
# ユーザー確認後
git push origin --delete "$WORKTREE_BRANCH"
```

### Step 8: mainを最新に更新

```bash
git checkout main 2>/dev/null || git checkout master
git pull
```

### Step 9: 次の作業用worktreeを作成

ユーザーに「次の作業用にworktreeを作成しますか？」と確認。

作成する場合:

1. ブランチ名を聞く（またはタスク内容から提案する）
2. worktreeを作成:

```bash
NEW_BRANCH="<branch-name>"
WORKTREE_DIR="$MAIN_REPO/.claude/worktrees/$NEW_BRANCH"
git worktree add "$WORKTREE_DIR" -b "$NEW_BRANCH"
```

3. 元のworktreeや元リポジトリに `.env*` ファイルがあればコピー:

```bash
# メインリポジトリの.envファイルをコピー
for envfile in $(find "$MAIN_REPO" -maxdepth 3 -name '.env*' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null); do
  REL_PATH="${envfile#$MAIN_REPO/}"
  TARGET_DIR="$WORKTREE_DIR/$(dirname "$REL_PATH")"
  mkdir -p "$TARGET_DIR"
  cp "$envfile" "$WORKTREE_DIR/$REL_PATH"
done
```

4. 新しいworktreeに移動:

```bash
cd "$WORKTREE_DIR"
```

5. 必要に応じてzellijペイン名を更新:

```bash
zellij action rename-pane "$NEW_BRANCH"
```

作成しない場合はスキップ。

### Step 10: サマリー表示

```
## Worktree Cleanup 完了

- 削除したworktree: <path>
- 削除したブランチ: <branch-name>
- 新しいworktree: <new-path> (<new-branch>) ※作成した場合
- 現在地: <current-path> (<current-branch>)
- 最新コミット: <hash> <message>
```

### Step 11: コンテキスト削減の提案

ユーザーに `/compact` の実行を提案する。worktree-cleanupは作業の区切りなので、前のworktreeでの作業履歴を圧縮する良いタイミング。

例: 「worktreeのクリーンアップが完了しました。作業の区切りなので、`/compact` でコンテキストを圧縮することをお勧めします。」

## 注意事項

- **`git worktree remove` は取り消せない** — 未コミットの変更がある場合は必ずユーザーに確認
- worktree内で別のプロセス（エディタ、サーバーなど）が動いている場合は削除に失敗する可能性がある。その場合はユーザーに報告
- Claude Codeのworktree機能（`/worktree`）で作成されたworktreeも、通常の `git worktree` で作成されたものも同じ手順で処理可能
