{ pkgs }:
let
  neovimConfigDir = ./config;

  # 2026-10: nixpkgs の typescript-language-server 6.0.2 は pnpmDeps の hash が
  # aarch64-darwin で一致せずビルドできない。
  # Mac で実際に得られた hash に差し替える。 upstream の hash が下の既知の値から変われば
  # (version bump や再修正) この override は自動で外れるので、 そのときはこのブロックごと消してよい。
  #   MUSx…: nixos-unstable 7fd4004 時点 / xR/EF…: master の "fix pnpm hash" (NixOS/nixpkgs#572951)
  knownBadTslsPnpmHashes = [
    "sha256-MUSxDMlbG21KSesGdEvqa2kEpuVfLlXRUX1qV/FGsSo="
    "sha256-xR/EF60lVBsITKgH7wCM2wHM46PFQevD51KfCENSUH4="
  ];
  typescript-language-server = pkgs.typescript-language-server.overrideAttrs (
    old:
    pkgs.lib.optionalAttrs (builtins.elem old.pnpmDeps.outputHash knownBadTslsPnpmHashes) {
      pnpmDeps = old.pnpmDeps.overrideAttrs {
        outputHash = "sha256-PmyJb8090pEPc09Tbv8RgdvQpzpba2L8ve87+aVncQU=";
      };
    }
  );
in
{
  enable = true;
  defaultEditor = true;
  viAlias = true;
  vimAlias = true;

  # home-manager の programs.neovim が内部で wrap し直すので、 unwrapped を渡す。
  # 旧 nightly overlay の頃は wrapped でも動いていたが、 通常の nixpkgs では
  # wrapped が `.lua` 属性を持たないため、 wrapper.nix の評価で失敗する。
  package = pkgs.neovim-unwrapped;

  # Extra packages available to Neovim
  extraPackages = with pkgs; [
    # Language servers
    lua-language-server
    typescript-language-server # let の override 版 (with より let が優先される)
    nil # Nix language server
    gopls

    # Formatters
    nixpkgs-fmt
    prettierd
    stylua
    prettier
    black
    isort
    ruff
    biome

    # Other tools
    ripgrep
    fd
    tree-sitter
  ];

  # Neovim plugins managed by Nix
  plugins = with pkgs.vimPlugins; [
    # Essential plugins
    plenary-nvim
    nvim-web-devicons

    # Navigation
    flash-nvim

    # Colorscheme
    tokyonight-nvim

    # Treesitter
    {
      plugin = nvim-treesitter.withAllGrammars;
      type = "lua";
      config = builtins.readFile "${neovimConfigDir}/lua/plugins/treesitter.lua";
    }

    # LSP
    nvim-lspconfig

    # Completion
    nvim-cmp
    cmp-nvim-lsp
    cmp-buffer
    cmp-path
    cmp-cmdline
    luasnip
    cmp_luasnip

    # Fuzzy finder
    telescope-nvim
    {
      plugin = telescope-file-browser-nvim;
      type = "lua";
      config = builtins.readFile "${neovimConfigDir}/lua/plugins/telescope-file-browser.lua";
    }

    # Git integration
    {
      plugin = gitsigns-nvim;
      type = "lua";
      config = builtins.readFile "${neovimConfigDir}/lua/plugins/gitsigns.lua";
    }

    # EditorConfig support
    editorconfig-nvim

    # Auto-formatting
    conform-nvim
  ];

  # Source external init.lua
  initLua = builtins.readFile "${neovimConfigDir}/init.lua";

  # Additional configuration files
  extraLuaPackages = ps: [ ];

  # The configuration files will be loaded via the init.lua
}
