{ pkgs, ... }:
{
  # 新 PC は Determinate Systems の Nix installer を使っているので、 nix-darwin が
  # Nix を管理しようとすると衝突する。 nix.enable = false にして Determinate に任せる。
  # TODO: 旧 PC (classic nix-darwin) と新 PC (Determinate) で出し分け
  # 現状旧 PC でもこれが false になり、 nix.optimise.automatic / max-jobs は効かないが、
  # 実害は小さい。 必要なら home-manager の nix.settings 側で代替する。
  nix.enable = false;

  system = {
    primaryUser = "takuyamatsumoto";
    stateVersion = 6;
    defaults = {
      NSGlobalDomain.AppleShowAllExtensions = true;
      finder = {
        AppleShowAllFiles = true;
        AppleShowAllExtensions = true;
      };
      dock = {
        autohide = true;
        show-recents = false;
        orientation = "bottom";
      };
    };
  };

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "uninstall";
      # `brew bundle install --cleanup` が `--force` 要求するようになった
      # (Homebrew CLI 仕様変更) ので、 確認なしで cleanup を走らせる。
      extraFlags = [ "--force-cleanup" ];
    };
    # cleanup = "uninstall" なので、 ここに書いていない brew パッケージ / cask は
    # switch のたびに確認なしでアンインストールされる。 手で brew install しても
    # 次の switch で消えるため、 入れたいものは必ずここに足すこと。
    brews = [
      "goenv"
      "bun"
      "herdr" # Claude Code の SessionStart hook が依存
      "railway"
      "pandoc"
      "poppler"
      "neonctl" # Ignition の Neon Postgres 操作
      "redis"
      # python は mise (programs.mise.globalConfig) で宣言する方に寄せたので
      # brew の python@3.13 は外した。 宣言先を 1 箇所にするため。
      # なお pipx が依存で python@3.14 を引き込むので、 それは残る。
      "pipx"
    ];
    casks = [
      "docker-desktop"
      "wezterm@nightly"
      "raycast"
      "figma"
      "logi-options+"
      "amethyst"
      "thebrowsercompany-dia"
      "nani"
      "amazon-workspaces"
      "claude"
      "codexbar"
      "chatgpt"
      "obsidian" # brain vault (Obsidian) を開く
      "ghostty" # 常用ターミナル
      "codex" # クロスモデルレビュー用 OpenAI codex CLI
      "font-jetbrains-mono-nerd-font"
      "visual-studio-code"
      "session-manager-plugin"
      # 旧 Mac では直ダウンロードで入れていたため brew leaves / brew list --cask
      # ベースの棚卸しから構造的に漏れていた 2 件 (2026-07-29 の環境差分照合で発見)。
      "typeless" # 音声入力。 旧 Mac で毎日使用
      "cursor"
    ];
  };

  launchd.user.agents.nix-auto-update = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          export PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin
          cd /Users/takuyamatsumoto/dotfiles
          echo "$(date): Starting nix auto update..." >> /tmp/nix-auto-update.log
          nix flake update >> /tmp/nix-auto-update.log 2>&1
          /Users/takuyamatsumoto/.nix-profile/bin/home-manager switch --flake .#myHomeConfig >> /tmp/nix-auto-update.log 2>&1
          sudo /run/current-system/sw/bin/darwin-rebuild switch --flake .#ATR-LAP-OSX-TAKUYA-MATSUMOTO >> /tmp/nix-auto-update.log 2>&1
          echo "$(date): Update complete." >> /tmp/nix-auto-update.log
        ''
      ];
      StartCalendarInterval = [
        {
          Hour = 9;
          Minute = 0;
        }
      ];
      StandardOutPath = "/tmp/nix-auto-update.out.log";
      StandardErrorPath = "/tmp/nix-auto-update.err.log";
    };
  };

  # マシン性能ロガー。 1 分ごとに ~/mac_perf.log へ追記し、 perf-log-analyst
  # エージェントがそれを読んでサーマルスロットリング等を分析する。
  # スクリプト実体は home-manager が ~/.local/bin に置く (旧 Mac から移植)。
  launchd.user.agents.mac-perf-logger = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/zsh"
        "/Users/takuyamatsumoto/.local/bin/mac-perf-logger.sh"
      ];
      StartInterval = 60;
      RunAtLoad = true;
      StandardErrorPath = "/Users/takuyamatsumoto/Library/Logs/mac-perf-logger.err";
    };
  };

  # brain vault (Obsidian) の無人スイープ。 毎週金曜 17:00 に走り、
  # ~/brain/_system/sweep-reports/ にレポートを出す。
  # sweep.sh は brain repo 側に入っているので、 ~/brain が clone 済みである前提。
  launchd.user.agents.brain-sweep = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/zsh"
        "/Users/takuyamatsumoto/brain/_system/sweep.sh"
      ];
      StartCalendarInterval = [
        {
          Weekday = 5;
          Hour = 17;
          Minute = 0;
        }
      ];
      StandardOutPath = "/Users/takuyamatsumoto/brain/_system/logs/launchd.log";
      StandardErrorPath = "/Users/takuyamatsumoto/brain/_system/logs/launchd.log";
    };
  };

  # 日報 (daily-report) / PR コンフリクト自動解決 (pr-conflict-check) /
  # Renovate 自動処理 (renovate-scheduled) の launchd エージェントは意図的に未登録。
  # スクリプト自体は home-manager が ~/.local/bin に配置しているので、
  # 必要になったら手動実行するか、ここに agent を書き足して再 switch する。
  # (元の定義は git log を参照)

  security.sudo.extraConfig = ''
    takuyamatsumoto ALL=(ALL) NOPASSWD: /run/current-system/sw/bin/darwin-rebuild
  '';

  fonts = {
    packages = with pkgs; [
      hackgen-nf-font
    ];
  };
}
