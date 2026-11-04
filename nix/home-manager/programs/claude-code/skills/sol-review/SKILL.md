---
name: sol-review
version: 2.0.0
description: "Run Sol (OpenAI Codex) as an independent cross-model reviewer: 3 lenses in parallel via codex exec read-only, P0/P1/P2 with file:line, results in .harness/reviews/. Pass 2 re-reviews only the delta. Use from /impl or standalone."
---

# sol-review — Codex を観点別に並列で走らせる

zj-plan の Sol watcher の後継。フォルダ監視はせず、明示的に起動する。
`codex exec --sandbox read-only` なので Codex はコードを変更できない。判定は Claude が `/adjudicate` で行う。

起動は **素の `codex exec`** に固定する（`~/.local/bin/codex-exec` ラッパーは `-c` や `--output-last-message` を
落とすことがあり、2026-11-05 に委任が止まらない・結果が空になる事故が出た）。公式プラグイン
`/codex:adversarial-review` を使う場合も、依頼文に下の「出力ルール」と「委任禁止」を必ず貼る。

どの経路でも、出力フォーマット（P0/P1/P2 + file:line + 再現条件）と観点分割はこの skill のテンプレを依頼文に貼る。
リポの `.codex/config.toml` に reviewer 用エージェントが定義されていれば（例: frank の `reviewer`）、その developer_instructions を尊重する。

## 引数

- Required: `<slug>`
- Optional: `--pass 2` — 2 巡目。effort を medium に落とし、前回結果と修正差分だけを見せる
- Optional: `--lens <name>` — 1 観点だけ（既定は 3 観点）

独立レビューの発注は**主担当が持つ**。実装担当のセッションから Sol を再起動しない（正典 §4）。

## 観点（lens）

| lens | 役割 | 見ること |
|---|---|---|
| `spec` | 仕様の穴 | AC を満たすか。AC に無い振る舞いの変更。既存ロジックの消失・回帰 |
| `guard` | 設計ガードレール | 境界値、エラーパス、null/空入力、競合、例外処理、公開 API の互換 |
| `attack` | 攻撃者・データ視点 | 入力検証、認可、個人情報、外部送信、秘密情報、ログ漏れ、鍵衝突 |

低リスク slice（request の `risk: low`）は `spec` 1 本だけでよい。

## Behavior

### Step 1: 入力を揃える

```bash
REQ=.harness/requests/<slug>.md
BASE=$(git merge-base main HEAD)
git diff "$BASE"...HEAD --stat
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p .harness/reviews
```

request が無ければ終了。差分が空なら「レビュー対象の差分がありません」と報告して終了。

### Step 2: 依頼文を作る

各 lens について `.harness/reviews/$TS-<slug>-<lens>.request.md` を書く。共通テンプレ:

```markdown
あなたは独立レビュアーの Sol（観点: <lens>）です。コードは変更できません。
対象リポジトリを自分で読み、次の差分を実装レビューしてください。

## 判断基準（必須）
<request の「目的」「スコープ」「AC」をそのまま貼る>

## 差分の範囲
- ベース: <BASE> → HEAD
- 変更ファイル: <git diff --stat の一覧>

## この観点で見ること
<lens 表の「見ること」を貼る>

## 委任禁止
サブエージェント・別担当（architect / researcher / implementer / worker 等）を起動しない。委任が必要だと思っても、
自分で読める範囲で結論を出し、読めなかった箇所は「未検証」と明記する。

## 出力ルール
1. 指摘は P0（致命）/ P1（重要）/ P2（改善）の重大度つき箇条書き。必ず file:line を添える
2. 判定は「コードとして変か」ではなく「AC を満たすか」。AC が不十分ならそれを P1 で指摘する
3. style・命名・好みは書かない。良い点の羅列も不要
4. 各指摘に「根拠（何を読んでそう判断したか）」を 1 行
5. 最後に総評 1 段落。新規 P0/P1 がゼロなら「P0/P1 なし」と明記
```

`--pass 2` のときは追加で:

```markdown
## 2 巡目
前回の指摘と裁定結果:
<.harness/review-log.md の該当行>
修正差分: <前回 HEAD> → HEAD
今回は修正差分だけを検証し、前回指摘が解消されたか（resolved / not resolved）と、新規 P0/P1 のみ報告する。
```

