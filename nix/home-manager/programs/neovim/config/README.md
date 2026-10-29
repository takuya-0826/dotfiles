# Neovim Configuration Structure

This directory contains the modularized Neovim configuration extracted from the inline Nix configuration.

## Directory Structure

```
config/
├── init.lua                 # Main entry point
└── lua/
    ├── config/             # Core configuration modules
    │   ├── options.lua     # Basic Neovim options
    │   ├── keymaps.lua     # Key mappings
    │   ├── colorscheme.lua # Color scheme settings
    │   ├── lsp.lua        # LSP configuration
    │   ├── completion.lua  # Completion setup
    │   └── diagnostics.lua # Diagnostic signs and settings
    └── plugins/            # Plugin-specific configurations
        ├── treesitter.lua  # Treesitter configuration
        ├── flash.lua       # Flash.nvim (jump) configuration
        ├── gitsigns.lua    # Git signs configuration
        └── conform.lua     # Formatter configuration
```

## Configuration Loading

1. The Nix configuration in `default.nix` loads `init.lua` via `extraLuaConfig`
2. `init.lua` loads all the modules in the correct order
3. Plugin configurations are loaded by their respective Nix plugin definitions
4. The configuration files are copied to `~/.config/nvim/lua/` by home-manager

## Adding New Configurations

To add new configuration modules:

1. Create a new `.lua` file in the appropriate directory (`config/` for core settings, `plugins/` for plugin configs)
2. Add a `require()` statement in `init.lua` if it's a core config module
3. For plugin configurations, update the plugin definition in `default.nix` to load the config file

## Benefits of This Structure

- **Modularity**: Each aspect of the configuration is in its own file
- **Maintainability**: Easier to find and modify specific settings
- **Version Control**: Better diff visibility for configuration changes
- **Reusability**: Individual modules can be easily shared or reused
- **Organization**: Clear separation between core config and plugin-specific settings