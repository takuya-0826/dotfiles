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
        orientation = "left";
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
      "python@3.13"
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
