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

  # デスクトップ通知の共通ヘルパー。
  #
  # 以前は各スクリプトが /Applications/Utilities/Notifier.app/... を直書きしていた。
  # これは Nix 管理外の手動インストールアプリで、 どこにも宣言が無かったため、
  # アプリが消えた瞬間に通知が全滅し Stop hook がエラーを吐き続ける状態になった。
  # writeShellApplication の runtimeInputs に通知バイナリを宣言することで、
  # 「Nix が存在を保証する」形に変える。 呼び出し側は絶対パスを持たない。
  notify-desktop = pkgs.writeShellApplication {
    name = "notify-desktop";
    runtimeInputs = [ pkgs.terminal-notifier ];
    text = builtins.readFile ./programs/claude-code/notify-desktop.sh;
  };
  notifyDesktop = "${notify-desktop}/bin/notify-desktop";
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
      ffmpeg
      direnv
      uv
      awscli2
      bruno
      mysql84
      lazysql
      # herdr: ターミナルマルチプレクサ (2026-10-01 に zellij から移行、 上流 2026-08-13 と同形)。
      # Homebrew formula の herdr (0.7.5) は削除し nixpkgs 版に一本化した。
      herdr
      # zellij は移行期間中だけ残す (既存セッションの退避用)。 herdr で一通り回ることを
      # 確認したら消す。 旧レイアウト/ラッパーは programs/zellij/_archived/ に退避済み。
      zellij
      # watch-video skill の依存。 yt-dlp で動画/字幕取得、 ffmpeg (ffprobe 同梱) で
      # フレーム抽出とメタデータ取得。 ローカル文字起こしの mlx-whisper は nixpkgs に
      # 無いので `uv tool install mlx-whisper` で別途入れる (YouTube は auto-sub で足りる)。
      yt-dlp
      ffmpeg
      inputs.gws.packages.${pkgs.system}.default
      inputs.gh-review-watcher.packages.${pkgs.system}.default
      inputs.port-patrol.packages.${pkgs.system}.default
      # デスクトップ通知の実体。 notify-desktop の runtimeInputs でも参照しているが、
      # 手動での動作確認 (terminal-notifier -list ALL 等) 用に PATH にも出しておく。
      terminal-notifier
      notify-desktop
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

    # GitHub の HTTPS URL を SSH に自動書き換えする。 旧 Mac の ~/.gitconfig に
    # あったが、 移行時に取りこぼしていた (2026-07-29 発見)。
    # これが無いと https://github.com/... で clone した repo が SSH ではなく
    # HTTPS 認証を要求してくる。
    settings.url."git@github.com:".insteadOf = "https://github.com/";
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
        # python も宣言しておく。 宣言しないと `python3` の解決先が Homebrew の
        # シンボリックリンク任せになり、 「pipx の依存で python@3.14 が入ったから
        # python3 が 3.14 になる」 という偶然でバージョンが決まってしまう
        # (2026-07-29 に実際にそうなっていた。 旧 Mac は 3.13 だった)。
        # mise の python は precompiled build を取るので npm 系の
        # min-release-age / ignore-scripts 問題とは無関係。
        python = "3.13";
        # Go: Atrae/frank の v2 (Frank を Python から書き直す取り組み) 用。
        # 宣言しない状態で開発機に go が無く、その場しのぎで `brew install go`
        # した結果「宣言に無い手動インストールに依存する」状態を作りかけたので
        # (Notifier.app と同じ構図)、node/python と同じくここで宣言する。
        # 1.26 固定は v2 の CI (.github/workflows/v2-ci.yml の go-version) と
        # 揃えるため —— 手元と CI で違う版を使うと、片方でだけ通るという
        # 一番デバッグしづらい状態になる。
        go = "1.26";
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
    source = pkgs.replaceVars ./programs/claude-code/notify-done.sh {
      inherit notifyDesktop;
    };
    executable = true;
  };

  # NOTE: Claude Code の作業状態 (working / idle / blocked) は herdr が
  # ネイティブに持つ。 `herdr integration install claude` を 1 度実行すると
  # ~/.claude/settings.json に hook が入り、 サイドバーに状態が出る。
  # 旧 zellij 構成の claude-zellij / zellij-tab-thinking.sh / zellij-tab-done.sh と
  # /tmp/zellij-tab-* マーカーはこれで不要になったため削除した。

  # そのディレクトリの直近セッションを --resume で開く。cwd を跨いで特定セッションを
  # 開き直したいとき用 (work.kdl の claude ペインは素の -c を使っている)
  home.file.".local/bin/claude-resume-latest" = {
    source = ./programs/claude-code/claude-resume-latest.sh;
    executable = true;
  };

  # Daily report generator script
  home.file.".local/bin/daily-report" = {
    source = ./programs/claude-code/daily-report.sh;
    executable = true;
  };

  # PR conflict daily auto-checker (entrypoint, called by launchd)
  home.file.".local/bin/pr-conflict-check" = {
    source = pkgs.replaceVars ./programs/claude-code/pr-conflict-check.sh {
      inherit notifyDesktop;
    };
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

  # Open a "Review: <repo>#<num>" tab running review-pr (triggered by gh-review-watcher)
  home.file.".local/bin/open-review-tab" = {
    source = ./programs/claude-code/open-review-tab.sh;
    executable = true;
  };

  # Close "Conflict: <repo>#<num>" tab (used by pr-conflict-resolve handoff prompt)
  home.file.".local/bin/close-conflict-tab" = {
    source = ./programs/claude-code/close-conflict-tab.sh;
    executable = true;
  };

  # dev-server: run long-lived dev servers inside a herdr pane/tab so the
  # Claude Code harness doesn't reap them with SIGTERM(143). See the
  # dev-server skill. dev-serve-run is the internal in-pane wrapper.
  home.file.".local/bin/dev-serve-run" = {
    source = ./programs/claude-code/dev-server/dev-serve-run.sh;
    executable = true;
  };
  home.file.".local/bin/dev-up" = {
    source = ./programs/claude-code/dev-server/dev-up.sh;
    executable = true;
  };
  home.file.".local/bin/dev-logs" = {
    source = ./programs/claude-code/dev-server/dev-logs.sh;
    executable = true;
  };
  home.file.".local/bin/dev-down" = {
    source = ./programs/claude-code/dev-server/dev-down.sh;
    executable = true;
  };
  home.file.".local/bin/dev-list" = {
    source = ./programs/claude-code/dev-server/dev-list.sh;
    executable = true;
  };
  home.file.".local/bin/dev-supervise" = {
    source = ./programs/claude-code/dev-server/dev-supervise.sh;
    executable = true;
  };
  # dev-ctl: sandbox-escape front-end. Claude's Bash sandbox blocks the herdr
  # socket, so dev-up/dev-down don't work there — but scripts under ~/.claude/scripts/
  # run OUTSIDE the sandbox when invoked by direct path. Claude drives dev servers via
  # `~/.claude/scripts/dev-ctl {up|down|logs|list|supervise}`.
  home.file.".claude/scripts/dev-ctl" = {
    source = ./programs/claude-code/dev-server/dev-ctl.sh;
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

  # herdr 設定。 レイアウトは herdr に宣言ファイル (旧 zellij の KDL 相当) が無く、
  # 永続セッションが構成を保持する設計なので、 作り直し用に bootstrap スクリプトを置く。
  xdg.configFile."herdr/config.toml" = {
    source = ./programs/herdr/config.toml;
  };

  # herdr のタブを label で引くヘルパー (close-*-tab / review-pr / pr-conflict-resolve が使う)
  home.file.".local/bin/herdr-tab-id" = {
    source = ./programs/herdr/herdr-tab-id.sh;
    executable = true;
  };

  # herdr-bootstrap <work|cockpit>: 旧 zellij KDL レイアウトの作り直し用
  home.file.".local/bin/herdr-bootstrap" = {
    source = ./programs/herdr/bootstrap.sh;
    executable = true;
  };

  # zellij 専用の自作ランチャー (zj-plan / sol-review-watch / zellij-tab-register) は
  # 2026-10-01 の herdr 移行で退役し programs/zellij/_archived/ に退避した。
  #   - zellij-tab-register: タブ名 🤖/✅ hook の共有ヘルパー → herdr がエージェント状態を
  #     ネイティブに持つので不要
  #   - zj-plan / sol-review-watch: 企画オーケストレーション組織タブ (KDL 生成) →
  #     herdr に宣言レイアウトが無い。必要になったら herdr-bootstrap 方式で作り直す
  # 旧 work.kdl / cockpit.kdl / claude-zellij も同じ場所にある。

  # Zellij 本体設定 (旧 Mac から移植)。 zellij は初回起動時に config.kdl を自動生成
  # するが、 それは既定値のダンプなので上書きしてよい。 差分は theme
  # (catppuccin-mocha / ghostty と統一) / pane_frames false / default_layout compact
  # / show_startup_tips false の 4 点。
  # session_serialization true は 2026-08-13 に外した (復元ダンプは claude ではなく
  # MCP サーバを掴むので信用できない。理由は config.kdl の当該箇所)。
  # ※ 2026-10-01 herdr 移行後は退避用。zellij 本体を外すときに一緒に消す。
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
    source = pkgs.replaceVars ./programs/claude-code/gh-review-watcher-config.toml {
      inherit notifyDesktop;
    };
  };
}
