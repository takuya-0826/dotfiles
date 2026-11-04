# Harness v2 — 個人開発体制（zj-plan / CODEX_DEVELOPMENT.md の後継）

拓也の開発体制を **全リポ共通の一層**にまとめたもの。2026-08 の zj-plan（zellij 5 ペイン）と、
2026-09 に frank 内に書かれた `docs/CODEX_DEVELOPMENT.md` の作法を統合し、Claude Code の公式部品
（skill / subagent / hooks / goal / worktree）で組み直した。Claude デスクトップでも CLI でも同じ入口。

**正典は `nix/home-manager/programs/claude-code/harness/protocol.md`**（`~/.claude/harness/protocol.md` に symlink）。
本ファイルは構成と導入手順だけ。ルールの本文はそちら。

## 二層

| 層 | 置き場所 | 中身 |
|---|---|---|
| 作法（全リポ共通・この dotfiles） | `~/.claude/harness/`, `~/.claude/skills/{slice,impl,sol-review,adjudicate}`, `~/.claude/agents/{evaluator,evidence-reviewer}` | 役割、発注書、予算、レビュー規律、裁定、リスク階層、証跡、引き継ぎ、計測 |
| リポ固有（各リポ・薄く） | `<repo>/.claude/settings.json`, `.claude/rules/`, `.harness/protocol.md`, `AGENTS.md` の 1 行 | 検証コマンド（Stop hook）、ドメイン規則、高リスクの具体例、承認境界、他人・他ツール向けの宣言 |

リポごとに「開発体制の文書」は持たない。リポに残るのは **コマンド・ドメイン・宣言** の 3 つだけ。

## 構成

```
nix/home-manager/programs/claude-code/
  harness/
    protocol.md                 正典
    templates/
      protocol.repo.md          リポ差分の雛形
      request.md                発注書（AC）の雛形
      progress.md               引き継ぎの雛形
      review-log.jsonl            裁定ログのヘッダ
      settings.python-uv.json   Stop hook / deny の雛形（言語別）
      settings.bun.json
      settings.pnpm.json
      settings.go.json
  skills/
    slice/        実装前に発注書（AC）を書き /goal を登録。高リスクなら止まる
    impl/         worktree で実装 → 証跡 → evaluator / evidence-reviewer / Sol を並列発注 → 裁定 → PR → progress.md
    sol-review/   Codex を spec / guard / attack の 3 観点で read-only 並列。2 巡目は差分のみ
    adjudicate/   指摘を fix / issue / reject に振り分け、review-log.jsonl に記録
  agents/
    evaluator.md          実際に動かして AC を採点
    evidence-reviewer.md  差分 × AC を表で返す

<repo>/
  .claude/settings.json   templates/settings.<lang>.json をコピーして CI と同じコマンドに合わせる
  .claude/rules/          ドメイン規則（既存のまま）
  .harness/
    protocol.md           templates/protocol.repo.md をコピーして埋める
    requests/ reviews/ review-log.jsonl
  progress.md
  AGENTS.md / CLAUDE.md   「開発体制は ~/.claude/harness/protocol.md」の 1 行とリンク
```

## 1 slice の流れ

```
/slice <やりたいこと>
  → .harness/requests/<slug>.md（発注書: 目的・スコープ・機械判定できる AC・検証・入力資料・裁量/要判断・リスク）
  → /goal 登録。高リスクなら拓也に確認して止まる
/impl <slug>
  → worktree → 実装 → CI と同じコマンドを実行して証跡（SHA・コマンド・終了状態・件数・ログ位置）を出す
     （Stop hook が lint/type を強制。通らないとターンを終われない）
  → evaluator（動かす）/ evidence-reviewer（差分×AC）/ /sol-review（Codex 3 観点）を並列発注
  → /adjudicate <slug>（fix / issue / reject → review-log.jsonl）
  → fix を修正 → /sol-review <slug> --pass 2（差分のみ、medium）
  → PR（Testing / Risk / How to revert）→ progress.md
```

拓也が手を動かすのは、`/slice` の入力と、高リスク・P1 対立・AC 変更・承認境界のエスカレーションだけ。

## 導入

