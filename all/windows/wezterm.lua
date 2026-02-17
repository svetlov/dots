local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.term = "xterm-256color"
config.audible_bell = "Disabled"

-- Font configuration
config.font = wezterm.font('Google Sans Code NF', { weight = 'Regular' })
config.font_size = 12.0

config.font_rules = {
  {
    intensity = 'Bold',
    font = wezterm.font('Google Sans Code NF', { weight = 'Bold' })
  },
  {
    italic = true,
    font = wezterm.font('Google Sans Code NF', { style = 'Italic' })
  },
  {
    intensity = 'Bold',
    italic = true,
    font = wezterm.font('Google Sans Code NF', { weight = 'Bold', style = 'Italic' })
  },
}

-- Alacritty default colors
config.colors = {
  foreground = '#d8d8d8',
  background = '#181818',
  
  cursor_bg = '#d8d8d8',
  cursor_border = '#d8d8d8',
  cursor_fg = '#181818',
  
  selection_bg = '#d8d8d8',
  selection_fg = '#181818',
  
  ansi = {
    '#181818', -- black
    '#ac4242', -- red
    '#90a959', -- green
    '#f4bf75', -- yellow
    '#6a9fb5', -- blue
    '#aa759f', -- magenta
    '#75b5aa', -- cyan
    '#d8d8d8', -- white
  },
  
  brights = {
    '#6b6b6b', -- bright black
    '#c55555', -- bright red
    '#aac474', -- bright green
    '#feca88', -- bright yellow
    '#82b8c8', -- bright blue
    '#c28cb8', -- bright magenta
    '#93d3c3', -- bright cyan
    '#f8f8f8', -- bright white
  },
}

-- Shift+Click to open hyperlinks (works inside tmux)
config.mouse_bindings = {
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'SHIFT',
    action = wezterm.action.OpenLinkAtMouseCursor,
  },
}

-- Default shell: WSL with zsh login shell
config.default_prog = { 'wsl.exe', '-e', 'zsh', '-l' }

return config
