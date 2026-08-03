{ pkgs, config, ... }:

{
  enable = true;

  # Enable useful features
  enableCompletion = true;
  autosuggestion.enable = true;
  syntaxHighlighting.enable = true;

  # History configuration
  history = {
    size = 100000;
    save = 100000;
    path = "${config.home.homeDirectory}/.zsh_history";
    ignoreDups = true;
    ignoreSpace = true;
    share = true;
  };

  # Shell aliases
  shellAliases = {
    # Navigation
    ".." = "cd ..";
    "..." = "cd ../..";
    "...." = "cd ../../..";

    # Git shortcuts
    g = "git";
    gs = "git status";
    gd = "git diff";
    gco = "git checkout";
    gcm = "git commit -m";
    gp = "git push";
    gl = "git pull";
    lg = "lazygit";

    # Directory listing
    ls = "ls --color=auto";
    la = "ls -la";
    ll = "ls -l";
    lt = "ls -lat";

    # Safety features
    rm = "rm -i";
    cp = "cp -i";
    mv = "mv -i";

    # Utilities
    cl = "clear";
    h = "history";
    hg = "history | grep";

    # Claude
    ccd = "command claude --dangerously-skip-permissions";
    ccdr = "command claude --dangerously-skip-permissions --remote-control";

    # Claude ランチャー (旧 Mac から引き継ぎ)。 _claude_in は initContent 定義。
    # cd 先を固定するので、 今いる場所に関係なく同じプロジェクトで起動できる。
    pm = "_claude_in ~/Atrae";
    frank = "_claude_in ~/Atrae/frank";
    gordon = "_claude_in ~/Atrae/frank/apps/gordon";

    # cca / cchub (zellij dev-hub セッション) は意図的に未登録。
    # dev-hub レイアウトは旧 Mac 側で layouts/_archived/ に引退させられていた。
    # zellij タブの起動は ~/.local/bin/zj-project (frank|ats|forms|general) を使う。

    # Neovim
    v = "nvim";
    vi = "nvim";
    vim = "nvim";

    # Quick edits
    zshrc = "nvim ~/.zshrc";
    zshconf = "nvim ~/dotfiles/nix/home-manager/programs/zsh/default.nix";
    nixconf = "nvim ~/dotfiles/flake.nix";

    # System
    update = "cd ~/dotfiles && nix run .#update";
    rebuild = "cd ~/dotfiles && nix run .#update";

    # Package manager shortcuts (@antfu/ni, mise で管理)
    # ni - install
    # nr - run
    # nx - execute
    # nu - update
    # nun - uninstall
    # nci - clean install
    # na - agent alias
  };

  # Session variables
  sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    PAGER = "less";
    LESS = "-R";
    # claude はネイティブ版 (~/.local/bin/claude、 公式インストーラ) を正とする。
    # nix の pkgs.claude-code も入るが、 envExtra で $HOME/.local/bin を PATH 先頭に
    # 置いているのでネイティブ版が勝つ。 ネイティブ版は自己更新するため常に新しい
    # (nix 側は flake.lock 追従なので遅れる)。
    # happy-coder にも同じ実体を渡さないと、 shell の claude と別バージョンを掴む。
    HAPPY_CLAUDE_PATH = "${config.home.homeDirectory}/.local/bin/claude";
  };

  # Init extra configuration
  initContent = ''
    # goenv (ensure Homebrew PATH is available before init)
    if [[ -x /opt/homebrew/bin/goenv ]]; then
      export PATH="/opt/homebrew/bin:$PATH"
      eval "$(/opt/homebrew/bin/goenv init -)"
    fi

    # Auto-start Zellij
    #
    # 単一セッション "dev" に attach する (zj-project と同じセッション名)。
    # `zellij setup --generate-auto-start` の既定は素の `zellij` = 起動のたびに
    # ランダム名で新規作成。zellij はクライアント/サーバ分離型でデタッチしても
    # サーバが残り、GC が無いので再起動まで一方的に増え続ける。各サーバは
    # ペイン名更新のため `ps -ao ppid,args` を定期実行するため、
    # セッション数 × 全プロセス数で負荷が自乗に効く。
    #
    # 発火条件も絞る。既定の判定は $ZELLIJ の有無だけで「人間が打つシェルか」を
    # 見ないため、GUI アプリやツールが `zsh -l` を起動しただけで発火する。
    # 2026-08-03、これが原因で 185 セッションまで増殖し Mac が実用不能になった
    # (load 43 / 全プロセス 1248 / ps だけで CPU 618% / zellij RSS 2.26GB)。
    # 主犯は Claude Code で、shell snapshot 用の非対話シェル経由で 1 日 30〜60 個
    # 生んでいた。CLAUDECODE は子プロセスに継承されるので明示的に除外する。
    if [[ -o interactive && -t 1 && -z "$ZELLIJ" && -z "$VSCODE_INJECTION" && -z "$CLAUDECODE" ]]; then
      zellij attach -c dev
    fi

    # Enable vi mode
    bindkey -v
    export KEYTIMEOUT=1

    # Better vi mode indicators
    function zle-keymap-select {
      if [[ ''${KEYMAP} == vicmd ]] || [[ $1 = 'block' ]]; then
        echo -ne '\e[1 q'
      elif [[ ''${KEYMAP} == main ]] || [[ ''${KEYMAP} == viins ]] || [[ ''${KEYMAP} = "" ]] || [[ $1 = 'beam' ]]; then
        echo -ne '\e[5 q'
      fi
    }
    zle -N zle-keymap-select

    # Use beam cursor on startup
    echo -ne '\e[5 q'

    # Edit command line in vim
    autoload -z edit-command-line
    zle -N edit-command-line
    bindkey -M vicmd v edit-command-line

    # Better history search
    bindkey '^R' history-incremental-search-backward
    bindkey '^S' history-incremental-search-forward
    bindkey '^P' up-line-or-search
    bindkey '^N' down-line-or-search

    # Key bindings for autosuggestions
    bindkey '^ ' autosuggest-accept
    bindkey '^f' autosuggest-accept

    # FZF integration if available
    if command -v fzf &> /dev/null; then
      source ${pkgs.fzf}/share/fzf/key-bindings.zsh
      source ${pkgs.fzf}/share/fzf/completion.zsh
    fi

    # Directory shortcuts
    hash -d dotfiles="$HOME/dotfiles"
    hash -d nix="$HOME/dotfiles/nix"
    hash -d downloads="$HOME/Downloads"
    hash -d projects="$HOME/Projects"

    # Useful functions
    function mkcd() {
      mkdir -p "$1" && cd "$1"
    }

    function extract() {
      if [ -f "$1" ]; then
        case "$1" in
          *.tar.bz2) tar xjf "$1";;
          *.tar.gz) tar xzf "$1";;
          *.bz2) bunzip2 "$1";;
          *.gz) gunzip "$1";;
          *.tar) tar xf "$1";;
          *.tbz2) tar xjf "$1";;
          *.tgz) tar xzf "$1";;
          *.zip) unzip "$1";;
          *.Z) uncompress "$1";;
          *.7z) 7z x "$1";;
          *) echo "'$1' cannot be extracted via extract()";;
        esac
      else
        echo "'$1' is not a valid file"
      fi
    }

    # Quick backup function
    function backup() {
      cp "$1" "$1.bak"
    }

    # Claude wrapper function to disable --dangerously-skip-permissions
    function claude() {
      for arg in "$@"
      do
        if [[ "$arg" = "--dangerously-skip-permissions" ]]
        then
          echo "エラー: '--dangerously-skip-permissions' オプションは無効化されています。" >&2
          return 1
        fi
      done
      command claude "$@"
    }

    # コンテキスト固定ランチャー。 どこから打っても claude の着地先が一定になる。
    # サブシェル ( ) で cd するので、 終了後は元の cwd に戻る。
    # 対応する alias は shellAliases の "Claude ランチャー" を参照。
    function _claude_in() {
      local dir="$1"
      shift
      ( cd "$dir" && claude "$@" )
    }

    # Find and replace in current directory
    function find-replace() {
      if [ $# -ne 2 ]; then
        echo "Usage: find-replace <find-text> <replace-text>"
        return 1
      fi
      rg -l "$1" | xargs sed -i "" "s/$1/$2/g"
    }
  '';

  # Environment variables
  envExtra = ''
    # Set PATH
    # 先頭に置くのは意図的。 claude はネイティブ版 (~/.local/bin/claude) を正とし、
    # nix の pkgs.claude-code より優先させる (HAPPY_CLAUDE_PATH も同じ実体を指す)。
    export PATH="$HOME/.local/bin:$PATH"

    # Load Nix profile
    if [ -e ~/.nix-profile/etc/profile.d/nix.sh ]; then
      . ~/.nix-profile/etc/profile.d/hm-session-vars.sh
    fi

    # Set default language
    export LANG="en_US.UTF-8"
    export LC_ALL="en_US.UTF-8"

    # node / ni / ccusage は mise (programs.mise) がグローバル管理する。

    # --- 会社端末 (Atrae) 必須の設定 -------------------------------------
    # 忘れると npm / pip / uv が TLS エラーや 403 で壊れる。
    # sessionVariables ではなく envExtra (.zshenv) に置くのは、 対話シェル以外
    # (エディタや CI ツールから起動される非対話 shell) でも効かせる必要があるため。

    # Netskope (SWG) が TLS を MITM するので、 その CA を node に信頼させる。
    # 証明書は Jamf が配布するため、 ファイルが在るときだけ設定する
    # (Netskope が入っていない端末でも壊れないように)。
    if [ -f "/Library/Application Support/Netskope/STAgent/data/nscacert.pem" ]; then
      export NODE_EXTRA_CA_CERTS="/Library/Application Support/Netskope/STAgent/data/nscacert.pem"
    fi

    # Takumi Guard PyPI プロキシ (社内で許可された PyPI ミラー)。
    export PIP_INDEX_URL="https://pypi.flatt.tech/simple/"
    export UV_INDEX_URL="https://pypi.flatt.tech/simple/"
    # ---------------------------------------------------------------------

    # 秘密情報は nix 管理外の ~/.zshrc.secrets (mode 600) に置き、 ここから読むだけ。
    # この repo は public なので、 トークンを .nix に直接書くと即漏洩する。
    # 中身: FIGMA_TOKEN / OPENAI_API_KEY (旧 Mac では .zshrc に平文で書かれていた)。
    # 新しい PC ではこのファイルを別途持ち込む必要がある (nix では再現されない)。
    [ -f "$HOME/.zshrc.secrets" ] && source "$HOME/.zshrc.secrets"
  '';

  # Oh-my-zsh configuration
  oh-my-zsh = {
    enable = true;
    theme = "robbyrussell";
    plugins = [
      "git"
      "docker"
      "kubectl"
      "terraform"
      "aws"
      "npm"
      "node"
      "python"
      "golang"
      "rust"
      "tmux"
      "vi-mode"
      "history-substring-search"
      "colored-man-pages"
      "command-not-found"
      "extract"
      "z"
    ];
  };
}
