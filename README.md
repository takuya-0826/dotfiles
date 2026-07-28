# dotfiles

Nix 管理の macOS dotfiles + Claude Code マルチエージェントワークフロー

## ハイライト

- **Zellij + Claude Code 統合** — タブ名が自動で 🤖(思考中) / ✅(完了) に切り替わり、10プロジェクトの並行作業を一目で管理
- **カスタムスキル** — `/renovate`, `/update-pr`, `/worktree-cleanup` など PR ライフサイクルを自動化する6つのスキル
- **日報自動生成** — Git コミット + Claude Code セッションログ + Google Tasks → Notion に自動投稿
- **自作 Rust TUI ツール** — flake input として管理し、dotfiles と一緒にインストール
- **ワンコマンドセットアップ** — `nix run .#update` で CLI ツール、GUI アプリ、macOS 設定、シェル設定すべてを適用

## クイックスタート

```bash
# 1. Nix をインストール
sh <(curl -L https://nixos.org/nix/install)

# 2. リポジトリをクローン
git clone https://github.com/EdV4H/dotfiles ~/dotfiles
cd ~/dotfiles

# 3. 環境を構築
nix run .#update
```

<!-- スクリーンショット: Cockpit レイアウト（後日追加）
![Cockpit Layout](docs/assets/cockpit.png)
-->

## ドキュメント

### Claude Code

| ドキュメント | 内容 |
|------------|------|
| [Zellij 統合](docs/claude-code/zellij-integration.md) | Hooks によるタブステータス連動、Cockpit レイアウト、macOS 通知 |
| [カスタムスキルガイド](docs/claude-code/custom-skills-guide.md) | SKILL.md の書き方 + 6つの自作スキル解説 |
| [日報自動化](docs/claude-code/daily-report-automation.md) | Git + セッションログ + Notion の自動日報パイプライン |
| [PR ワークフロー](docs/claude-code/pr-workflow.md) | PR 作成・更新・Renovate マージ・Worktree クリーンアップ |
| [マルチエージェント](docs/claude-code/multi-agent-workflow.md) | tmux 5ロール管理パターン |

### Nix

| ドキュメント | 内容 |
|------------|------|
| [macOS セットアップ](docs/nix/macos-setup.md) | Nix Flakes + Home Manager + nix-darwin 環境構築 |
| [カスタム Flake Inputs](docs/nix/custom-flake-inputs.md) | 自作 Rust TUI ツールを flake input として管理 |

### ターミナル

| ドキュメント | 内容 |
|------------|------|
| [Zellij レイアウト](docs/terminal/zellij-layouts.md) | Cockpit / Work レイアウトの設計思想と KDL の書き方 |
| [Zsh 生産性設定](docs/terminal/zsh-productivity.md) | エイリアス、vi-mode、fzf/zoxide、カスタム関数 |

## リポジトリ構成

```
dotfiles/
├── flake.nix                          # Flake エントリーポイント
├── flake.lock
├── CLAUDE.md                          # Claude Code プロジェクト設定
├── docs/                              # ドキュメント
│   ├── claude-code/
│   ├── nix/
│   └── terminal/
└── nix/
    ├── home-manager/
    │   ├── default.nix                # ユーザー設定 (パッケージ, セッション変数)
    │   └── programs/
    │       ├── claude-code/           # Hooks, スキル, ラッパースクリプト
    │       │   ├── claude-zellij.sh
    │       │   ├── daily-report.sh
    │       │   ├── notify-done.sh
    │       │   ├── zellij-tab-thinking.sh
    │       │   ├── zellij-tab-done.sh
    │       │   └── skills/
    │       │       ├── daily-report/
    │       │       ├── pane-name/
    │       │       ├── renovate/
    │       │       ├── tab-name/
    │       │       ├── update-pr/
    │       │       └── worktree-cleanup/
    │       ├── neovim/                # Neovim 設定
    │       ├── wezterm/               # WezTerm 設定
    │       ├── zellij/
    │       │   └── layouts/           # Zellij レイアウト (work, cockpit)
    │       └── zsh/                   # Zsh 設定
    └── nix-darwin/
        └── default.nix               # macOS システム設定
```

## 使用ツール

| カテゴリ | ツール |
|---------|-------|
| パッケージ管理 | [Nix](https://nixos.org/) + [Home Manager](https://github.com/nix-community/home-manager) + [nix-darwin](https://github.com/LnL7/nix-darwin) |
| ターミナル | [WezTerm](https://wezfurlong.org/wezterm/) + [Zellij](https://zellij.dev/) |
| エディタ | [Neovim](https://neovim.io/) (nightly) |
| AI | [Claude Code](https://docs.anthropic.com/en/docs/claude-code) + [Gemini CLI](https://github.com/google-gemini/gemini-cli) |
| シェル | Zsh + Oh-my-zsh + fzf + zoxide |
| Git | Git + [GitHub CLI](https://cli.github.com/) + [LazyGit](https://github.com/jesseduffield/lazygit) |

## コマンドリファレンス

```bash
# 環境全体の更新
nix run .#update

# Home Manager のみ更新
nix run nixpkgs#home-manager -- switch --flake .#myHomeConfig

# nix-darwin のみ更新
sudo darwin-rebuild switch --flake .#ATR-LAP-OSX-TAKUYA-MATSUMOTO

# Nix ファイルのフォーマット
nix fmt

# Flake の検証
nix flake check
```

## ライセンス

MIT
