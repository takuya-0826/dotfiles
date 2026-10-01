# herdr ワークスペース設計

> プロジェクトごとに Claude Code + シェルペインを組み立て、以降は永続セッションに任せる。

## 課題

毎朝の開発開始時に、複数プロジェクトのディレクトリを開き、Claude Code を起動し、dev サーバーを立ち上げるのに時間がかかっていた。

## 解決策

zellij では KDL レイアウトファイル（`work.kdl` / `cockpit.kdl`）を書いて `zellij --layout work` で
毎回組み立てていた。**herdr には宣言的なレイアウトファイルが無い**代わりに、
server が workspace / tab / pane を保持し続ける:

- `prefix+q` で detach しても server は走り続け、`herdr` で元の状態に戻る
- server が落ちても workspace / tab / pane / cwd / フォーカスは snapshot から復元される
  （プロセス自体は新しいシェルとして起動し直し）
- `[session] resume_agents_on_restore = true` なら claude ペインは会話セッションごと復帰する

つまり日常的にはレイアウトを「起動」しない。組むのは**新しい PC** か**閉じてしまったとき**だけで、
そのための再現手段が `herdr-bootstrap` スクリプト。

## 構造

herdr は zellij より 1 階層深い:

```
session ─┬─ workspace "Work" ─┬─ tab "Alchemy" ─┬─ pane (claude)
         │                    │                 └─ pane (nr dev)
         │                    ├─ tab "English" ─── pane (claude)
         │                    └─ ...
         └─ workspace "Cockpit" ─ ...
```

サイドバーは workspace 単位でエージェントの状態を束ねて表示する
（→ [Claude Code + herdr 統合](../claude-code/herdr-integration.md)）。

## ワークスペース一覧

### work — メインの開発ワークスペース

6 タブ構成 (2026-10-01、松本の PJ 構成)。各プロジェクトに Claude Code を割り当て:

```
┌──────────────────────────────────────────────────────────────┐
│ Frank │ tiki-taka │ uSketch │ Forms │ brain │ dotfiles        │
├──────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────┐         │
│  │  claude -c                                     │  ← 入力済み・未実行
│  ├────────────────────────────────────────────────┤         │
│  │  pnpm dev                                      │  ← 同上（split）
│  └────────────────────────────────────────────────┘         │
└──────────────────────────────────────────────────────────────┘
```

**特徴**:
- コマンドは `herdr pane send-text` で**打ち込むだけ**（改行を送らない）。
  旧レイアウトの `start_suspended true` と同じで、Enter を押したときに初めて起動する
- 状態表示は herdr のサイドバーが持つので、`claude-zellij` のようなラッパーは不要
- `-c` フラグで会話を継続

**タブ構成**:

| タブ名 | プロジェクト | ペイン構成 | 位置づけ |
|-------|------------|----------|---------|
| Frank | Atrae/frank | Claude + `python -m frank.main` (:8080) | 確定 |
| tiki-taka | LightSuccess | Claude | 確定 |
| uSketch | Atrae/usketch | Claude + `pnpm dev` | 確定 |
| Forms | wevox-mono-web/web-progressive | Claude + BFF `pnpm dev` (:3333) + `pnpm dev --filter forms` (:3017) | 2026-10 完了まで |
| brain | brain | Claude | 常設 (生メモの中継地) |
| dotfiles | dotfiles | Claude | 常設 |

外したもの: Home (cockpit の scratch で代替) / ATS (新 ATS は wevox-hiring-sandbox へ移行中)。
旧 zellij 版の 8 タブは `nix/home-manager/programs/zellij/_archived/layouts/work.kdl`。

### cockpit — 指揮ワークスペース

複数プロジェクトの Claude Code を横断的に扱う。zellij 版は 1 タブに 4x2 のスタックペインを
敷き詰めていたが、**herdr にスタックペインが無い**ため「1 プロジェクト = 1 タブ、
中に claude ペイン + 作業用シェル」に展開してある（サイドバーが一覧の役割を担う）:

| タブ名 | プロジェクト | ペイン構成 |
|-------|------------|----------|
| Frank | Atrae/frank | Claude (`--remote-control`) + shell |
| tiki-taka | LightSuccess | Claude (`--remote-control`) + shell |
| uSketch | Atrae/usketch | Claude (`--remote-control`) + shell |
| Forms | wevox-mono-web/web-progressive | Claude (`--remote-control`) + shell |
| review | Atrae | `gh-review-watcher` + shell |
| scratch | Atrae | shell x2 |
| dotfiles | dotfiles | Claude (`--remote-control`) + shell |

