---@type Wezterm
local wezterm = require 'wezterm'

---@class QuickLaunchConfig
---@field path_separator string
---@field launch_targets_path string
local M = {}

---@enum QuickLaunchActionType
local QuickLaunchActionType = {
  EDIT = 'edit',
  REMOTE = 'remote',
  RUN = 'run',
  SHELL = 'shell',
}

---@class QuickLaunchAction
---@field type QuickLaunchActionType
---@field label string?
---@field cwd string?
---@field args string[]?
---@field set_environment_variables { [string]: string }?

---@class QuickLaunchElement
---@field id string
---@field name string?
---@field icon string?
---@field menu_entry string

---@enum QuickLaunchPaneDirection
M.QuickLaunchPaneDirection = {
  UP = 'Up',
  DOWN = 'Down',
  LEFT = 'Left',
  RIGHT = 'Right',
}

---@class QuickLaunchPane: QuickLaunchElement
---@field direction QuickLaunchPaneDirection
---@field size number?
---@field action QuickLaunchAction

---@class QuickLaunchTab: QuickLaunchElement
---@field action QuickLaunchAction?
---@field panes QuickLaunchPane[]

---@class QuickLaunchWorkspace: QuickLaunchElement
---@field tabs QuickLaunchTab[]

---@class QuickLaunchTargets
---@field public workspaces QuickLaunchWorkspace[]
---@field public tabs QuickLaunchTab[]
---@field public panes QuickLaunchPane[]
---@field package _workspaces_dict table<string, QuickLaunchWorkspace>
---@field package _workspaces_max_choice_width number
---@field package _tabs_dict table<string, QuickLaunchTab>
---@field package _tabs_max_choice_width number
---@field package _panes_dict table<string, QuickLaunchPane>
---@field package _panes_max_choice_width number
---@field public get_workspace fun(self: QuickLaunchTargets, workspace_id: string): QuickLaunchWorkspace?
---@field public get_tab fun(self: QuickLaunchTargets, tab_id: string, workspace_id: string?): QuickLaunchTab?
---@field public get_pane fun(self: QuickLaunchTargets, pane_id: string, tab_id: string?, workspace_id: string?): QuickLaunchPane?
---@field public get_workspaces_choices_max_length fun(self: QuickLaunchTargets): number
---@field public get_tabs_choices_max_length fun(self: QuickLaunchTargets): number
---@field public get_panes_choices_max_length fun(self: QuickLaunchTargets): number

---@param element QuickLaunchWorkspace|QuickLaunchTab|QuickLaunchPane
---@param max_length number
---@return string
---@return number
local function make_element_menu_item(element, max_length)
  local label = element.action and element.action.label
  local action_type = element.action and element.action.type
  local name = label or element.name or element.id
  if element.direction or element.size then
    name = name
      .. '  ('
      .. element.direction
      .. ' '
      .. math.floor((element.size or 0.5) * 100 + 0.5)
      .. '%)'
  end
  local icon = element.icon
  if not icon then
    if action_type == QuickLaunchActionType.SHELL then
      icon = wezterm.nerdfonts.fa_folder_open_o -- ' '
    elseif action_type == QuickLaunchActionType.EDIT then
      icon = wezterm.nerdfonts.md_file_edit -- '󱇧 '
    elseif action_type == QuickLaunchActionType.REMOTE then
      icon = wezterm.nerdfonts.md_remote_desktop -- '󰢹 '
    elseif action_type == QuickLaunchActionType.RUN then
      icon = wezterm.nerdfonts.md_cog_play_outline -- '󱤶 '
    elseif not action_type then
      icon = wezterm.nerdfonts.md_collage .. ' ' -- '󰙀 '
    else
      icon = '  '
    end
  end
  local menu_item = icon .. ' ' .. name
  local menu_length = #menu_item + 4
  if menu_length < max_length then
    menu_length = max_length
  end
  return menu_item, menu_length
end

---@param self QuickLaunchTargets
---@param workspace_id string
---@return QuickLaunchWorkspace?
local function _targets_get_workspace(self, workspace_id)
  return self._workspaces_dict[workspace_id]
end

---@param self QuickLaunchTargets
---@param tab_id string
---@param workspace_id string?
---@return QuickLaunchTab?
local function _targets_get_tab(self, tab_id, workspace_id)
  if workspace_id then
    return self._tabs_dict[workspace_id .. '-' .. tab_id]
  end
  return self._tabs_dict[tab_id]
end

---@param self QuickLaunchTargets
---@param pane_id string
---@param tab_id string?
---@param workspace_id string?
---@return QuickLaunchPane?
local function _targets_get_pane(self, pane_id, tab_id, workspace_id)
  if tab_id or workspace_id then
    if tab_id and workspace_id then
      return self._panes_dict[workspace_id .. '-' .. tab_id .. '-' .. pane_id]
    end
    return self._panes_dict[(tab_id or workspace_id) .. '-' .. pane_id]
  end
  return self._panes_dict[pane_id]
