---
name: impl
version: 2.0.0
description: "Implement a slice in a worktree against its AC, then run verification, Sol (Codex) review, evaluator, and adjudication. Use after /slice."
---

# impl — slice を実装して、検証・レビュー・裁定まで回す

`.harness/requests/<slug>.md` の AC に対して実装する。Stop hook（lint/test）が通らないとターンは終われない。

## 引数

- Required: `<slug>` — `/slice` が作った request の slug

## Behavior

### Step 1: 正典・リポ差分・契約を読む

```bash
cat ~/.claude/harness/protocol.md
cat .harness/protocol.md 2>/dev/null
cat .harness/requests/<slug>.md
```

無人実行（print モード・定期タスク）なら、正典 §3 の予算（`--max-turns` / 時間 / API 換算額）を起動側が指定していることを確認する。指定が無ければ小修正は 50 ターン・900 秒・5 ドル相当で自分を区切る。**上限到達を成功と読み替えない**。

request が無ければ「先に /slice を実行してください」と報告して終了。

### Step 2: worktree で作業する

既に worktree 内（`git rev-parse --git-common-dir` が `.git` でない）ならそのまま。そうでなければ worktree を作って移る。

```bash
git worktree add -b feat/<slug> ../<repo>-<slug> main
```

worktree に `.env` 等が必要なら `.worktreeinclude` に従う（CLAUDE.md 参照）。

### Step 3: 実装

- AC の順に実装し、AC ごとにテストを書く
- スコープ外のファイルは触らない。触る必要が出たら止まって拓也に上げる
- 「完了した」と言う前に、必ず実行して **証跡**（対象 SHA・コマンド・終了状態・要点と件数・ログの場所）を会話に出す。コマンドはリポ差分 `.harness/protocol.md` の「検証コマンド」（CI と同じもの）を使う:

```bash
git rev-parse HEAD
<リポの lint / type / test コマンド>
```

### Step 4: 評価と独立レビューを発注する

3 つを並列で起動する。**自分では判定しない**。

1. **evaluator**（サブエージェント `evaluator`）
   渡すもの: request のパス、起動コマンド、AC。「実際に実行して AC ごとに pass/fail と出力を表で返す」
2. **evidence-reviewer**（サブエージェント `evidence-reviewer`）
   渡すもの: `git diff main...HEAD`、request のパス。「AC への適合を claim / verdict / evidence / correction の表で返す。style は見ない」
3. **Sol**（Codex）
   `/sol-review <slug>` を実行する（観点別に 3 本並列、結果は `.harness/reviews/`）

### Step 5: 裁定

全部の結果が揃ったら `/adjudicate <slug>` を実行する。
「今やる」に振り分けられた指摘だけ修正し、修正後は **2 巡目**として Sol を `effort: medium` で差分のみ再実行する（`/sol-review <slug> --pass 2`）。

2 巡目で新規 P0/P1 が出たら、修正せず Step 7 へ（拓也へエスカレーション）。

### Step 6: PR

```bash
git add -A && git commit -m "<gitmoji> <slug>: <要約>"
git push -u origin feat/<slug>
gh pr create --fill --body "$(cat <<'EOF'
## Slice
.harness/requests/<slug>.md

## Testing
<実行したコマンドと結果の要点>

## Risk
<low|mid|high> — <理由>

## How to revert
<revert 手順 or フラグ名>

## Review
Sol: <P0/P1/P2 件数と裁定> / evaluator: <pass/fail 件数> / evidence-reviewer: <verified/incorrect/unresolved 件数>
EOF
)"
```

高リスク階層なら `--draft` で作り、拓也のレビューを待つ。

### Step 7: progress.md を更新して終わる

`~/.claude/harness/templates/progress.md` の形。履歴やログ全文は書かず、判断・未確認・SHA・証跡・次の一手だけ。

```markdown
Task: <slug>
Outputs: PR #<n>, .harness/reviews/<ts>-<slug>-*.md
Completed: AC-1..N / Sol 2 pass / evaluator pass
Decisions: <確定した判断とその根拠>
Open issues: <Issue 化した P1/P2、未解決>
Next action: <1 つ>
Ask: <拓也に決めてほしいこと。無ければ「なし」>
```

最後に出力パスと検証結果を会話に出す（goal の判定材料）。

## Notes

- 「テストが通った」だけは不可。コマンドと出力を出す。
- レビュアーの指摘を全部直さない。裁定は `/adjudicate` の表に従う。
- 2 パスで終わらないものは slice の切り方が悪い。拓也に戻す。