`--remote-control` 付きで起動するので、外部からプロンプトを送信できる。

## セットアップ

### herdr の自動起動

zsh の initContent で、ターミナル起動時に herdr へ入る:

```bash
if [[ -z "$HERDR_ENV" && -z "$VSCODE_INJECTION" && -o interactive ]]; then
  herdr
fi
```

`$HERDR_ENV` は herdr が管理するペインの中でだけ `1` になるので、これで多重起動を防げる
（herdr 側も `experimental.allow_nested = false` で二重に守っている）。

### ワークスペースを組む

```bash
herdr-bootstrap work
herdr-bootstrap cockpit
```

一度組んだら、あとは herdr の永続セッションに任せる。

### 設定ファイル

`~/.config/herdr/config.toml` を Nix Home Manager で配置している:

```nix
xdg.configFile."herdr/config.toml" = {
  source = ./programs/herdr/config.toml;
};
```

変更を走行中の server に反映するには `herdr server reload-config`（または `prefix+shift+r`）。

## bootstrap スクリプトの書き方

herdr の CLI は socket API の薄いラッパーで、**エンベロープ付き JSON** を返す。

```bash
# workspace を作る（自動で空タブが 1 つ付いてくるので最後に閉じる）
out=$(herdr workspace create --label Work --cwd "$HOME" --no-focus)
ws=$(jq -r '.result.workspace.workspace_id' <<<"$out")
seed=$(jq -r '.result.tab.tab_id' <<<"$out")

# タブを作る。root pane まで返ってくるので pane を引き直さなくてよい
out=$(herdr tab create --workspace "$ws" --label Alchemy --cwd "$HOME/Projects/alchemy" --no-focus)
pane=$(jq -r '.result.root_pane.pane_id' <<<"$out")

# コマンドを「打ち込むだけ」= 旧 start_suspended
herdr pane send-text "$pane" "claude --dangerously-skip-permissions -c"

# 分割（herdr にスタックペインは無い。direction は right / down のみ）
out=$(herdr pane split --pane "$pane" --direction down --cwd "$HOME/Projects/alchemy" --no-focus)
sub=$(jq -r '.result.pane.pane_id' <<<"$out")

herdr tab close "$seed"
```

`--no-focus` を付けると作業中のタブからフォーカスが奪われない。

## 主要ファイル

| ファイル | 役割 |
|---------|------|
| [`nix/home-manager/programs/herdr/bootstrap.sh`](../../nix/home-manager/programs/herdr/bootstrap.sh) | work / cockpit の構築 |
| [`nix/home-manager/programs/herdr/config.toml`](../../nix/home-manager/programs/herdr/config.toml) | herdr 設定 |
| [`nix/home-manager/programs/herdr/herdr-tab-id.sh`](../../nix/home-manager/programs/herdr/herdr-tab-id.sh) | label → tab_id の解決 |

## カスタマイズ

### タブを追加する

`bootstrap.sh` の `build_work()` に 1 行足す:

```bash
tab NewProject "Projects/new-project" $CLAUDE >/dev/null
```

dev サーバー付きなら:

```bash
p=$(tab MyApp "Projects/my-app" $CLAUDE)
below "$p" "Projects/my-app" nr dev >/dev/null
```

## Tips & 注意点

- **コマンドは打ち込むだけで実行しない**（`pane send-text`）。10タブ全てが同時起動すると
  リソースが逼迫するため。実行したいなら `herdr pane run`（Enter まで送る）。
- **スタックペイン / フローティングペインは無い。** split は right / down の 2 方向のみ。
  代わりに `prefix+z` の zoom と、サイドバーからのタブ切り替えを使う。
- **タブ/ペインはコマンドが終了しても消えない**（`--close-on-exit` 相当が無い）。
  自動で開いたタブは明示的に閉じる。
- **cwd**: `--cwd` を省くと `[terminal] new_cwd = "follow"` に従って呼び出し元を引き継ぐ。
  bootstrap では毎回明示している。
- **プロジェクトを増やしすぎない。** サイドバーが一覧の役割を持つので、
  zellij 時代のタブ名絵文字より多くのワークスペースを見渡せるが、それでも server の
  メモリは pane 数に比例する。
