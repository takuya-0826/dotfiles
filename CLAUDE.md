# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Nix-based dotfiles configuration repository that manages system configuration for macOS (aarch64-darwin) using:
- **Nix Flakes** for reproducible system configuration
- **Home Manager** for user-level package and configuration management
- **nix-darwin** for macOS system-level configuration
- **Homebrew** integration for GUI applications

## Essential Commands

### System Updates
```bash
# Update entire system configuration (flake + home-manager + nix-darwin)
nix run .#update

# Update only home-manager configuration
nix run nixpkgs#home-manager -- switch --flake .#myHomeConfig

# Update only nix-darwin configuration
sudo darwin-rebuild switch --flake .#ATR-LAP-OSX-TAKUYA-MATSUMOTO

# Update flake inputs
nix flake update
```

### Development Commands
```bash
# Format Nix files
nix fmt

# Check flake configuration
nix flake check

# Build without switching
nix build .#homeConfigurations.myHomeConfig.activationPackage
nix build .#darwinConfigurations.ATR-LAP-OSX-TAKUYA-MATSUMOTO.system
```

## Architecture

### Flake Structure
- **flake.nix**: Main entry point defining:
  - Home Manager configuration: `myHomeConfig`
  - Darwin configuration: `ATR-LAP-OSX-TAKUYA-MATSUMOTO`
  - Update script app: `.#update`
  - Formatter using treefmt-nix

### Configuration Modules
- **nix/home-manager/default.nix**: User-level configuration
  - Shell configuration (zsh with aliases)
  - Development tools (git, gh, tmux, neovim, etc.)
  - Session variables (Google Cloud project, etc.)
  - mise (node / npm グローバルツール管理)
  
- **nix/nix-darwin/default.nix**: System-level macOS configuration
  - Nix daemon settings
  - macOS defaults (Finder, Dock)
  - Homebrew casks for GUI applications
  - Font packages

