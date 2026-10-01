---
name: dev-server
version: 1.1.0
description: "Start / inspect / stop long-running dev servers (Vite, pnpm dev, Next, etc.) inside a herdr pane or tab so they survive. Use this INSTEAD of `!`-backgrounding or run_in_background for any process that must keep running — the Claude Code harness reaps those with SIGTERM (exit 143) after ~20min. Commands: dev-up / dev-logs / dev-down / dev-list. NOTE for Claude: the herdr socket is blocked in the Bash sandbox, so drive dev servers via `~/.claude/scripts/dev-ctl {up|down|logs|list}` (bare dev-up/dev-down fail with EPERM)."
---

# dev-server

長時間走らせる開発サーバー（`pnpm dev` / Vite / Next / watch 系）を **herdr の
ペイン・タブの中**で起動する。これらは herdr server の子プロセスになり、Claude
Code ハーネスのプロセスツリーから外れるので **SIGTERM(143) で回収されない**。

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

前提: **herdr サーバーが動いていること**。socket は `~/.config/herdr/` 配下の固定パス
（`$TMPDIR` に依存しない）。launchd や実シェルからは同じサーバーに届くが、
**Claude の Bash サンドボックスからは herdr socket が塞がれている**（2026-08-19 実測。
以前は例外だったが外れた）。

> [!IMPORTANT]
> **Claude が起動・停止・監視を叩くときは、素の `dev-up`/`dev-down`/`dev-supervise` ではなく
> 末尾「サンドボックスからの実行について」の `~/.claude/scripts/dev-ctl` 経由**にすること
> （素の herdr 系は socket EPERM で失敗する）。以下の素コマンドの例は**実シェル（herdr ペイン）向け**。

起動・停止はどちらもペイン/タブ ID 指定なので focus 奪取や誤爆は起きない。

### 起動

```bash
dev-up [--keep] [--tab|--split] <name> -- <cmd...>
```

- `<name>` は識別名（`[A-Za-z0-9._-]` のみ）。ログ・停止・一覧のキーになる。
- 配置（省略時 `--tab`）:
  - `--tab`   `dev:<name>` という新規タブ。`--no-focus` で作るのでフォーカスは動かない（デフォルト）
  - `--split` 今いるペインを下に分割（`$HERDR_PANE_ID` が要るのでペインの中から叩くこと）
  - herdr にスタックペイン／フローティングペインは無い。旧 `--stack` / `--float` は
    エラーになるので `--tab` か `--split` に読み替える。
- `--keep`: **自動再起動の対象**にする（下記「自動再起動」参照）。
- **cwd は今いるディレクトリが使われる。** 別ディレクトリなら `cd` してから呼ぶ。

### 自動再起動（--keep + dev-supervise）

実際の dev サーバー（pnpm/vite/node）は、**起動してしばらくすると何かに SIGTERM(143)
で殺される**ことがある（tab/split いずれでも起こりうる。trivial な sleep ループは
殺されないので、犯人は「サーバー」を狙っている）。対策として自動再起動を用意:

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
- `dev-supervise` 自体は多重起動しない（ロックあり）。稀に見張り役が消えたら再度
  `dev-up --tab supervisor -- dev-supervise` を叩く。

例:
```bash
cd ~/Projects/wevox/wevox-mono-web/web-progressive
dev-up weboard -- pnpm dev:proxy --filter weboard
```

### 状態確認（ログ）

ペインは画面外かもしれないので、**起動できたか / エラーが出ていないかは必ずログで確認する**:

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
残っていれば SIGKILL → ペイン/タブを ID 指定で除去する。猶予は `DEV_DOWN_GRACE`（秒）で変えられる。

