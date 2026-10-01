---
name: pr-conflict-check
version: 1.0.0
description: "Check own open PRs for conflicts and auto-fix when safe (lockfile / trivial). Hands off complex cases to a herdr Claude session."
---

# pr-conflict-check

自分のopen PR（非draft）にコンフリクトがないかチェックし、機械的に直せるもの（lockfile再生成、import順並べ替え等）は無人で解決する。判断が必要なケースは herdr タブで Claude セッションを起動する。

通常は launchd により毎日 8:30 AM に自動実行されるが、このSkillで手動起動もできる。

## 引数

- 引数なし: 自分のopen PR全件をチェック
- `<owner/repo>#<num>`: 単一PRのみ処理（例: `takuya-0826/dotfiles#42`）

## Behavior

シェルスクリプト `~/.local/bin/pr-conflict-check` を呼ぶだけ。

```bash
~/.local/bin/pr-conflict-check "$1"
```

### dry-run

検出と判定までやってログのみ出力（push/Claude起動なし）:

```bash
PR_CONFLICT_DRY_RUN=1 ~/.local/bin/pr-conflict-check
```

### ログ確認

```bash
tail -100 /tmp/pr-conflict-check.log
```

## 内部動作

各PRに対して以下の順で判定:

1. `mergeable=CONFLICTING` でなければスキップ
2. `gh pr update-branch --rebase` (API) を試行
3. ローカルclone を探して `git rebase origin/<base>` を試行
4. conflict が出た場合:
   - **lockfile のみ** (`pnpm-lock.yaml` / `Cargo.lock` / `flake.lock` 等) → 該当パッケージマネージャで再生成 → push
   - **risk list 該当** (migration / .env / terraform / *.sql 等) → 人間委譲（herdr タブ）
   - **それ以外** → Claude に判定依頼。`HIGH` 信頼度のときのみ自動修正、それ以外は人間委譲

詳細は `nix/home-manager/programs/claude-code/pr-conflict-check.sh` および `pr-conflict-resolve.sh` を参照。

## 注意事項

- 未コミット変更がある clone は触らない（人間が作業中の可能性があるため）
- `git push --force-with-lease` を使うので、他人が同じブランチに push していたら失敗する（安全側）
- 人間委譲タブは `Conflict: <repo>#<num>` の名前で herdr に開かれる。`Review: ...` (review-pr) と prefix で住み分け
