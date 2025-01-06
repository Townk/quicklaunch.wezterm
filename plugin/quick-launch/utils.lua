---@type Wezterm
local wezterm = require 'wezterm'
local config = require 'quick-launch.config'

local M = {}

---@param targets QuickLaunchTargets
---@return QuickLaunchWorkspace?
function M.get_active_workspace(targets)
  local ws_name = wezterm.mux.get_active_workspace()
  local active_workspace = targets:get_workspace(ws_name)
  if not active_workspace then
    for _, ws in ipairs(targets.workspaces) do
      if ws.name == ws_name then
        active_workspace = ws
        break
      end
    end
  end
  return active_workspace
end

---@param targets QuickLaunchTargets
---@param name_index table<string, string>
---@return QuickLaunchWorkspace?
function M.index_workspace_names(targets, name_index)
  local ws_name = wezterm.mux.get_active_workspace()
  local active_workspace
  for _, ws in ipairs(targets.workspaces) do
    name_index[ws.name] = ws
    if ws.id == ws_name or ws.name == ws_name then
      active_workspace = ws
    end
  end
  return active_workspace
end

---@param tabs QuickLaunchTab[]
---@param title string
local function find_matching_tab(tabs, title)
  for _, tab in ipairs(tabs) do
    if tab.name == title or tab.id == title then
      return tab
    end
  end
  return nil
end

---@param window Window
---@param targets QuickLaunchTargets
---@param active_workspace QuickLaunchWorkspace?
---@return QuickLaunchTab?
function M.get_active_tab(window, targets, active_workspace)
  local ws_id
  if active_workspace then
    ws_id = active_workspace.id
  else
    active_workspace = M.get_active_workspace(targets)
    if active_workspace then
      ws_id = active_workspace.id
    end
  end
  local mux_tab = window:active_tab()
  local mux_tab_title = mux_tab:get_title()
  local active_tab = targets:get_tab(mux_tab_title)
    or (ws_id and targets:get_tab(mux_tab_title, ws_id))
    or find_matching_tab(targets.tabs, mux_tab_title)
    or (active_workspace and find_matching_tab(active_workspace.tabs, mux_tab_title))
  return active_tab
end

---@class InputSelectorChoice
---@field id string
---@field label string

---@param choices InputSelectorChoice[]
---@param id string
---@param label string
---@param max_length number
local function insert_choice(choices, id, label, max_length)
  for _, choice in ipairs(choices) do
    if choice.id == id then
      return
    end
  end
  table.insert(choices, {
    id = id,
    label = wezterm.pad_right(label, max_length),
  })
end

---@param choices InputSelectorChoice[]
---@param elements QuickLaunchElement[]
---@param max_length number
local function insert_all_choice(choices, elements, max_length)
  for _, element in ipairs(elements) do
    insert_choice(choices, element.id, element.menu_entry, max_length)
  end
end

---@param targets QuickLaunchTargets
---@return InputSelectorChoice[]
function M.make_workspaces_choices(targets)
  ---@type InputSelectorChoice[]
  local choices = {}
  local ws_name_index = {}
  local max_length = targets:get_workspaces_choices_max_length()
  local active_ws = M.index_workspace_names(targets, ws_name_index)
  local remove_first = false
  if not active_ws then
    active_ws = targets:get_workspace(wezterm.mux.get_active_workspace())
  end
  if active_ws then
    table.insert(choices, { id = active_ws.id, label = active_ws.menu_entry })
    remove_first = true
  end
  local active_ws_name = wezterm.mux.get_active_workspace()

  for _, known_ws in ipairs(wezterm.mux.get_workspace_names()) do
    if not active_ws or known_ws ~= active_ws.id then
      local ql_ws = ws_name_index[known_ws] or targets:get_workspace(known_ws)
      if ql_ws then
        insert_choice(choices, ql_ws.id, ql_ws.menu_entry, max_length)
      else
        if known_ws ~= active_ws_name then
          insert_choice(
            choices,
            known_ws,
            wezterm.nerdfonts.md_collage .. '  ' .. known_ws,
            max_length
          )
        end
      end
    end
  end

  insert_all_choice(choices, targets.workspaces, max_length)

  insert_choice(
    choices,
    '__NEW_WORKSPACE__',
    '󱂬  New workspace with a "random" name',
    max_length
  )

  if remove_first then
    choices = { table.unpack(choices, 2) }
  end

  return choices
end

---@param targets QuickLaunchTargets
---@return InputSelectorChoice[]
function M.make_tabs_choices(targets)
  local choices = {}
  local max_length = targets:get_tabs_choices_max_length()
  local active_ws = M.get_active_workspace(targets)

  insert_all_choice(choices, targets.tabs, max_length)
  if active_ws then
    insert_all_choice(choices, active_ws.tabs, max_length)
  end

  return choices
end

---@param window Window
---@param targets QuickLaunchTargets
---@return InputSelectorChoice[]
function M.make_panes_choices(window, targets)
  local choices = {}
  local max_length = targets:get_panes_choices_max_length()
  local active_tab = M.get_active_tab(window, targets)

  insert_all_choice(choices, targets.panes, max_length)
  if active_tab then
    insert_all_choice(choices, active_tab.panes, max_length)
  end

  return choices
end

