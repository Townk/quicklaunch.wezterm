-- SPDX-License-Identifier: MIT
-- Copyright © 2024 Thiago Alves

---@type Wezterm
local wezterm = require 'wezterm'

local M = {}

local separator = package.config:sub(1, 1) == '\\' and '\\' or '/'
local plugin_dir
local plugin_name = 'quicklaunch.wezterm'
for _, plugin in ipairs(wezterm.plugin.list()) do
  if plugin.url:sub(-#plugin_name) == plugin_name then
    plugin_dir = plugin.plugin_dir
    break
  end
end

package.path = package.path
  .. ';'
  .. plugin_dir
  .. separator
  .. 'plugin'
  .. separator
  .. '?.lua'

local ql_config = require 'quick-launch.config'

---Main function to apply required configurations to the user's configuration.
---@param wezterm_config Config
---@param custom_config QuickLaunchConfig?
function M.apply_to_config(wezterm_config, custom_config)
  ql_config.path_separator = (custom_config and custom_config.path_separator) or ql_config.path_separator
  ql_config.launch_targets_path = (custom_config and custom_config.launch_targets_path)
    or ql_config.launch_targets_path
end

M.actions = require 'quick-launch.actions'

return M