### Step 3: 並列起動（バックグラウンド）

```bash
EFFORT=xhigh   # --pass 2 なら medium
# codex-exec ラッパーは --output-last-message を落とすことがある（2026-11-04 に実測: 結果 .md が空）。
# フラグを通せる場合だけ使い、通せなければ素の codex。どちらでも stdout を tee で .md に残す。
for LENS in spec guard attack; do
  OUT=".harness/reviews/$TS-<slug>-$LENS.md"
  codex exec -C "$PWD" --sandbox read-only --skip-git-repo-check \
    -c model_reasoning_effort="$EFFORT" \
    -c agents.enabled=false \
    -c agents.max_concurrent_threads_per_session=0 \
    --output-last-message "$OUT" \
    "$(cat .harness/reviews/$TS-<slug>-$LENS.request.md)" \
    < /dev/null 2> ".harness/reviews/$TS-<slug>-$LENS.log" | tee ".harness/reviews/$TS-<slug>-$LENS.stdout.md" >/dev/null &
  echo $! >> ".harness/reviews/$TS-<slug>.pids"
done
```

- `-m` は `~/.codex/config.toml` の既定モデルに任せる。固定したいときだけ付ける
- 完了判定は **出力ファイルの存在ではなく、プロセスの終了**で行う（`wait` または pid を確認）。途中で読むと「指摘ゼロ」と誤判定する
- 大きい差分では 10 分を超えることがある。待つ

```bash
while read -r PID; do wait "$PID" 2>/dev/null || true; done < ".harness/reviews/$TS-<slug>.pids"
# 結果 .md が空なら stdout の写しを採用し、先頭にその旨を書く（証跡が消えないようにする）
for LENS in spec guard attack; do
  OUT=".harness/reviews/$TS-<slug>-$LENS.md"; ALT=".harness/reviews/$TS-<slug>-$LENS.stdout.md"
  if [ ! -s "$OUT" ] && [ -s "$ALT" ]; then
    { echo "<!-- --output-last-message が空だったため stdout から採取 -->"; cat "$ALT"; } > "$OUT"
  fi
done
```

### Step 4: 結果を確認して報告

```bash
for LENS in spec guard attack; do
  echo "== $LENS"; grep -E '^\s*[-*]\s*\**P[012]' ".harness/reviews/$TS-<slug>-$LENS.md" | head -20
done
```

報告形式:

```
## sol-review <slug> pass <1|2>
- spec:   P0 x / P1 y / P2 z
- guard:  P0 x / P1 y / P2 z
- attack: P0 x / P1 y / P2 z
- 複数 lens が同じ箇所を指摘: <file:line 一覧>（裁定で重大度を 1 段上げる候補）
- 結果: .harness/reviews/<TS>-<slug>-*.md
- 次: /adjudicate <slug>
```

## コミットするもの / しないもの

- コミットする: `.request.md`（依頼文）と `.md`（結果）
- **コミットしない**: `.log`（stderr）と `.stdout.md`。Codex が中で実行した `git log` 等の出力（作者名・メール）が混ざり、
  PII 検査（credential-leak-scan / pii-bulk-records）でマージが止まる（2026-11-05 frank #1260 で実測）。
  リポの `.gitignore` に `.harness/reviews/*.log` と `.harness/reviews/*.stdout.md` を入れる（テンプレ参照）
- `-c agents.enabled=false` を付けるのは、リポの `.codex/config.toml` でサブエージェントが有効だとレビュアーが委任して
  同じ結論を複数回出すため。レビューは単体で走らせる

## Notes

- `resume` を使うときはフラグを `resume <id>` の**前**に置く（後ろに置くと引数エラー）
- `--sandbox read-only` では Codex はテストを実行できない（EPERM）。テストは Claude 側で回す
- mise 等のシム経由で codex が黙って落ちることがある。`which codex` で実体を確認
- 委任が本当に止まっているかは `.log` に `agent`/`spawn`/`delegat` が無いことで確認する（`grep -iE 'spawn|delegat|subagent' <log>`）
- Codex のレート上限に当たったら、同じ依頼文を Claude のサブエージェント（`evidence-reviewer`）に渡して代替し、ログに `fallback: claude` と残す