### Program Configurations
- **nix/home-manager/programs/wezterm/**: Terminal emulator configuration
  - Lua-based configuration with custom keybindings
  - Everforest Dark color scheme
  
- **nix/home-manager/programs/neovim/**: Neovim configuration (軽量な編集用。 AI/IDE 系は Claude Desktop に任せ、 LSP・補完・treesitter・telescope 程度に絞っている)

## Key Configuration Details

### User Information
- Username: `takuyamatsumoto`
- Home directory: `/Users/takuyamatsumoto`
- System: `aarch64-darwin`
- Machine name: `ATR-LAP-OSX-TAKUYA-MATSUMOTO`

### Installed Development Tools
- Version control: git, gh, lazygit
- Terminal: wezterm, zellij (terminal multiplexer)
- Editor: neovim
- Search: ripgrep
- Utilities: curl, jq, docker
- AI tools: claude-code, gemini-cli, amazon-q-cli
- Node.js: mise (node / ni / ccusage をグローバル管理)
- Cloud: google-cloud-sdk

### Shell Aliases
- `lg` → `lazygit`
- `la` → `ls -a`
- `ccd` → `claude --dangerously-skip-permissions`
- `cc` → `claude --remote-control`
- `cl` → `clear`

## Working with this Configuration

When modifying configurations:
1. Edit the appropriate `.nix` file
2. Run `nix fmt` to ensure proper formatting
3. Test changes with `nix flake check`
4. Apply changes using the update commands above

Note: The configuration uses experimental Nix features (flakes) which must be enabled in the Nix settings.

## Common Tasks

### Adding new packages
- For user packages: Edit `home.packages` in `nix/home-manager/default.nix`
- For GUI apps: Add to `homebrew.casks` in `nix/nix-darwin/default.nix`
- After adding, run `nix run .#update` to apply

### Modifying shell aliases
- Edit `programs.zsh.shellAliases` in `nix/home-manager/default.nix`
- Changes take effect after running the update command

### Adding new program configurations
- Create a new file in `nix/home-manager/programs/<program>/default.nix`
- Import it in `nix/home-manager/default.nix`
- See wezterm configuration as an example

## Compact Instructions

When compacting, preserve the following:
- Current task context and goals
- File paths being edited and their purpose
- Test results and error messages
- Decisions already made and their rationale
- Key variable names and function signatures being worked on

## Important Notes

- WezTerm is installed via Homebrew's nightly cask, not Nix
- The configuration includes both Nix packages and Homebrew casks for different types of applications

### zellij (ターミナルマルチプレクサ)

2026-08 に herdr へ移行し、 2026-10 に zellij へ戻した (開発の主軸を Claude デスクトップアプリに
移したため)。 herdr 期の改良 (ID 指定の後片付け、 自動化用の専用スペース、 preflight) は zellij 版に
移植済み。 herdr に戻すときは `feat/back-to-zellij` の移行コミットを revert する。

スクリプトから触るときの要点:

- **zellij は必ず `zj` 経由で呼ぶ。** zellij の socket は `$TMPDIR/zellij-<uid>/` にあり、 launchd や
  Claude Code の Bash は `$TMPDIR` が違うので素の `zellij` では "There is no active session!" になる。
  `zj` が macOS のユーザー一時ディレクトリ (`getconf DARWIN_USER_TEMP_DIR`) に揃える。
- **タブ/ペインの操作は必ず ID 指定。** 素の `zellij action close-tab` / `close-pane` はフォーカス中の
  ものを閉じる事故を起こす。 `close-tab-by-id <id>` / `close-pane --pane-id <id>` を使う。
  `new-tab` は新タブの id (数字) を、 `new-pane` は `terminal_<n>` を stdout に返す。
- **自動化のタブはバックグラウンドセッションに作る** (herdr の workspace の代わり)。
  `dev-servers` (dev-up) / `reviews` (zellij の外から開いたレビュー) / `pr-conflicts` (コンフリクト委譲)。
  `zj ensure <name>` が無ければ作る。 見るときは `zellij attach <name>`。 クライアントを開いていなくても
  中のコマンドは動き続ける。
- `zellij action list-tabs --json` は `[{"tab_id":…,"name":…,…}]` の配列 (エンベロープ無し)。
- コマンド付きのタブは `new-tab --name … --cwd … -- <cmd>`。 `--close-on-exit` で終了時に閉じる。
- **Claude Code の Bash からは socket が塞がれている。** Claude が zellij を触るときは `~/.claude/scripts/`
  配下の hatch 経由 (dev サーバーは `dev-ctl`) にする。 → サンドボックスの項を見よ。

専用ヘルパー (使えるなら必ずこっちを優先):

- `zj [-s SESSION] action …` / `zj find-tab <name>` (全セッション横断で `<session>\t<tab_id>`) /
  `zj ensure <SESSION>` / `zj preflight [caller]` (届かない理由を出して exit 69)
- `close-conflict-tab <repo> <num>` → `Conflict: <repo>#<num>` タブを閉じる (pr-conflict-check 用)
- `close-merged-review-tab <num> <repo>` → `Review: <repo>#<num>` タブを閉じる (gh-review-watcher 用)
- `open-review-tab <url> <num> <repo>` → `Review: <repo>#<num>` タブを開いて review-pr を走らせる
- `fire-review-routine <url> <num> <repo>` → ルーティン「PRレビュー一次請け」を /fire API で起動 (gh-review-watcher の
  on_new_pr 既定。 トークンはキーチェーン `claude-routine-pr-review`。 失敗時は open-review-tab にフォールバック)
- レイアウト: `zellij --layout work` / `zellij --layout cockpit` (`nix/home-manager/programs/zellij/layouts/`)

参考実装: `nix/home-manager/programs/zellij/zj.sh`, `nix/home-manager/programs/claude-code/close-conflict-tab.sh`

## サンドボックス (組織ポリシー / Claude Code の Bash)

会社端末の Claude Code は Bash コマンドを OS 層のサンドボックス内で実行する (managed hook
`/Library/Application Support/ClaudeCode/`)。セッション冒頭の `<sandbox-note>` が最新の正。
**設定は時期により変わる** (2026-08 に数回変更あり)。以下は 2026-08-19 時点の要点。

### 何が塞がれる / 何が例外か
- **塞がれる**: unix ソケット接続 (nix daemon 等)、Mach IPC (pbcopy/pbpaste)、TCP listen、
  **localhost の bind も connect も** (127.0.0.1 への直 curl/python は EPERM)、許可外ホスト通信、
  ワークスペース・`/tmp/claude`・`$TMPDIR` **以外への書込**。
- **例外 (サンドボックス外で走る)**: **行頭が** `git` / `gh` / `gcloud` / `bq` / `crit` 等の
  許可コマンド、または `~/.claude/scripts/` 配下のスクリプトを**パス直接指定**で実行したとき。
  判定はコマンド文字列のパターン一致。
  (zellij / herdr のようなマルチプレクサは例外に入っていない — socket が EPERM になる。
  最新の正はセッション冒頭の `<sandbox-note>`。)
- **`bash script.sh` で包む・`&&`連結・パイプ・for/while に
  入れると例外が外れてサンドボックス内に落ちる**ので、許可コマンドは行頭の単発で打つ
  (作業ディレクトリは `cd &&` でなく Bash ツールの実行ディレクトリ指定で合わせる)。
- **zellij の socket は Claude の Bash から塞がれている** → 素の `zellij` / `zj` / `dev-up` / `dev-down` 等は
  失敗する (`dev-up` は `zj preflight` で exit 69)。
  **dev サーバーは `~/.claude/scripts/dev-ctl {up|down|logs|list}` 経由で叩く** (scripts 例外で
  サンドボックス外＝socket に届く。 実測で up→down 成功)。 `dev-list` は socket 不使用だが `kill -0` が
  EPERM られ生きてるサーバも "dead" と誤表示するので、 状態確認も `dev-ctl list` を使う。
  (launchd から起動される zellij スクリプト群はサンドボックス外なので従来どおり動く。)

### localhost サーバと話す
`~/.claude/scripts/lo-fetch <port> [path] [method]` を使う (127.0.0.1 固定の正規中継)。
自分でサーバを bind したり直接 localhost に curl しない。サーバは人間がターミナルで起動する。

### git worktree での作業
- **作成・一覧は可** (`git worktree` は例外なので使える。 マルチプレクサの worktree 機能は socket 経由なので
  Claude の Bash からは今は塞がれている)。
- ただし**書込許可ルートは Bash ツールの作業ディレクトリに固定**され、コマンド内 `cd` では移らない。
  → **worktree の中で type-check/lint/build すると EPERM で死ぬ** (書込ルート外だから)。
- **中で作業できる worktree は次のいずれか**:
  1. リポジトリの **`.claude/worktrees/` 配下** (常時書込可。ここに作るのが正規)
  2. **`EnterWorktree` ツール**で作る (.claude/worktrees 配下・書込ルートが追従)
  3. **サブエージェント** (Agent の `cwd=その worktree`、または `isolation:"worktree"`) に検証を投げる
- 既存の兄弟ディレクトリ worktree (`<repo>-<name>` 等) はメイン Bash から検証不可 →
  サブエージェント(cwd=worktree)に投げる / `.claude/worktrees/` へ移設 / その worktree でセッション起動。
- **モノレポはリポジトリルートをセッション cwd に** (turbo 等が兄弟パッケージに書けず失敗するため)。
- **worktree に `.env` 等のクレデンシャルが無いとき、 Claude が自分でコピー/リンクしない** (Read の deny
  ルールは symlink の先も見るので読めないうえ、 クレデンシャルを動かす操作は権限ポリシーに触れうる)。
  - Claude が作る worktree (`EnterWorktree` / `--worktree` / `isolation:"worktree"`) には、 メインチェックアウト
    直下の `.worktreeinclude` (gitignore 記法) に書いた gitignore 済みファイルを Claude Code 本体がコピーする。
    無ければ「`.worktreeinclude` に `.env` 等を書いて」とユーザーに頼む (会社 repo に commit したくなければ
    `.git/info/exclude` に `.worktreeinclude` を足せばよい)。
  - 人間が作る worktree は `wt add <git worktree add の引数>` (同じ `.worktreeinclude` を読んで symlink を貼る。
    `.worktreeinclude` が無ければ `**/.env` `**/.env.*` `**/.envrc` `**/.dev.vars`。 `WT_COPY=1` でコピー)。
    既存の worktree には `wt seed [dir]`。 実装は `nix/home-manager/programs/git/wt.sh`。

### やってはいけない / 依頼に回すこと
- **迂回しない**: chmod・サンドボックス外での再実行・別フラグ脱出等でサンドボックスを破らない。
  正規ツールへの乗り換えは可 (Web取得は WebFetch、外部連携は MCP、`ax`/curl でシェルアウトしない)。
- **git 書込みの別経路禁止**: ローカルの commit/push/PR が塞がれても MCP/GitHub API で作り直さない。
  `index.lock: Operation not permitted` は**ロック競合でなく書込ルート不一致**。正規は「書込ルートを
  対象に合わせてローカルで同じ操作を回す」(worktree の項) だけ。無理なら失敗内容をそのまま報告して止まる。
- **mise install / mise use 等の導入系は不可** (承認を通しても OS 層は外れない)。読取(`mise ls`)・
  導入済み実行は可。導入が要るときはユーザーにターミナル実行を依頼する。
- 塞がれた操作で正規の代替が無ければ、**失敗コマンドと理由をそのまま報告して指示待ち** (黙って
  「できません」と見送らない — 許可か不明ならまず試すか人間に確認)。

## PC 移行手順

新しい Mac に乗り換えるときの手順。 dotfiles (nix) で OS / dotfile / launchd / skills は再現できるので、 ここでは **nix 管理外の state** (gitignored な `.env` / `.npmrc` / SSH 鍵 / cache 等) と **クローン済み repo** の引き継ぎだけを扱う。

実装は `nix/home-manager/programs/claude-code/migration/` に 3 スクリプトあり、 `~/.local/bin/` に登録済み:

- `migration-export` — gitignored secret + `~/.ssh` 等を tar.gz に固める
- `migration-list-repos` — `~/Projects/` 配下の repo path と remote URL を TSV 化
- `migration-restore` — 新 PC で展開 + 再 clone

### 旧 PC 側

```bash
# dry-run でまず中身を確認
MIGRATION_DRY_RUN=1 ~/.local/bin/migration-export

