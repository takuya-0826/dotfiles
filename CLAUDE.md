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
  
- **nix/home-manager/programs/neovim/**: Neovim configuration (currently minimal)

## Key Configuration Details

### User Information
- Username: `takuyamatsumoto`
- Home directory: `/Users/takuyamatsumoto`
- System: `aarch64-darwin`
- Machine name: `ATR-LAP-OSX-TAKUYA-MATSUMOTO`

### Installed Development Tools
- Version control: git, gh, lazygit
- Terminal: wezterm, tmux
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

- The Neovim configuration references a symlink to `${pwd}/conf` which points to `~/dotfiles-nix/home-manager/console/neovim/conf` - this path may need adjustment
- WezTerm is installed via Homebrew's nightly cask, not Nix
- The configuration includes both Nix packages and Homebrew casks for different types of applications

### Zellij タブ閉じる時の注意

**重要**: zellij タブを閉じる時は **絶対に `zellij action close-tab` を呼ばない**。`close-tab` は「今フォーカスのあるタブ」を閉じるコマンドであり、ユーザーが見ているタブを巻き込んで破壊する事故が頻発している。必ず `close-tab-by-id` を ID 指定で使うこと。

事故パターン: `go-to-tab-name "<name>"` は対象タブが存在しないと**フォーカスを移動せず黙って失敗** (exit code 2)。続けて `close-tab` を実行すると**現在フォーカスのタブが閉じてしまう**。 `2>/dev/null` でエラーを潰していると気付かず、別のタブを破壊する。

```bash
# ❌ 絶対 NG: tab name が存在しないと、フォーカスのある別のタブを閉じてしまう
zellij action go-to-tab-name "$TAB_NAME" 2>/dev/null
zellij action close-tab

# ❌ 絶対 NG: フォーカスのあるタブをそのまま閉じる (今いるタブが消える)
zellij action close-tab

# ✅ 安全: ID で明示的に指定 (なければ noop)
TAB_ID=$(zellij action list-tabs --json | jq -r --arg n "$TAB_NAME" '.[] | select(.name == $n) | .tab_id')
[ -n "$TAB_ID" ] && zellij action close-tab-by-id "$TAB_ID"
```

専用ヘルパー (使えるなら必ずこっちを優先):

- `close-conflict-tab <repo> <num>` → `Conflict: <repo>#<num>` タブを閉じる (pr-conflict-check 用)
- `close-merged-review-tab <num> <repo>` → `Review: <repo>#<num>` タブを閉じる (gh-review-watcher 用)

参考実装: `nix/home-manager/programs/claude-code/close-conflict-tab.sh`, `close-merged-review-tab.sh`

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
git clone https://github.com/EdV4H/dotfiles ~/dotfiles
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
```

### 引き継がないもの

`node_modules` / build 成果物 / `~/.local/share/mise/` (ランタイム実体) / Claude Desktop の state / aws/gcloud の認証 SQLite — すべて新 PC で再構築 (token 失効リスクと keychain 結合の複雑さを避けるため)。