---@param action QuickLaunchAction
---@param element QuickLaunchWorkspace|QuickLaunchTab|QuickLaunchPane
---@return string
function M.cmd_prefix(action, element)
  local cmd_prefix = ''
  if action.cwd then
    cmd_prefix = 'cd ' .. action.cwd .. '; '
  end

  if element.action and element.direction then
    -- This element is a pane, and we must set a user variable using `printf`
    cmd_prefix = cmd_prefix
      .. 'printf "\x1b]1337;SetUserVar=paneid=%s\x07\x1b]1337;SetUserVar=panetitle=%s\x07" '
      .. '`echo -n "'
      .. element.id
      .. '" | base64` '
      .. '`echo -n "'
      .. (element.name or element.id)
      .. '" | base64`; '
  else -- if element.action or element.panes then
    -- This element is a tab or a workspace, and we must set the tab title
    -- using `wezterm cli`
    cmd_prefix = cmd_prefix
      .. 'wezterm cli set-tab-title "'
      .. (element.name or element.id)
      .. '"; '
  end
  return cmd_prefix
end

---@param element QuickLaunchWorkspace|QuickLaunchTab|QuickLaunchPane
---@return SpawnCommand?
function M.make_spawn_command(element)
  local spawn_cmd = {}
  -- If the element has an `action` field, then we should use it directly;
  -- otherwise, the element might be a tab with only panes, or a workspace,
  -- which, in turn, might have a tab with an action defined, or just panes.
  local action = element.action
    or (element.panes and #element.panes > 0 and element.panes[1].action)
    or (
      element.tabs
      and #element.tabs > 0
      and (
        element.tabs[1].action or (#element.tabs[1].panes > 0 and element.tabs[1].panes[1].action)
      )
    )

  if not action then
    wezterm.log_error(
      '[QuickLauncher]: Trying to build a SpawnCommand for the element',
      element.id,
      ', but such element does not have an action associated with it'
    )
    return nil
  end

  spawn_cmd['cwd'] = action.cwd
  spawn_cmd['label'] = action.label
  if action.set_environment_variables then
    spawn_cmd['set_environment_variables'] = action.set_environment_variables
  end
  spawn_cmd['domain'] = 'CurrentPaneDomain'
  if action.type ~= 'shell' then
    spawn_cmd['args'] = { os.getenv 'SHELL', '-c' }
  end
  local cmd_prefix = M.cmd_prefix(action, element)

  if action.type == 'edit' then
    local files_to_edit = {}
    for _, file_path in ipairs(action.args) do
      local first_char = action.args[1]:sub(1, 1)
      if first_char ~= '/' and first_char ~= '~' and first_char ~= '\\' then
        table.insert(
          files_to_edit,
          ((action.cwd and (action.cwd .. config.path_separator)) or '') .. file_path
        )
      else
        table.insert(files_to_edit, file_path)
      end
    end
    if files_to_edit then
      table.insert(spawn_cmd['args'], cmd_prefix .. 'nvim ' .. table.concat(files_to_edit, ' '))
    else
      table.insert(spawn_cmd['args'], cmd_prefix .. 'nvim')
    end
  elseif action.type == 'remote' then
    if action.args then
      table.insert(spawn_cmd['args'], 'ssh ' .. table.concat(action.args, ' '))
    else
      wezterm.log_error '[QuickEdit] Trying to spawn an SSH command without a host argument'
      return nil
    end
  elseif action.type == 'run' then
    if action.args then
      table.insert(spawn_cmd['args'], cmd_prefix .. table.concat(action.args, ' '))
    else
      wezterm.log_error '[QuickEdit] Trying to spawn a run command without any arguments'
      return nil
    end
  end
  return spawn_cmd
end

function M.make_menu_header_select(overlay_title, element_type, action_name)
  return wezterm.format {
    { Attribute = { Intensity = 'Bold' } },
    { Foreground = { Color = '#E7C787' } },
    { Text = '# ' .. overlay_title .. '\r\n\n' },
    { Foreground = { Color = '#61afef' } },
    { Text = 'Select a ' .. element_type .. ' to ' .. action_name .. ':\r\n' },
    { Attribute = { Intensity = 'Normal' } },
    { Foreground = { Color = '#565C64' } },
    { Text = 'ᵏⱼ,󰓢: prev/next  ⏎: select  ⎋: cancel  /: fuzzy\r\n' },
    -- { Text = 'j,↓: next  k,↑: prev  ⏎: select  ⎋: cancel  /: fuzzy\r\n' },
    'ResetAttributes',
  }
end

function M.make_menu_header_fuzzy(overlay_title, element_type, action_name)
  return wezterm.format {
    { Attribute = { Intensity = 'Bold' } },
    { Foreground = { Color = '#E7C787' } },
    { Text = '# ' .. overlay_title .. '\r\n\n' },
    { Foreground = { Color = '#61afef' } },
    { Text = 'Search a ' .. element_type .. ' to ' .. action_name .. ': \x1b[s\r\n' },
    { Attribute = { Intensity = 'Normal' } },
    { Foreground = { Color = '#565C64' } },
    { Text = '\x1b[K\r󰓢: prev/next  ⏎: select  ⎋: cancel\r\n\x1b[u' },
    -- { Text = '\x1b[K\r↓: next  ↑: prev  ⏎: select  ⎋: cancel\r\n\x1b[u' },
    'ResetAttributes',
  }
end

return M
