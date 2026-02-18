local wezterm = require 'wezterm'
local act = wezterm.action
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

-- Hide the tab bar (workspaces replace tabs)
config.enable_tab_bar = false

config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }

local is_windows = wezterm.target_triple:find('windows') ~= nil

config.default_workspace = 'local'

-- Predefined SSH workspaces (always shown in picker, created on demand)
local ssh_workspaces = {
  'devbox',
}

-- Default shell: WSL on Windows, native zsh on macOS
if is_windows then
  config.default_prog = { 'wsl.exe', '-e', 'zsh', '-l' }
end

-- Ctrl+b prefix (one-shot, like tmux)
config.keys = {
  { key = 'a', mods = 'CTRL', action = act.ActivateKeyTable { name = 'prefix', one_shot = true, timeout_milliseconds = 2000 } },
}

config.key_tables = {
  prefix = {
    -- Splits (inherit current pane directory)
    { key = '|', mods = 'SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
    { key = '_', mods = 'SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },

    -- Pane navigation (h/j/k/l)
    { key = 'h', action = act.ActivatePaneDirection 'Left' },
    { key = 'j', action = act.ActivatePaneDirection 'Down' },
    { key = 'k', action = act.ActivatePaneDirection 'Up' },
    { key = 'l', action = act.ActivatePaneDirection 'Right' },

    -- Pane management
    { key = '\\', action = act.TogglePaneZoomState },
    { key = 'z', action = act.TogglePaneZoomState },
    -- NOTE: WezTerm has no native even-layout action (wezterm/wezterm#2972)
    -- Binding omitted until upstream adds support
    { key = 'x', action = act.CloseCurrentPane { confirm = true } },

    -- Workspace management
    { key = 'w', action = wezterm.action_callback(function(window, pane)
        local active = {}
        for _, name in ipairs(wezterm.mux.get_workspace_names()) do
          active[name] = true
        end
        -- merge active workspaces + predefined ssh workspaces, 'local' always first
        local all = { 'local' }
        local seen = { ['local'] = true }
        for _, name in ipairs(wezterm.mux.get_workspace_names()) do
          if not seen[name] then
            table.insert(all, name)
            seen[name] = true
          end
        end
        for _, name in ipairs(ssh_workspaces) do
          if not seen[name] then
            table.insert(all, name)
          end
        end

        local current = window:active_workspace()
        local choices = {}
        for _, name in ipairs(all) do
          local label
          if name == current then
            label = wezterm.format {
              { Foreground = { Color = '#f4bf75' } },
              { Text = name .. ' *' },
            }
          elseif not active[name] then
            label = wezterm.format {
              { Foreground = { Color = '#6b6b6b' } },
              { Text = name },
            }
          else
            label = name
          end
          table.insert(choices, { id = name, label = label })
        end
        window:perform_action(act.InputSelector {
          title = 'Switch workspace',
          choices = choices,
          fuzzy = true,
          alphabet = '',
          action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
            if id then
              local spawn_opts = nil
              if id ~= 'local' then
                if is_windows then
                  spawn_opts = { args = { 'wsl.exe', '-e', 'env', 'WEZTERM_NO_TMUX=1', 'zsh', '-l' } }
                else
                  spawn_opts = { set_environment_variables = { WEZTERM_NO_TMUX = '1' } }
                end
              end
              inner_window:perform_action(act.SwitchToWorkspace {
                name = id,
                spawn = spawn_opts,
              }, inner_pane)
            end
          end),
        }, pane)
      end) },
    { key = 'c', action = act.PromptInputLine {
        description = 'New workspace name:',
        action = wezterm.action_callback(function(window, pane, line)
          if line then
            local spawn
            if is_windows then
              spawn = { args = { 'wsl.exe', '-e', 'env', 'WEZTERM_NO_TMUX=1', 'zsh', '-l' } }
            else
              spawn = { set_environment_variables = { WEZTERM_NO_TMUX = '1' } }
            end
            window:perform_action(act.SwitchToWorkspace {
              name = line,
              spawn = spawn,
            }, pane)
          end
        end),
      } },
    { key = '$', mods = 'SHIFT', action = act.PromptInputLine {
        description = 'Rename workspace:',
        action = wezterm.action_callback(function(window, pane, line)
          if line then
            window:mux_window():set_workspace(line)
          end
        end),
      } },
    { key = 'n', action = act.SwitchWorkspaceRelative(1) },
    { key = 'p', action = act.SwitchWorkspaceRelative(-1) },

    -- Passthrough: Ctrl+b Ctrl+b sends literal Ctrl+b
    { key = 'a', mods = 'CTRL', action = act.SendKey { key = 'a', mods = 'CTRL' } },
  },
}

return config