end

---@param self QuickLaunchTargets
---@return number
local function _targets_get_workspaces_choices_max_length(self)
  return self._workspaces_max_choice_width
end

---@param self QuickLaunchTargets
---@return number
local function _targets_get_tabs_choices_max_length(self)
  return self._tabs_max_choice_width
end

---@param self QuickLaunchTargets
---@return number
local function _targets_get_panes_choices_max_length(self)
  return self._panes_max_choice_width
end

---@param targets QuickLaunchTargets
local function index_panes(targets)
  for _, pane in ipairs(targets.panes) do
    pane.menu_entry, targets._panes_max_choice_width =
      make_element_menu_item(pane, targets._panes_max_choice_width)
    targets._panes_dict[pane.id] = pane
  end
end

---@param targets QuickLaunchTargets
local function index_tabs(targets)
  for _, tab in ipairs(targets.tabs) do
    tab.menu_entry, targets._tabs_max_choice_width =
      make_element_menu_item(tab, targets._tabs_max_choice_width)
    targets._tabs_dict[tab.id] = tab
    if tab.panes then
      for _, pane in ipairs(tab.panes) do
        pane.menu_entry, targets._panes_max_choice_width =
          make_element_menu_item(pane, targets._panes_max_choice_width)
        pane.id = tab.id .. '-' .. pane.id
        targets._panes_dict[tab.id .. '-' .. pane.id] = pane
      end
    else
      tab.panes = {}
    end
  end
end

---@param targets QuickLaunchTargets
local function index_workspaces(targets)
  for _, ws in ipairs(targets.workspaces) do
    ws.menu_entry, targets._workspaces_max_choice_width =
      make_element_menu_item(ws, targets._workspaces_max_choice_width)
    targets._workspaces_dict[ws.id] = ws
    if ws.tabs then
      for _, tab in ipairs(ws.tabs) do
        tab.menu_entry, targets._tabs_max_choice_width =
          make_element_menu_item(tab, targets._tabs_max_choice_width)
        tab.id = ws.id .. '-' .. tab.id
        targets._tabs_dict[ws.id .. '-' .. tab.id] = tab
        if tab.panes then
          for _, pane in ipairs(tab.panes) do
            pane.menu_entry, targets._panes_max_choice_width =
              make_element_menu_item(pane, targets._panes_max_choice_width)
            pane.id = ws.id .. '-' .. tab.id .. '-' .. pane.id
            targets._panes_dict[ws.id .. '-' .. tab.id .. '-' .. pane.id] = pane
          end
        else
          tab.panes = {}
        end
      end
    else
      ws.tabs = {}
    end
  end
end

---@param targets QuickLaunchTargets
---@return QuickLaunchTargets
local function initialize_targets(targets)
  targets.workspaces = targets.workspaces or {}
  targets.tabs = targets.tabs or {}
  targets.panes = targets.panes or {}

  targets._workspaces_dict = {}
  targets._tabs_dict = {}
  targets._panes_dict = {}

  targets._workspaces_max_choice_width = 0
  targets._tabs_max_choice_width = 0
  targets._panes_max_choice_width = 0

  index_panes(targets)
  index_tabs(targets)
  index_workspaces(targets)

  targets.get_workspace = _targets_get_workspace
  targets.get_tab = _targets_get_tab
  targets.get_pane = _targets_get_pane

  targets.get_workspaces_choices_max_length = _targets_get_workspaces_choices_max_length
  targets.get_tabs_choices_max_length = _targets_get_tabs_choices_max_length
  targets.get_panes_choices_max_length = _targets_get_panes_choices_max_length

  return targets
end

---@return QuickLaunchTargets?
function M.read_targets()
  ---@type QuickLaunchTargets
  local targets
  if not M.path_separator then
    M.path_separator = '/'
  end
  if not M.launch_targets_path then
    M.launch_targets_path = wezterm.config_dir .. M.path_separator .. 'quick-launch-targets.yaml'
  end

  local file = io.open(M.launch_targets_path, 'r')
  if file then
    if M.launch_targets_path:sub(-4) == 'json' then
      targets = wezterm.serde.json_decode(file:read '*a')
    elseif M.launch_targets_path:sub(-4) == 'yaml' or M.launch_targets_path:sub(-3) == 'yml' then
      targets = wezterm.serde.yaml_decode(file:read '*a')
    elseif M.launch_targets_path:sub(-4) == 'toml' then
      targets = wezterm.serde.toml_decode(file:read '*a')
    else
      wezterm.log_error('[QuickLaunch]: Unknown config file "' .. M.launch_targets_path .. '"')
    end
    io.close(file)
  else
    wezterm.log_warn('Could not read the "' .. M.launch_targets_path .. '" file')
    return nil
  end
  return initialize_targets(targets)
end

return M
