---
name: slice
version: 2.0.0
description: "Cut a slice: write the acceptance criteria (sprint contract) BEFORE implementation, decide risk tier, register /goal. Use when starting a new piece of work in a repo with .harness/protocol.md."
---

# slice — 実装前に契約を結ぶ

正典 `~/.claude/harness/protocol.md` §2「発注書」を実行する。実装はしない。成果物は `.harness/requests/<slug>.md` 1 枚と `/goal` の登録。

## 引数

- Required: `<やりたいこと>` — 自由文（1〜4 文でよい）

## Behavior

### Step 1: 正典・リポ差分・progress.md を読む

```bash
cat ~/.claude/harness/protocol.md          # 正典（判断のルール）
cat .harness/protocol.md 2>/dev/null       # リポ差分（検証コマンド・高リスク例・承認境界）
cat progress.md 2>/dev/null
```

リポ差分が無ければ `~/.claude/harness/templates/protocol.repo.md` をコピーして空欄を拓也に埋めてもらう（止まる）。
リポに独自の開発文書（例: `docs/CODEX_DEVELOPMENT.md`、`AGENTS.md`）があれば、それが指す**コマンドと境界**は従う。作法が正典と食い違っていたら正典を優先し、食い違いを progress.md の Ask に書く。

### Step 2: slug とリスク階層を決める

- slug は英小文字とハイフン（例 `export-csv-filter`）
- リスクは **変更内容** で決める。protocol.md のリスク階層表に照らし、迷ったら 1 段上げる
- 高リスク（認証・個人情報・外部送信・秘密情報・スキーマ・CI・公開 API 破壊）なら、ここで拓也に「高リスクです。進めますか」と 1 行で確認して止まる

### Step 3: 発注書（AC）を書く

`~/.claude/harness/templates/request.md` をコピーして `.harness/requests/<slug>.md` に書く。**各 AC は観測できる結果**（コマンドと期待出力、またはテスト名）にする。`base_sha` に `git rev-parse main` を入れる。小修正は 目的・AC・検証 の 3 行でよい。

```markdown
---
slug: <slug>
risk: low | mid | high
effort: xhigh      # 1 巡目。2 巡目は medium
created: YYYY-MM-DD
---

## 目的
<1〜3 文。誰の何が変わるか>

## スコープ
- 触るファイル・モジュール: ...
- 触らない: ...

## AC（受け入れ条件）
- [ ] AC-1: `<コマンド>` を実行すると `<期待出力>` になる
- [ ] AC-2: テスト `<test名>` が通る
- [ ] AC-3: 既存の `<振る舞い>` が変わらない（回帰なし）

## 評価の観点（Sol / evaluator に渡す）
- 仕様の穴: ...
- 設計ガードレール: ...
- 攻撃者視点 / データ: ...

## 判断を要する点（あれば）
- ...
```

AC が 3 つ未満、または観測できない表現（「正しく動く」など）が残っていたら書き直す。

### Step 4: /goal の文面を出す（登録は拓也）

`/goal` はスラッシュコマンドなので skill の中からは実行できない（2026-11-04 に実測）。
次の 1 行を**そのままコピーできる形**で会話に出し、拓也に貼ってもらう。無人実行（print モード・定期タスク）のときは
起動側のプロンプトにこの文面を含める。

```
/goal <slug>: .harness/requests/<slug>.md の AC がすべて満たされ、.harness/reviews/ に Sol と evaluator の結果があり、新規 P0/P1 がゼロで、progress.md が更新され、出力パスと検証結果が会話に出ている。12 ターンで未達なら blocker を報告して止まる。
```

### Step 5: 報告

```
## slice ready
- request: .harness/requests/<slug>.md
- risk: <tier>
- goal: 上の 1 行を貼ってください（skill からは登録できません）
- 次: /impl <slug>
```

## Notes

- AC は実装中に書き換えない。変えたくなったら拓也に上げる（protocol.md）。
- 1 slice は 1 セッション内で終わる大きさに切る。終わらないなら slice を 2 つにする。