# 実行
~/.local/bin/migration-export
~/.local/bin/migration-list-repos

# 生成物 (~/migration-bundle-<ts>.{tar.gz,sha256,repos.txt}) を AirDrop / scp で新 PC へ
```

### 新 PC 側

```bash
# 1. nix セットアップ
curl -fsSL https://install.determinate.systems/nix | sh -s -- install

# 2. dotfiles を clone (gh CLI 未認証段階なので https 経由)
git clone https://github.com/takuya-0826/dotfiles ~/dotfiles
cd ~/dotfiles

# 2.5. 会社端末で Netskope (SWG) が常駐している場合、 cache.nixos.org の HTTPS を
# MITM するため nix-daemon が cache から binary を取れない → local build 嵐になる。
# Netskope CA を nix の信頼バンドルに追加してから nix run .#update する。
#   (Netskope クライアントが無い PC ではこの step はスキップ可)
if pgrep -f "Netskope Client.app" >/dev/null; then
  security find-certificate -a -p -c "ca.atrae.goskope.com" \
    /Library/Keychains/System.keychain | sudo tee /etc/ssl/atrae-netskope-ca.pem
  # nix-darwin の security.pki.certificateFiles で永続化される。 ただし初回 bootstrap は
  # まだ反映前なので、 nix-daemon 用のバンドルに手動 append:
  sudo bash -c '
    cp /etc/static/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt.tmp
    cat /etc/ssl/atrae-netskope-ca.pem >> /etc/ssl/certs/ca-certificates.crt.tmp
    mv /etc/ssl/certs/ca-certificates.crt.tmp /etc/ssl/certs/ca-certificates.crt
  '
  sudo launchctl kickstart -k system/org.nixos.nix-daemon