### dotfiles（1 回だけ）

`nix/home-manager/default.nix` に次がある（skills の隣）:

```nix
  home.file.".claude/agents"  = { source = ./programs/claude-code/agents;  recursive = true; };
  home.file.".claude/harness" = { source = ./programs/claude-code/harness; recursive = true; };
```

```bash
nix fmt && nix flake check && nix run .#update
ls ~/.claude/harness/protocol.md ~/.claude/skills/slice ~/.claude/agents/
```

### 新しいリポに入れる（5 分）

```bash
cd <repo>
mkdir -p .harness/requests .harness/reviews .claude
cp ~/.claude/harness/templates/protocol.repo.md .harness/protocol.md   # 空欄を埋める
cp ~/.claude/harness/templates/review-log.jsonl  .harness/review-log.jsonl
cp ~/.claude/harness/templates/progress.md     progress.md
cp ~/.claude/harness/templates/settings.<lang>.json .claude/settings.json  # CI と同じコマンドに直す
```

`AGENTS.md`（無ければ `CLAUDE.md`）に 1 行:

> 開発体制は `~/.claude/harness/protocol.md`（dotfiles）。リポ固有の差分は `.harness/protocol.md`。

動作確認: `/permissions` で deny が載る → わざと lint を壊して「終わり」と言わせ Stop hook が戻す → `/agents` に evaluator が見える → `which codex`。

### 既存リポ（frank）

frank の `docs/CODEX_DEVELOPMENT.md` は 2026-11-04 に **ポインタ＋リポ固有**だけに縮めた。作法は正典に吸収済み:
役割表（Astra/Sol/Opus/Terra/Luna → モデル非依存の役割名）、発注書、print モードの予算、証跡、レビューの終了条件、裁定。
G1 の切替凍結・4 波などの**プロジェクト判断**は `v2/G1-TASKS.md` が正。

## zj-plan / CODEX_DEVELOPMENT.md からの変更点

| 以前 | v2 | 理由 |
|---|---|---|
| zellij 5 ペイン（zj-plan） | Claude 1 体 + サブエージェント + worktree | デスクトップ主軸。並列は 3〜4 が実用上限 |
| リポごとに開発体制の文書 | 正典は 1 つ、リポは差分 3 点 | 同じ作法を 2 か所で保守しない |
| protocol を読んで守る | 「必ず」は Stop hook / deny / goal | Claude はガイドラインを読み飛ばせる。ツールは飛ばさない |
| Sol watcher（フォルダ監視） | `/sol-review`（明示起動、3 観点並列、終了コードで完了判定、codex-exec / 公式プラグイン） | 自作ループの保守をなくす。途中読みの誤判定を防ぐ |
| レビュアーは読むだけ | evaluator が実行して採点 | テスト・型チェックが見逃す種類のバグ |
| 指摘は読んで終わり | review-log.jsonl に fix/issue/reject + タグ | Claude 書き × Codex レビューは精度が下がる研究結果あり。当たり率を測る |
| 一律 xhigh | リスク階層で深さと拓也介入を決める | 人間の時間を高リスクに集中 |

継承: 成果物必須、2 パス上限、P0/P1/P2 + file:line、AC 適合で判定、発注書を実装前に、予算上限、証跡、エスカレーション条件、独立レビューの発注は主担当。

## 月 1 の見直し

正典 §9。`review-log.jsonl` の集計コマンドは `/adjudicate` の末尾。

## 参考

- Solving code review at Anthropic — https://claude.dev/blog/solving-code-review-at-anthropic/
- Best practices for Claude Code — https://code.claude.com/docs/en/best-practices
- Harness design for long-running application development — https://www.anthropic.com/engineering/harness-design-long-running-apps
- Codex レビュー艦隊（Zenn） — https://zenn.dev/417/articles/masakazu-claude-code-codex-fleet-20260710
- @beamnxw "Make Opus 5.5 Finish Long Tasks" (2026-10-07)
- 旧実装: `nix/home-manager/programs/zellij/_archived/zj-plan.sh`, `sol-review-watch.sh`、frank `docs/CODEX_DEVELOPMENT.md`（git 履歴 2026-09-09 版）