> [!IMPORTANT]
> **graceful shutdown は途中で切られない。** 以前は `dev-down` から**0.2秒以内**にサーバーが
> 消えていた（SIGKILL より前に、である）。グループへの TERM でラッパー（`dev-serve-run` の
> bash）が即死し、それにつられて zellij がペインごと畳んで、後片付け中のサーバーを
> 巻き込んでいた。ログの flush・プールの close・停止イベントの記録が残らない。
> （herdr のペインはコマンドが終わっても畳まれないので、この巻き添えは構造的に消えた。
> ただしラッパーがグループ kill を生き延びる必要は変わらない。）
>
> いまはラッパーがシグナルを受けても死なず、子の終了を待つ。`dev-down` 側もリーダーの
> pid ではなく**グループ内のプロセス**が消えるまで待つ。TERM は二重に送らない——
> 一度しか受けないハンドラ（Node の `process.once("SIGTERM", …)`）を持つサーバーが
> 2発目で即死するため。

### 一覧

```bash
dev-list                 # 起動済み dev サーバーと alive/dead を表示
```

## 挙動メモ

- 出力は `/tmp/claude/dev-servers/<name>.log` に tee される（ペイン表示は維持）。
- state は `/tmp/claude/dev-servers/`（再起動で消える＝サーバーもどうせ止まるので整合）。
  `/tmp/claude` は Claude Code の Bash サンドボックス・実シェル・herdr ペインの
  **どこからでも書ける安定パス**なので採用している（`$TMPDIR` は文脈ごとに変わり
  dev-up と dev-down で食い違うため不可）。`DEV_SERVERS_DIR` で上書き可。
- herdr のペインは login shell で起動するので PATH は基本そのまま通るが、`dev-up` は
  念のため呼び出し元シェルの **PATH を明示的に転送**している（mise/Homebrew/corepack の
  `pnpm`/`node` 等の解決を `terminal.shell_mode` 設定に依存させないため）。
  なので `dev-up` は **対象ツールが `pnpm` などを見つけられるシェル**で叩くこと。
- `pane run` はペインのシェルに**コマンドを打ち込む**方式（zellij の `new-pane -- cmd` の
  ような argv 直渡しが無い）。`dev-up` 側で `printf %q` 済みなので利用者は意識しなくてよい。
- **`--tab` のサーバーは専用 workspace `dev-servers` にまとまる**（無ければ自動作成）。
  作業スペースが dev サーバーのタブで散らからない。ラベルは `$DEV_SERVERS_WORKSPACE` で変更可。
- 同名が既に alive なら `dev-up` は起動を拒否する。まず `dev-down <name>`。
- **herdr のタブ/ペインはコマンドが終了しても消えない**（`--close-on-exit` 相当が無い）。
  後片付けは `dev-down` が記録済み ID で行うので、放置せず `dev-down` すること。

## サンドボックスからの実行について（Claude 向け・重要）

組織ポリシーの Bash サンドボックスは **unix ソケット接続と他 pid への `kill` を遮断**する
（時期によって緩和されることがあるが、原則こちら）。herdr の制御は socket 経由なので:

| コマンド | Claude のサンドボックス直実行 | 理由 |
|---|---|---|
| `dev-logs` | ✅ そのまま | ただのファイル tail |
| `dev-list` | △ 一覧は出るが **STATE(alive/dead) は当てにならない** | `kill -0` が他 pid で不許可 → 全部 dead に見える |
| `dev-up` / `dev-down` / `supervise` | ❌ 直実行は失敗 | `herdr …` = unix socket 遮断 / kill 遮断 |

**サンドボックスから herdr を触る系を動かすには `~/.claude/scripts/dev-ctl` を使う。**
`~/.claude/**/scripts/` 配下のスクリプトを**パス直接指定**で実行するとサンドボックス外で走る
（＝ herdr socket に届く、`ps`/`kill` も効く）。`dev-ctl` は dev-* への薄いラッパ:

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
- **実シェル（herdr ペイン）からは `dev-up`/`dev-down`/`dev-list` を直接**使ってよい（dev-ctl 不要）。
- state パスは共有なので、ユーザーが実シェルで起動したサーバーも Claude から `dev-logs` で読める。
- `--split` は `$HERDR_PANE_ID` が要る（herdr ペイン内から）。無ければ `--tab`。
