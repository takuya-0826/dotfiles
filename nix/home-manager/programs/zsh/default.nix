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
    cc = "command claude --remote-control";

    # Codex
    cod = "command codex --dangerously-bypass-approvals-and-sandbox";

    # Claude ランチャー (旧 Mac から引き継ぎ)。 _claude_in は initContent 定義。
    # cd 先を固定するので、 今いる場所に関係なく同じプロジェクトで起動できる。
    pm = "_claude_in ~/Atrae";
    frank = "_claude_in ~/Atrae/frank";
    gordon = "_claude_in ~/Atrae/frank/apps/gordon";

    # ワークスペースは herdr の永続サーバが保持する。組み直すときだけ
    # `herdr-bootstrap work` / `herdr-bootstrap cockpit` (docs/terminal/herdr-workspaces.md)。

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

    # Claude Code の子セッションマーカーを対話シェルでは常に外す (2026-08-04)。
    # マルチプレクサのサーバが Claude セッション内から起動されると、全ペインがこの
    # 変数を遺伝して「自分はサブエージェントの子」と誤認し、transcript 保存が OFF に
    # なる (= exit すると --resume 不能・claude-resume-latest も永久に失敗)。
    # 人間が打つ対話シェルから起動する claude は常に親セッションが正しい。
    # 本物の子セッションは claude が直接 spawn するので .zshrc を通らず影響しない。
    unset CLAUDE_CODE_CHILD_SESSION

    # Auto-start herdr (2026-10-01、zellij から移行。上流 EdV4H 2026-08-13 と同形)
    #
    # $HERDR_ENV は herdr が管理するペインの中でだけ "1" になるので、これで
    # ネスト起動を防ぐ (herdr 側も experimental.allow_nested=false で二重に守る)。
    # exec せず条件分岐で呼ぶのは、herdr から detach (prefix+q) したときに
    # 素の zsh に戻れるようにするため。
    #
    # 上流に無い条件を 2 つ足している (zellij 時代の 2026-08-03 事故の再発防止):
    #   -t 1          … 人間の端末に繋がっているときだけ。ツールが裏で起動する
    #                   「.zshrc を読む対話シェル」から多重起動させない。
    #   -z $CLAUDECODE … Claude Code の中から開いたシェルでも起動しない。
    # 当時の経緯 (185 セッション増殖、tty 無しゴースト 88%) は
    # docs/claude-code/_archived/zellij-integration.md と git log を参照。
    # herdr はサーバ 1 本に全 workspace が載る設計なのでセッションは増殖しないが、
    # 条件は無害なので残す。
    if [[ -o interactive && -t 1 && -z "$HERDR_ENV" && -z "$VSCODE_INJECTION" && -z "$CLAUDECODE" ]]; then
      herdr
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

    # zj-hub / dev-hub / zj-project は退役した。現在の zellij 環境は
    # layouts/work.kdl (タブ = PJ、作業する画面) と layouts/cockpit.kdl
    # (ペイン = PJ、--remote-control で俯瞰する指揮盤面) の 2 枚だけで、
    # ランチャーは要らない (端末を開くと auto-start が work を開く)。
    #
    # ⚠️ 2026-08-11 にここへ「まるちゃんの work.kdl はタブ = PJ で、1 画面に複数 PJ を
    # 並べたペインは 1 つも無い」と書いて dev-hub を退役させたが、これは誤りだった。
    # 上流 EdV4H には cockpit.kdl があり、まさにペイン = PJ をやっている (本人の
    # docs/terminal/zellij-layouts.md が「複数プロジェクトの Claude Code を同時に
    # 表示し、全体を俯瞰する」と説明している)。彼は 2 枚を用途で使い分けていて、
    # 8 分割とタブ = PJ は対立しない。詳細は layouts/work.kdl 冒頭。
    #
    # ここにあった知見は移設済み:
    #   - 復元ダンプが MCP サーバを掴む件 → programs/zellij/config.kdl
    #     (session_serialization を外した理由として記述)
    #   - レイアウトの設計メモ → programs/zellij/layouts/work.kdl 冒頭
    #   - 旧 dev-hub 本体 → programs/zellij/_archived/dev-hub.kdl
    #
    # ★ 唯一ここにしか無かった知見なので書き残す: zellij の中から
    #   `zellij attach` を呼ぶと **入れ子**になる。キー入力は外側のセッションが
    #   先に食うのでフルスクリーン (Alt+f) やペイン移動が効かなくなる
    #   (ステータスバーが 2 本出ているのが入れ子のサイン)。内側から別セッションへ
    #   移るときは `zellij action switch-session` でクライアントを載せ替える。

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
