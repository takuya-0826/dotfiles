# Zsh 生産性設定

> エイリアス、vi-mode、fzf/zoxide でシェル操作を高速化する。

## 課題

頻繁に使うコマンドが長い。ディレクトリ移動が面倒。コマンドライン編集が非効率。

## 解決策

Nix Home Manager で zsh の設定を宣言的に管理し、エイリアス・キーバインド・プラグインを統合。

## セットアップ

全ての設定は `nix/home-manager/programs/zsh/default.nix` に集約。`nix run .#update` で適用される。

## エイリアス

### Git

```bash
g    → git
gs   → git status
gd   → git diff
gco  → git checkout
gcm  → git commit -m
gp   → git push
gl   → git pull
lg   → lazygit
```

### ナビゲーション

```bash
..   → cd ..
...  → cd ../..
.... → cd ../../..
```

### ディレクトリ一覧 (ls)

```bash
ls   → ls --color=auto
la   → ls -la
ll   → ls -l
lt   → ls -lat
```

### Claude Code

```bash
ccd  → claude --dangerously-skip-permissions
ccdr → claude --dangerously-skip-permissions --remote-control
```

**安全装置**: `claude` コマンド自体はラッパー関数で `--dangerously-skip-permissions` フラグを拒否する:

```bash
function claude() {
  for arg in "$@"; do
    if [[ "$arg" = "--dangerously-skip-permissions" ]]; then
      echo "エラー: '--dangerously-skip-permissions' オプションは無効化されています。" >&2
      return 1
    fi
  done
  command claude "$@"
}
```

`ccd` エイリアスは `command claude` を使うためこのガードを迂回する。意図的に危険モードを使う場合は `ccd` を明示的に使うという設計。

### システム

```bash
cl      → clear
h       → history
hg      → history | grep
update  → cd ~/dotfiles && nix run .#update
rebuild → cd ~/dotfiles && nix run .#update
```

### エディタ

```bash
v   → nvim
vi  → nvim
vim → nvim
```

### 設定ファイルの編集

```bash
zshrc   → nvim ~/.zshrc
zshconf → nvim ~/dotfiles/nix/home-manager/programs/zsh/default.nix
nixconf → nvim ~/dotfiles/flake.nix
```

## Vi モード

```bash
bindkey -v
export KEYTIMEOUT=1
```

**カーソル形状でモード表示**:
- Normal モード: ブロックカーソル (`\e[1 q`)
- Insert モード: ビームカーソル (`\e[5 q`)

**コマンドラインで vim 編集**:
- Normal モードで `v` を押すと、コマンドラインの内容を vim で編集できる

## FZF 連携

```bash
# FZF のキーバインドと補完を読み込み
source ${pkgs.fzf}/share/fzf/key-bindings.zsh
source ${pkgs.fzf}/share/fzf/completion.zsh
```

| キーバインド | 動作 |
|------------|------|
| `Ctrl+R` | 履歴のファジー検索 |
| `Ctrl+T` | ファイルのファジー検索 |
| `Alt+C` | ディレクトリのファジー移動 |
| `**<Tab>` | パス補完のファジー検索 |

## Zoxide（スマートディレクトリ移動）

zoxide はパッケージとしてインストール済み。Oh-my-zsh の `z` プラグインと併用。

```bash
z projects  # ~/Projects に移動（過去の移動履歴から推測）
```

## ディレクトリショートカット

```bash
hash -d dotfiles="$HOME/dotfiles"
hash -d nix="$HOME/dotfiles/nix"
hash -d downloads="$HOME/Downloads"
hash -d projects="$HOME/Projects"
```

使用例:
```bash
cd ~dotfiles    # ~/dotfiles に移動
cd ~projects    # ~/Projects に移動
```

## 便利な関数

### mkcd — ディレクトリ作成 + 移動

```bash
mkcd my-new-project
# mkdir -p my-new-project && cd my-new-project
```

### extract — アーカイブ展開

```bash
extract archive.tar.gz   # 自動で適切なコマンドを選択
extract file.zip
extract data.7z
```

対応フォーマット: `.tar.gz`, `.tar.bz2`, `.bz2`, `.gz`, `.tar`, `.tbz2`, `.tgz`, `.zip`, `.Z`, `.7z`

### backup — ファイルバックアップ

```bash
backup important.conf
# cp important.conf important.conf.bak
```

### find-replace — 一括置換

```bash
find-replace "oldName" "newName"
# カレントディレクトリ以下の全ファイルで置換
```

## Oh-my-zsh プラグイン

```nix
oh-my-zsh = {
  enable = true;
  theme = "robbyrussell";
  plugins = [
    "git"                      # Git エイリアス・補完
    "docker"                   # Docker 補完
    "kubectl"                  # Kubernetes 補完
    "terraform"                # Terraform 補完
    "aws"                      # AWS CLI 補完
    "npm"                      # npm 補完
    "node"                     # Node.js 補完
    "python"                   # Python 補完
    "golang"                   # Go 補完
    "rust"                     # Rust 補完
    "tmux"                     # tmux 補完
    "vi-mode"                  # Vi モード拡張
    "history-substring-search" # 部分文字列履歴検索
    "colored-man-pages"        # man ページのカラー表示
    "command-not-found"        # コマンド未インストール時の提案
    "extract"                  # アーカイブ展開
    "z"                        # ディレクトリジャンプ
  ];
};
```

## グローバルツール管理 (mise)

node / npm グローバルツールは `programs.mise` が宣言的に管理する
(`nix/home-manager/default.nix`):

```nix
programs.mise = {
  enable = true;
  globalConfig.tools = {
    node = "latest";
    "npm:@antfu/ni" = "latest";   # npm パッケージマネージャー抽象化
    "npm:ccusage" = "latest";     # Claude Code 使用量追跡
  };
};
```

`home-manager switch` 時に `~/.config/mise/config.toml` が生成され、
シェル起動時の `mise activate` が node / ni / ccusage を PATH に通す。

## 主要ファイル

| ファイル | 役割 |
|---------|------|
| [`nix/home-manager/programs/zsh/default.nix`](../../nix/home-manager/programs/zsh/default.nix) | Zsh 設定全体 |

## カスタマイズ

### エイリアスを追加する

```nix
# nix/home-manager/programs/zsh/default.nix
shellAliases = {
  # 既存のエイリアス...
  k = "kubectl";
  kgp = "kubectl get pods";
};
```

### テーマを変更する

```nix
oh-my-zsh = {
  theme = "agnoster";  # 例: agnoster
};
```

### プラグインを追加する

```nix
oh-my-zsh.plugins = [
  # 既存のプラグイン...
  "ansible"
  "helm"
];
```

## Tips & 注意点

- **履歴サイズ**: 100,000 エントリ。重複排除・スペースで始まるコマンドは除外
- **共有履歴**: `share = true` で複数のシェルセッション間で履歴を共有
- **Zellij 自動起動**: VSCode のターミナルでは自動起動しない（`VSCODE_INJECTION` 環境変数で判定）
- **安全機能**: `rm`, `cp`, `mv` に `-i`（確認プロンプト）を付与
