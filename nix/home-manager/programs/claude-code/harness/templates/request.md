---
slug: <slug>
risk: low | mid | high
effort: xhigh      # 1 巡目。2 巡目は medium
created: YYYY-MM-DD
base_sha: <git rev-parse main>
---

## 目的
<1〜3 文。誰の何が変わるか>

## スコープ
- 触るファイル・モジュール:
- 触らない:

## AC（受け入れ条件 — 機械判定できる形）
- [ ] AC-1: `<コマンド>` を実行すると `<期待出力>` になる
- [ ] AC-2: テスト `<test名>` が通る
- [ ] AC-3: 既存の `<振る舞い>` が変わらない（回帰なし）

## 検証方法と証跡の返却先
- コマンド:
- 証跡: `.harness/reviews/<ts>-<slug>-*.md`、PR 本文の Testing 欄

## 入力資料
- 仕様 / rules / 既決事項:

## 実装者裁量 / 要判断
- 裁量:
- 要判断（あれば止まる）:

## 評価の観点（Sol / evaluator に渡す）
- spec（仕様の穴）:
- guard（設計ガードレール）:
- attack（攻撃者・データ）:
