---
name: dev-server
version: 2.0.0
description: "Start / inspect / stop long-running dev servers (Vite, pnpm dev, Next, etc.) inside a zellij tab so they survive. Use this INSTEAD of `!`-backgrounding or run_in_background for any process that must keep running — the Claude Code harness reaps those with SIGTERM (exit 143) after ~20min. Commands: dev-up / dev-logs / dev-down / dev-list. NOTE for Claude: the zellij socket is blocked in the Bash sandbox, so drive dev servers via `~/.claude/scripts/dev-ctl {up|down|logs|list}` (bare dev-up/dev-down fail)."
---

# dev-server

長時間走らせる開発サーバー（`pnpm dev` / Vite / Next / watch 系）を **zellij のタブの中**で
起動する。これらは zellij server の子プロセスになり、Claude Code ハーネスのプロセスツリー
から外れるので **SIGTERM(143) で回収されない**。

## いつ使うか（重要）

**終わらないプロセスは `!` でも `run_in_background` でも起動しない。** それらは
ハーネスの子なので一定時間後に SIGTERM(exit 143) で kill される（Vite の HMR が
正常でも約20分で落ちる事象が確認済み）。dev サーバー・watcher・常駐プロセスは
**必ず `dev-up`** を使うこと。

対象の目安:
- `pnpm dev` / `pnpm dev:proxy` / `vite` / `next dev` / `astro dev` など常駐サーバー
- `tsc --watch` / `vitest --watch` など終わらない watch タスク

`npm test`（一回で終わる）や `pnpm build` のような**有限のコマンドは対象外** —
通常どおり Bash ツールで実行してよい。

## コマンド

> [!IMPORTANT]
> **Claude が起動・停止・監視を叩くときは、素の `dev-up`/`dev-down`/`dev-supervise` ではなく
> 末尾「サンドボックスからの実行について」の `~/.claude/scripts/dev-ctl` 経由**にすること
> （Claude の Bash サンドボックスは zellij の socket を塞ぐ）。以下の素コマンドの例は
> **自分のターミナル向け**。

### 起動

```bash
dev-up [--keep] [--tab|--split] <name> -- <cmd...>
```

- `<name>` は識別名（`[A-Za-z0-9._-]` のみ）。ログ・停止・一覧のキーになる。
- 配置（省略時 `--tab`）:
  - `--tab`   バックグラウンドの zellij セッション **`dev-servers`** に `dev:<name>` タブを作る
    （無ければ自動作成）。作業中の画面のフォーカスは動かない。zellij のクライアントを
    開いていなくても動き続ける（Claude デスクトップアプリで作業していても OK）。
    セッション名は `$DEV_SERVERS_SESSION` で変更可。見るときは `zellij attach dev-servers`。
  - `--split` 今いるペインを下に分割（zellij のペインの中から叩くこと）
  - 旧 `--stack` / `--float` は廃止。`--tab` か `--split` に読み替える。
- `--keep`: **自動再起動の対象**にする（下記「自動再起動」参照）。
- **cwd は今いるディレクトリが使われる。** 別ディレクトリなら `cd` してから呼ぶ。

例:
```bash
cd ~/Projects/wevox/wevox-mono-web/web-progressive
dev-up weboard -- pnpm dev:proxy --filter weboard
```

### 自動再起動（--keep + dev-supervise）

実際の dev サーバー（pnpm/vite/node）は、**起動してしばらくすると何かに SIGTERM(143)
で殺される**ことがある（trivial な sleep ループは殺されないので、犯人は「サーバー」を
狙っている）。対策として自動再起動を用意:

```bash
# 1) 見張り役を一度だけ起動（自分のタブで。trivial ループなので殺されない）
dev-up --tab supervisor -- dev-supervise

# 2) サーバーを --keep 付きで起動 → 死んでも watchdog が復活させる
dev-up --keep --tab weboard -- pnpm dev:proxy --filter weboard
```

- `dev-supervise` は `keep=1` のサーバーを ~15秒毎に監視し、pgid が死んでいたら
  `dev-up` で同じ cwd/コマンドで再起動する（元の argv を厳密に保存して復元）。
- 短時間に連続で死ぬ場合はレート制限（120秒に5回超で 300秒バックオフ）で暴走を防ぐ。
- `dev-down <name>` で keep マーカーごと消えるので、以後は再起動されない。
- `dev-supervise` 自体は多重起動しない（ロックあり）。

### 状態確認（ログ）

タブは見えていないので、**起動できたか / エラーが出ていないかは必ずログで確認する**:

```bash
dev-logs <name>          # 末尾60行（デフォルト）
dev-logs <name> 120      # 末尾120行
```

`dev-logs <name> -f`（follow）は**ブロックするのでヘッドレス／自動実行では使わない**。
起動直後は少し待ってから `dev-logs` を1回読むこと（"ready in xxx ms" 等を確認）。

### 停止

```bash
dev-down <name>
```

プロセスグループごと SIGTERM → **グループ内のプロセスが消えるまで最大8秒待って**、
残っていれば SIGKILL → タブ/ペインを **ID 指定で**閉じる。猶予は `DEV_DOWN_GRACE`（秒）で変えられる。
素の `zellij action close-tab` はフォーカス中のタブを閉じるので使わない。

> [!IMPORTANT]
> **graceful shutdown は途中で切られない。** グループへの TERM でラッパー（`dev-serve-run` の
> bash）が即死すると、zellij がペインごと畳んで後片付け中のサーバーを巻き込む（以前は
> `dev-down` から 0.2 秒以内に消えていた）。いまはラッパーがシグナルを受けても死なず、子の
> 終了を待つ。`dev-down` 側もグループ内のプロセスが消えるまで待つ。TERM は二重に送らない
> （`process.once("SIGTERM", …)` のようなサーバーが 2 発目で即死するため）。

### 一覧

```bash
dev-list                 # 起動済み dev サーバーと alive/dead を表示
```

## 挙動メモ

- 出力は `/tmp/claude/dev-servers/<name>.log` に tee される（タブ表示は維持）。
- state は `/tmp/claude/dev-servers/`。`/tmp/claude` は Claude の Bash サンドボックス・実シェル・
  zellij ペインの**どこからでも書ける安定パス**なので採用している（`$TMPDIR` は文脈ごとに
  変わり dev-up と dev-down で食い違うため不可）。`DEV_SERVERS_DIR` で上書き可。
- zellij の呼び出しはすべて `zj` 経由。zellij の socket は `$TMPDIR` 配下にあり、launchd や
  Claude の Bash は `$TMPDIR` が違うので素の `zellij` では届かない。`zj` が macOS のユーザー
  一時ディレクトリに揃える。
- `dev-up` は呼び出し元シェルの **PATH を転送**する（zellij server が起こすシェルには
  mise/Homebrew の PATH が無いことがあるため）。`pnpm` 等が見つかるシェルで叩くこと。
- タブ（`--tab`）はサーバーが死んでも残り、終了ステータスを読める。後片付けは `dev-down` か
  次の `dev-up` が ID 指定で行う。`--split` のペインは終了で自動的に閉じる。
- 同名が既に alive なら `dev-up` は起動を拒否する。まず `dev-down <name>`。

## サンドボックスからの実行について（Claude 向け・重要）

組織ポリシーの Bash サンドボックスは **unix ソケット接続と他 pid への `kill` を遮断**する。
zellij の制御は socket 経由なので:

| コマンド | Claude のサンドボックス直実行 | 理由 |
|---|---|---|
| `dev-logs` | ✅ そのまま | ただのファイル tail |
| `dev-list` | △ 一覧は出るが **STATE(alive/dead) は当てにならない** | `kill -0` が他 pid で不許可 → 全部 dead に見える |
| `dev-up` / `dev-down` / `supervise` | ❌ 直実行は失敗 | zellij socket 遮断 / kill 遮断 |

**サンドボックスから動かすには `~/.claude/scripts/dev-ctl` を使う。** `~/.claude/**/scripts/`
配下のスクリプトを**パス直接指定**で実行するとサンドボックス外で走る（socket に届く、
`kill` も効く）。`dev-ctl` は dev-* への薄いラッパ:

```bash
~/.claude/scripts/dev-ctl up --keep --tab weboard -- pnpm dev:proxy --filter weboard
~/.claude/scripts/dev-ctl list      # サンドボックス外なので alive/dead が正確
~/.claude/scripts/dev-ctl logs weboard
~/.claude/scripts/dev-ctl down weboard
~/.claude/scripts/dev-ctl supervise
```

注意:
- **行頭が `~/.claude/…/dev-ctl` であること。** `cd … && ~/.claude/…` や `bash ~/.claude/…` の
  ように行頭が別コマンドになると除外が外れてサンドボックス内実行になり失敗する。
- `down` は内部で `kill` するため auto-mode classifier に止められることがある。その場合は
  ユーザーに実シェルでの実行を依頼する。
- **自分のターミナルからは `dev-up`/`dev-down`/`dev-list` を直接**使ってよい（dev-ctl 不要）。
- state パスは共有なので、ユーザーが実シェルで起動したサーバーも Claude から `dev-logs` で読める。
- `--split` は zellij のペインの中からしか使えない。Claude からは `--tab` を使う。
