---@diagnostic disable:assign-type-mismatch
---@type Wezterm
local wezterm = require 'wezterm'
local config = require 'quick-launch.config'
local utils = require 'quick-launch.utils'

local M = {}

---@param pane QuickLaunchPane
---@return SpawnCommand?
local function get_pane_command(pane)
  local split_command = utils.make_spawn_command(pane)
  if split_command then
    split_command['direction'] = pane.direction or 'Right'
    split_command['size'] = pane.size or 0.5
  end
  return split_command
end

---@param mux_pane Pane
---@param pane QuickLaunchPane
---@return Pane?
local function split_pane(mux_pane, pane)
  local split_command = get_pane_command(pane)
  if split_command then
    return mux_pane:split(split_command)
  end
end

local function split_extra_panes(ql_tab, mux_pane)
  for idx, ql_pane in ipairs(ql_tab.panes) do
    if idx > 1 or ql_tab.action then
      mux_pane = split_pane(mux_pane, ql_pane)
    end
  end
end

---@param targets QuickLaunchTargets
local function open_workspace_action(targets, id)
  local selected_ws = targets:get_workspace(id)
  if selected_ws then
    for _, mux_ws in ipairs(wezterm.mux.get_workspace_names()) do
      if mux_ws == selected_ws.name or mux_ws == selected_ws.id then
        wezterm.mux.set_active_workspace(mux_ws)
        return
      end
    end
    local ws_name = selected_ws.name or selected_ws.id
    local ws_command = utils.make_spawn_command(selected_ws)
    if ws_command then
      ws_command['workspace'] = ws_name
      local mux_tab, mux_pane, mux_window = wezterm.mux.spawn_window(ws_command)
      ---@cast mux_tab MuxTabObj
      ---@cast mux_pane Pane
      ---@cast mux_window MuxWindow

      wezterm.mux.set_active_workspace(ws_name)
      for t_idx, ql_tab in ipairs(selected_ws.tabs) do
        local first_pane
        if t_idx > 1 then
          local tab_command = utils.make_spawn_command(ql_tab)
          if tab_command then
            _, mux_pane, _ = mux_window:spawn_tab(tab_command)
            first_pane = mux_pane
          end
        else
          first_pane = mux_pane
        end
        if first_pane then
          split_extra_panes(ql_tab, mux_pane)
          first_pane:activate()
        end
      end
      mux_tab:activate()
    else
      wezterm.log_error('[QuickLaunch]: Cannot create a SpawnCommand for workspace', ws_name)
    end
  else
    for _, mux_ws in ipairs(wezterm.mux.get_workspace_names()) do
      if mux_ws == id then
        wezterm.mux.set_active_workspace(mux_ws)
        return
      end
    end
    wezterm.log_warn(
      '[QuickLaunch]: Selected workspace cannot be found in the',
      config.launch_targets_path,
      'file'
    )
  end
end

---@param targets QuickLaunchTargets
local function make_open_workspace_action(targets)
  return wezterm.action_callback(function(window, pane, id, label)
    if id and label then
      if id == '__NEW_WORKSPACE__' then
        window:perform_action(wezterm.action.SwitchToWorkspace, pane)
        return
      end
      open_workspace_action(targets, id)
    else
      wezterm.log_info '[QuickLaunch]: Open workspace action canceled'
    end
  end)
end

---@param targets QuickLaunchTargets
---@param id string
local function open_tab_action(window, targets, id)
  local selected_tab = targets:get_tab(id)
  if selected_tab then
    local selected_tab_title = selected_tab.name or selected_tab.id
    for _, tab in ipairs(window:mux_window():tabs()) do
      if tab:get_title() == selected_tab_title then
        tab:activate()
        return
      end
    end
    local tab_command = utils.make_spawn_command(selected_tab)
    if tab_command then
      local _, mux_pane, _ = window:mux_window():spawn_tab(tab_command)
      split_extra_panes(selected_tab, mux_pane)
      mux_pane:activate()
    else
      wezterm.log_error(
        '[QuickLaunch]: Cannot create a SpawnCommand for tab',
        selected_tab.name or selected_tab.id
      )
    end
  else
    wezterm.log_warn(
      '[QuickLaunch]: Selected tab "' .. id .. '" cannot be found in the',
      config.launch_targets_path,
      'file'
    )
  end
end

---@param targets QuickLaunchTargets
local function make_open_tab_action(targets)
  return wezterm.action_callback(function(window, _, id, label)
    if id and label then
      open_tab_action(window, targets, id)
    else
      wezterm.log_info '[QuickLaunch]: Open tab action canceled'
    end
  end)
end

---@param targets QuickLaunchTargets
local function open_pane_action(window, targets, id)
  local selected_pane = targets:get_pane(id)
  if selected_pane then
    local mux_tab = window:mux_window():active_tab()
    for _, mux_pane in ipairs(mux_tab:panes()) do
      if mux_pane:get_user_vars().paneid == id then
        mux_pane:activate()
        return
      end
    end
    split_pane(mux_tab:active_pane(), selected_pane)
  else
    wezterm.log_warn(
      '[QuickLaunch]: Selected pane cannot be found in the',
      config.launch_targets_path,
      'file'
    )
  end
end

---@param targets QuickLaunchTargets
local function make_open_pane_action(targets)
  return wezterm.action_callback(function(window, _, id, label)
    if id and label then
      open_pane_action(window, targets, id)
    else
      wezterm.log_info '[QuickLaunch]: Open split pane action canceled'
    end
  end)
end

---@param target_workspace string?
---@return Action
function M.open_workspace(target_workspace)
  return wezterm.action_callback(function(window, pane)
    local targets = config.read_targets()
    if targets then
      if target_workspace then
        open_workspace_action(targets, target_workspace)
      else
      end
      window:perform_action(
        wezterm.action.InputSelector {
          title = 'Select a workspace to open:',
          description = utils.make_menu_header_select('Open Workspace', 'workspace', 'open'),
          fuzzy_description = utils.make_menu_header_fuzzy('Open Workspace', 'workspace', 'open'),
          choices = utils.make_workspaces_choices(targets),
          action = make_open_workspace_action(targets),
        },
        pane
      )
    end
  end)
end

---@param target_tab string?
---@return Action
function M.open_tab(target_tab)
  return wezterm.action_callback(function(window, pane)
    local targets = config.read_targets()
    if targets then
      if target_tab then
        open_tab_action(window, targets, target_tab)
      else
        window:perform_action(
          wezterm.action.InputSelector {
            title = 'Select a tab to open:',
            description = utils.make_menu_header_select('Open Tab', 'tab', 'open'),
            fuzzy_description = utils.make_menu_header_fuzzy('Open Tab', 'tab', 'open'),
            choices = utils.make_tabs_choices(targets),
            action = make_open_tab_action(targets),
          },
          pane
        )
      end
    end
  end)
end

---@param target_pane string?
---@return Action
function M.open_pane(target_pane)
  return wezterm.action_callback(function(window, pane)
    local targets = config.read_targets()
    if targets then
      if target_pane then
        open_pane_action(window, targets, target_pane)
      else
        window:perform_action(
          wezterm.action.InputSelector {
            title = 'Select a split pane to open:',
            description = utils.make_menu_header_select('Open Split Pane', 'pane', 'split'),
            fuzzy_description = utils.make_menu_header_fuzzy('Open Split Pane', 'pane', 'split'),
            choices = utils.make_panes_choices(window, targets),
            action = make_open_pane_action(targets),
          },
          pane
        )
      end
    end
  end)
end

return M
