---
name: adjudicate
version: 2.0.0
description: "Adjudicate review findings (Sol/Codex, evaluator, evidence-reviewer) into do-now / issue / reject per protocol.md, and append tags to .harness/review-log.md so reviewer noise can be measured. Use after /sol-review."
---

# adjudicate — 指摘を裁定して記録する

レビュアーの指摘を**そのまま採用しない**。正典 `~/.claude/harness/protocol.md` §5 の裁定表に従って 3 つに振り分け、ログに残す。
レビュアーが「通過 / 未検証 / 残るリスク」を分けて返している場合、未検証は欠陥ではなく `issue`（追跡先つき）か evaluator への再依頼にする。
ログは「どのレビュアーの、どの観点が当たるか」を測るための唯一のデータなので、必ず書く。

## 引数

- Required: `<slug>`

## Behavior

### Step 1: 結果を集める

```bash
ls -t .harness/reviews/*-<slug>-*.md | grep -v request | head -10
```

最新の pass の Sol 3 本（spec / guard / attack）、evaluator の表、evidence-reviewer の表を読む。
`.pids` のプロセスがまだ生きていれば待つ（途中で読まない）。

### Step 2: 指摘を 1 件ずつ裁定する

正典 §5 の表:

| 振り分け | 条件 |
|---|---|
| **fix**（今やる） | P0。または 2 つ以上のレビュアー／lens が独立に同じ箇所を指摘した P1 |
| **issue**（Issue 化） | P1 のうち slice の AC 外。P2 全部 |
| **reject**（棄却） | 意図的な設計、AC と矛盾、根拠が示されていない、既存コード由来で slice と無関係 |

判断に迷う P1 は **fix** に寄せる。ただし「P1 級の見解対立」（レビュアー同士、またはレビュアーと AC が矛盾）は拓也へ。

### Step 3: ログに追記する

`.harness/review-log.md` の Markdown 表に 1 指摘 1 行で追記する（無ければヘッダ付きで作る）。組織ルールで `.tsv/.csv/.jsonl/.ndjson` が禁止のリポがあるため Markdown。列は `ts | slug | pass | reviewer | lens | severity | file_line | decision | tag | note`。

- `reviewer`: `sol` / `evaluator` / `evidence`
- `decision`: `fix` / `issue` / `reject`
- `tag`（記事の分類）: `fixed`（直した）/ `wrong`（誤指摘）/ `intended`（意図的な動作）/ `minor`（重要でない）
  - fix → 修正後に `fixed`
  - reject → `wrong` か `intended`
  - issue → `minor`

```bash
python3 - <<'PY'
import datetime,os
p=".harness/review-log.md"
cols=["ts","slug","pass","reviewer","lens","severity","file_line","decision","tag","note"]
row={"ts":datetime.datetime.now().isoformat(timespec="minutes"),"slug":"<slug>","pass":1,
     "reviewer":"<sol|evaluator|evidence>","lens":"<spec|guard|attack|->","severity":"<P0|P1|P2>",
     "file_line":"<path:line>","decision":"<fix|issue|reject>","tag":"<fixed|wrong|intended|minor>","note":"<短い理由>"}
cell=lambda v: str(v).replace("|","/").replace("\n"," ")
new=not os.path.exists(p) or os.path.getsize(p)==0
with open(p,"a") as f:
    if new: f.write("| "+" | ".join(cols)+" |\n|"+"---|"*len(cols)+"\n")
    f.write("| "+" | ".join(cell(row[c]) for c in cols)+" |\n")
PY
```

### Step 4: Issue を切る

`decision=issue` のものは 1 件ずつ `gh issue create` する。タイトルに `[<slug>] P<n>` を付け、本文に file:line と根拠を貼る。

### Step 5: 報告

```
## adjudicate <slug> pass <n>
- fix:    N 件（<file:line> ...）
- issue:  N 件（#..., #...）
- reject: N 件
- 複数レビュアー一致: N 件
- エスカレーション: <あれば内容。無ければ「なし」>
- 次: fix を修正 → /sol-review <slug> --pass 2
```

## 月 1 の集計（拓也 or 定期タスク）

```bash
python3 - <<'PY'
import collections
n=collections.Counter(); w=collections.Counter(); cols=None
for l in open(".harness/review-log.md"):
    l=l.strip()
    if not l.startswith("|") or set(l)<=set("|- "): continue
    c=[x.strip() for x in l.strip("|").split("|")]
    if cols is None: cols=c; continue
    r=dict(zip(cols,c)); k=f'{r["reviewer"]}/{r["lens"]}'; n[k]+=1; w[k]+= r["tag"]=="wrong"
for k in sorted(n): print(f"{k:20s} n={n[k]:3d} wrong={w[k]:3d} ({100*w[k]/n[k]:.0f}%)")
PY
```

`wrong` 率が 40% を超える reviewer/lens は、依頼文を直すか、その観点を Claude 側に寄せる。
0 件しか出ない lens は外す（Anthropic の harness 設計：不要になった部品は外す）。

## Notes

- レビュアーが「即修正」と書いていても、裁定表に当たらなければ fix にしない（ガードレール系は過剰になりやすい）
- 既存コード由来の指摘（slice の差分と無関係）は reject + note に `pre-existing`。月 1 の全体レビューで拾う
