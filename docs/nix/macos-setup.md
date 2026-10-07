# Nix で macOS 環境構築

> Nix Flakes + Home Manager + nix-darwin で macOS の開発環境を宣言的に管理する。

## 課題

新しい Mac のセットアップに半日以上かかっていた。Homebrew でインストールしたツール、シェル設定、macOS の設定変更など、手作業で再現する必要があった。

## 解決策

Nix Flakes を使い、全ての設定を1つの flake.nix で管理。`nix run .#update` 一発で環境を再現できるようにした。

```
flake.nix
├── Home Manager (ユーザー設定)
│   ├── パッケージ (CLI ツール)
│   ├── シェル設定 (zsh)
│   ├── プログラム設定 (neovim, zellij, wezterm)
│   └── ファイル配置 (Claude Code hooks, scripts)
├── nix-darwin (システム設定)
│   ├── macOS defaults (Finder, Dock)
│   ├── Homebrew casks (GUI アプリ)
│   ├── フォント
│   └── launchd エージェント
└── treefmt (フォーマッター)
```

## セットアップ

### 1. Nix のインストール

```bash
sh <(curl -L https://nixos.org/nix/install)
```

### 2. リポジトリのクローン

```bash
git clone https://github.com/takuya-0826/dotfiles ~/dotfiles
cd ~/dotfiles
```

### 3. 環境の構築

```bash
nix run .#update
```

これで以下が実行される:
1. `nix flake update` — flake inputs を最新に更新
2. `home-manager switch` — ユーザー設定を適用
3. `darwin-rebuild switch` — システム設定を適用

### 4. 自動更新

nix-darwin の launchd エージェントで毎朝 9:00 に自動更新が走る:

```nix
launchd.user.agents.nix-auto-update = {
  serviceConfig = {
    ProgramArguments = [ "/bin/sh" "-c" ''
      cd /Users/takuyamatsumoto/dotfiles
      nix flake update
      home-manager switch --flake .#myHomeConfig
      sudo darwin-rebuild switch --flake .#ATR-LAP-OSX-TAKUYA-MATSUMOTO
    '' ];
    StartCalendarInterval = [{ Hour = 9; Minute = 0; }];
  };
};
```

## 管理しているもの

### CLI ツール (Home Manager)

```nix
home.packages = with pkgs; [
  # バージョン管理
  git gh lazygit

  # ターミナル
  tmux zellij

  # エディタ
  # (neovim は programs.neovim で管理)

  # 検索・ファイル操作
  ripgrep fzf fd bat eza zoxide

  # AI ツール
  claude-code gemini-cli amazon-q-cli

  # 開発ツール (node は mise=programs.mise が管理)
  docker jq curl direnv uv

  # データベース
  mysql84 lazysql bruno

  # クラウド
  google-cloud-sdk

  # カスタム flake inputs
  inputs.gws.packages.${pkgs.system}.default           # Google Workspace CLI
  inputs.gh-review-watcher.packages.${pkgs.system}.default  # GitHub レビュー監視
  inputs.port-patrol.packages.${pkgs.system}.default    # ポート監視
];
```

### GUI アプリ (Homebrew casks)

```nix
homebrew.casks = [
  "docker-desktop"
  "wezterm@nightly"
  "raycast"
  "figma"
  "logi-options+"
  "amethyst"      # ウィンドウマネージャー
  "arc"           # ブラウザ
  "claude"        # Claude デスクトップ
];
```

### macOS システム設定

```nix
system.defaults = {
  NSGlobalDomain.AppleShowAllExtensions = true;
  finder = {
    AppleShowAllFiles = true;         # 隠しファイル表示
    AppleShowAllExtensions = true;    # 拡張子表示
  };
  dock = {
    autohide = true;                  # Dock 自動非表示
    show-recents = false;             # 最近使ったアプリ非表示
    orientation = "left";             # Dock を左側に配置
  };
};
```

### フォント

```nix
fonts.packages = with pkgs; [
  hackgen-nf-font    # HackGen Nerd Font (日本語対応)
];
```

## 主要ファイル

| ファイル | 役割 |
|---------|------|
| [`flake.nix`](../../flake.nix) | Flake エントリーポイント |
| [`nix/home-manager/default.nix`](../../nix/home-manager/default.nix) | ユーザー設定 |
| [`nix/nix-darwin/default.nix`](../../nix/nix-darwin/default.nix) | システム設定 |

## カスタマイズ

### パッケージを追加する

**CLI ツール**: `nix/home-manager/default.nix` の `home.packages` に追加:

```nix
home.packages = with pkgs; [
  # 既存のパッケージ...
  htop  # ← 追加
];
```

**GUI アプリ**: `nix/nix-darwin/default.nix` の `homebrew.casks` に追加:

```nix
homebrew.casks = [
  # 既存のアプリ...
  "slack"  # ← 追加
];
```

追加後に `nix run .#update` を実行。

### ユーザー名・マシン名を変更する

`flake.nix` と各設定ファイルの以下を変更:

- `username` — ユーザー名
- `homeDirectory` — ホームディレクトリ
- `darwinConfigurations.<machine-name>` — マシン名
- `system.primaryUser` — システムのプライマリユーザー

### シェルエイリアスの追加

`nix/home-manager/programs/zsh/default.nix` の `shellAliases` に追加:

```nix
shellAliases = {
  # 既存のエイリアス...
  k = "kubectl";  # ← 追加
};
```

## 便利なコマンド

```bash
# 設定のフォーマット
nix fmt

# flake の検証
nix flake check

# ビルドのみ（適用しない）
nix build .#homeConfigurations.myHomeConfig.activationPackage

# flake inputs の更新
nix flake update

# 特定の input のみ更新
nix flake update nixpkgs
```

## Tips & 注意点

- **experimental features**: Nix Flakes は実験的機能。`nix.settings.experimental-features = "nix-command flakes"` が必要
- **Homebrew と Nix の使い分け**: GUI アプリは Homebrew casks、CLI ツールは Nix という方針。Nix で GUI アプリを管理するのは macOS では困難なため
- **WezTerm**: `wezterm@nightly` を Homebrew で管理。Nix パッケージだと macOS の統合が弱い
- **sudo**: `darwin-rebuild switch` には sudo が必要。パスワード入力なしで実行できるよう `security.sudo.extraConfig` を設定済み
- **ビルドに時間がかかる場合**: `awscli2` などのパッケージはテストフェーズが長い。`doCheck = false` オーバーレイで回避可能（現在 awscli2 は無効化中）