fi

nix run .#update

# 3. bundle を展開して repo を再 clone (gh auth は先に通すこと)
gh auth login
~/.local/bin/migration-restore ~/Downloads/migration-bundle-*.tar.gz ~/Downloads/migration-bundle-*.repos.txt

# 4. 他の認証
aws sso login   # profile ごとに
gcloud auth login && gcloud auth application-default login
docker login

# 5. node 環境 (mise が global=latest で自動管理。特定バージョンが要る時のみ)
mise use -g node@<version>

# 6. Kiro CLI を使う場合 (退避された zprofile を戻す)
[ -f ~/.zprofile.kiro.bak ] && mv ~/.zprofile ~/.zprofile.hm.bak && mv ~/.zprofile.kiro.bak ~/.zprofile

# 7. poke-mate を使う場合: skill の symlink を貼る
#    (poke-mate repo 内に skill 本体があり、 ~/.claude/skills から symlink で参照する設計)
if [ -d ~/Projects/poke-mate ]; then
  ln -sfn ~/Projects/poke-mate/skills/build-party-with-me ~/.claude/skills/poke-mate-build-party-with-me
  ln -sfn ~/Projects/poke-mate/skills/review-party ~/.claude/skills/poke-mate-review-party
fi

# 8. zellij: 作業用レイアウトで起動 (自動化用の dev-servers / reviews / pr-conflicts
#    セッションは必要になったときに自動で作られる)
zellij --layout work
```

### 引き継がないもの

`node_modules` / build 成果物 / `~/.local/share/mise/` (ランタイム実体) / Claude Desktop の state / aws/gcloud の認証 SQLite — すべて新 PC で再構築 (token 失効リスクと keychain 結合の複雑さを避けるため)。