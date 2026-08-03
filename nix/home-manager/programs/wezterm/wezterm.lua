-- Pull in the wezterm API
local wezterm = require 'wezterm'

-- This table will hold the configuration.
local config = {}

-- In newer versions of wezterm, use the config_builder which will
-- help provide clearer error messages
if wezterm.config_builder then
  config = wezterm.config_builder()
end

-- This is where you actually apply your config choices

-- 背景透過
config.window_background_opacity = 1

-- Font
config.font = wezterm.font("HackGen Console NF", {weight="Regular", stretch="Normal", style="Normal"})
config.font_size = 14.0
config.use_ime = true

-- Option キーを Alt として送る (2026-08-03 追加)。
-- macOS の既定では Option が「合成キー入力」(特殊文字) に食われるため、
-- zellij の Alt 系バインド (Alt+矢印 = ペイン/タブ移動、Alt+n = 新規ペイン、
-- Alt+[ ] = レイアウト切替) がターミナルに届かず一切効かなかった。
-- 両方 false にして左右どちらの Option も Alt 修飾として転送する。
-- 代償は Option+英字での特殊文字入力 (¥ や © 等) が使えなくなること。
-- 日本語入力は IME 側の処理なので影響しない (use_ime = true のまま)。
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

-- Color scheme:
config.color_scheme = 'Everforest Dark (Gogh)'

-- Mouse bindings
config.mouse_bindings = {
  -- Ctl + Click to open link in browser
  {
    event={Up={streak=1, button="Left"}},
    mods="CMD",
    action="OpenLinkAtMouseCursor",
  },
}

-- Keybindings
local act = wezterm.action
config.keys = {
  -- Ctrl+Shift+sで新しいペインを作成(画面を分割)
  {
    key = 's',
    mods = 'SHIFT|CTRL',
    action = act.SplitHorizontal { domain = 'CurrentPaneDomain' },
  },
  -- Ctrl+Shift+vで新しいペインを作成(画面を分割)
  {
    key = 'v',
    mods = 'SHIFT|CTRL',
    action = act.SplitVertical { domain = 'CurrentPaneDomain' },
  },
  -- Ctrl+Shift+wで現在のペインを閉じる
  {
    key = 'w',
    mods = 'SHIFT|CTRL',
    action = act.CloseCurrentPane { confirm = true },
  },
  -- Ctrl+Backspaceで前の単語を削除
  {
    key = "Backspace",
    mods = "CTRL",
    action = act.SendKey {
      key = "w",
      mods = "CTRL",
    },
  },
  -- Shift+Enterでエスケープ付き改行を送信
  {
    key = "Enter",
    mods = "SHIFT",
    action = act.SendString("\x1b\r"),
  },
}

-- and finally, return the configuration to wezterm
return config
