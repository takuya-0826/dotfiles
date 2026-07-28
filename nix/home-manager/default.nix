{
  inputs,
  lib,
  config,
  pkgs,
  ...
}:
let
  username = "takuyamatsumoto";
  pwd = "${config.home.homeDirectory}/dotfiles-nix/home-manager/console/neovim";
in
{
  nixpkgs = {
    # 2026-06-11: Netskope の SSL Inspection Bypass が入って cache.nixos.org が
    # 正常に引けるようになったので、 以前 SIGKILL / flaky test 回避のために入れていた
    # overlay 群 (asciidoc / awscli2 / direnv / python313.tornado) を撤去。
    # python313.override が python パッケージセット全体を新 hash にしてしまい、
    # 巨大な local build (~1400 derivations) を誘発していた。
    # 再発時のメモは git log で参照可能。
    overlays = [ ];
    config = {
      allowUnfree = true;
    };
  };

  home = {
    username = username;
    homeDirectory = "/Users/${username}";

    stateVersion = "25.05";

    packages = with pkgs; [
      git
      gh
      curl
      jq
      ripgrep
      coreutils
      tmux
      docker
      lazygit
      claude-code
      gemini-cli
      amazon-q-cli
      google-cloud-sdk
      fzf
      zoxide
      eza
      bat
      fd
      direnv
      uv
      awscli2
      bruno
      mysql84
      lazysql
      zellij
      inputs.gws.packages.${pkgs.system}.default
      inputs.gh-review-watcher.packages.${pkgs.system}.default
      inputs.port-patrol.packages.${pkgs.system}.default
    ];

    sessionVariables = {
      GOOGLE_CLOUD_PROJECT = "atrae-engineer-gu7335mbf";
      GOENV_ROOT = "$HOME/.goenv";
      CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "65";
    };

    sessionPath = [
      "$HOME/.local/bin"
      "$GOENV_ROOT/bin"
      "$HOME/go/bin"
    ];
  };

  programs.home-manager.enable = true;

  # git identity。 手で `git config --global` すると新 PC で消えるので nix 管理下に置く。
  #
  # メールは GitHub の noreply アドレス。 この dotfiles は public repo なので、
  # 会社メールを刻印すると公開履歴に永久に残る (収集 bot の的にもなる)。
  # noreply でも GitHub 上の表示 (アイコン / profile リンク / contribution) は同じ。
  #
  # 注意: home-manager はこれを ~/.config/git/config に書く。 git は
  # ~/.gitconfig が存在するとそちらを優先して ~/.config/git/config を**無視する**
  # ので、 `git config --global` は使わないこと (使うと下記の設定が死ぬ)。
  programs.git = {
    enable = true;
    settings.user = {
      name = "Takuya Matsumoto";
      email = "66290370+takuya-0826@users.noreply.github.com";
    };
    # グローバル gitignore (~/.config/git/ignore に出力される)。
    # Claude Code がリポジトリごとに作る settings.local.json の誤コミット防止。
    ignores = [
      "**/.claude/settings.local.json"
    ];
  };

  programs.wezterm = import ./programs/wezterm/default.nix;

  # mise: ランタイム管理 (旧 volta の置き換え)。 node は latest をグローバル固定。
  #
  # ni / ccusage 等の npm backend ツールはここでは管理しない。 npm.flatt.tech の
  # min-release-age (リリース後 5 日は install 拒否) と mise の "latest"/レンジ解決が
  # 衝突する (mise が先に最新版へ固定 → npm が age で弾く) ため。
  # それらは nix 管理外の書き込み可能な ~/.config/mise/conf.d/*.toml で
  # age を満たす版を明示ピンして ad-hoc 管理する。
  programs.mise = {
    enable = true;
    enableZshIntegration = true;
    globalConfig = {
      tools = {
        node = "latest";
      };
    };
  };

  programs.bash.enable = false;
  programs.zsh = import ./programs/zsh/default.nix {
    inherit pkgs config;
  };

  programs.neovim = import ./programs/neovim/default.nix {
    inherit pkgs;
  };

  # Copy Neovim configuration files
  xdg.configFile."nvim/init.lua" = {
    source = ./programs/neovim/config/init.lua;
  };

  xdg.configFile."nvim/lua" = {
    source = ./programs/neovim/config/lua;
    recursive = true;
  };

  # Legacy symlink for backward compatibility
  xdg.configFile."nvim/lua/conf" = {
    source = config.lib.file.mkOutOfStoreSymlink "${pwd}/conf";
  };

  # Claude Code hooks
  home.file.".claude/hooks/notify-done.sh" = {
    source = ./programs/claude-code/notify-done.sh;
    executable = true;
  };

  home.file.".claude/hooks/zellij-tab-thinking.sh" = {
    source = ./programs/claude-code/zellij-tab-thinking.sh;
    executable = true;
  };

  home.file.".claude/hooks/zellij-tab-done.sh" = {
    source = ./programs/claude-code/zellij-tab-done.sh;
    executable = true;
  };

  # Claude Code zellij wrapper (claude-zellij command)
  home.file.".local/bin/claude-zellij" = {
    source = ./programs/claude-code/claude-zellij.sh;
    executable = true;
  };

  # Daily report generator script
  home.file.".local/bin/daily-report" = {
    source = ./programs/claude-code/daily-report.sh;
    executable = true;
  };

  # PR conflict daily auto-checker (entrypoint, called by launchd)
  home.file.".local/bin/pr-conflict-check" = {
    source = ./programs/claude-code/pr-conflict-check.sh;
    executable = true;
  };

  # Single-PR conflict resolver (called by pr-conflict-check)
  home.file.".local/bin/pr-conflict-resolve" = {
    source = ./programs/claude-code/pr-conflict-resolve.sh;
    executable = true;
  };

  # Renovate PR scheduled processor (entrypoint, called by launchd every few hours)
  home.file.".local/bin/renovate-scheduled" = {
    source = ./programs/claude-code/renovate-scheduled.sh;
    executable = true;
  };

  # PR review script (triggered by gh-review-watcher)
  home.file.".local/bin/review-pr" = {
    source = ./programs/claude-code/review-pr.sh;
    executable = true;
  };

  # Close merged/closed PR review tabs (triggered by gh-review-watcher on_poll)
  home.file.".local/bin/close-merged-review-tab" = {
    source = ./programs/claude-code/close-merged-review-tab.sh;
    executable = true;
  };

  # Close "Conflict: <repo>#<num>" tab safely (used by pr-conflict-resolve handoff prompt)
  home.file.".local/bin/close-conflict-tab" = {
    source = ./programs/claude-code/close-conflict-tab.sh;
    executable = true;
  };

  # PC migration helpers (旧 PC 側で export + list-repos、新 PC 側で restore)
  home.file.".local/bin/migration-export" = {
    source = ./programs/claude-code/migration/export-secrets.sh;
    executable = true;
  };
  home.file.".local/bin/migration-list-repos" = {
    source = ./programs/claude-code/migration/list-repos.sh;
    executable = true;
  };
  home.file.".local/bin/migration-restore" = {
    source = ./programs/claude-code/migration/restore.sh;
    executable = true;
  };

  # Claude Code skills (gws - Google Workspace CLI)
  home.file.".claude/skills" = {
    source = ./programs/claude-code/skills;
    recursive = true;
  };

  # Zellij layouts
  xdg.configFile."zellij/layouts" = {
    source = ./programs/zellij/layouts;
    recursive = true;
  };

  # Zellij 本体設定 (旧 Mac から移植)。 zellij は初回起動時に config.kdl を自動生成
  # するが、 それは既定値のダンプなので上書きしてよい。 差分は theme
  # (catppuccin-mocha / ghostty と統一) / pane_frames false / default_layout compact
  # / session_serialization true / show_startup_tips false の 5 点。
  # session_serialization は zj-project のタブ (cwd・コマンド) を再起動後に復活させる。
  xdg.configFile."zellij/config.kdl".source = ./programs/zellij/config.kdl;

  # Ghostty (常用ターミナル、 旧 Mac から移植)。 JetBrainsMono Nerd Font +
  # CJK をヒラギノ角ゴ ProN にマップ + Catppuccin Mocha + JIS キーボード向け
  # キーバインド。 フォントは homebrew cask font-jetbrains-mono-nerd-font で入る。
  xdg.configFile."ghostty/config".source = ./programs/ghostty/config;

  # starship のプロンプト定義 (旧 Mac から移植)。 ファイルを置くだけでは有効に
  # ならない。 有効化するには programs/zsh/default.nix の oh-my-zsh.theme を外して
  # starship init を足す必要がある (現在は robbyrussell テーマのまま)。
  xdg.configFile."starship.toml".source = ./programs/starship/starship.toml;

  # gh-review-watcher の hook 設定
  xdg.configFile."gh-review-watcher/config.toml" = {
    source = ./programs/claude-code/gh-review-watcher-config.toml;
  };
}
