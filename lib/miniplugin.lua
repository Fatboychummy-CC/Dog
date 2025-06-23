--- MiniPlugin
--- 
--- MiniPlugin is a simple plugin system for Lua programs (targeting CC:Tweaked).

local expect = require "cc.expect".expect

--- This represents a base class for plugins. Your program should define a child class that extends this base class.
---@class MiniPlugin.Plugin
---@field name string The name of the plugin.
---@field description string A short description of the plugin.
---@field version string The version of the plugin.
---@field author string? The author of the plugin.
---@field config table A table containing the plugin's configuration. This can be saved alongside program state.
---@field tasks table<string, fun(self:self, ...:any)> A table containing the plugin's tasks. These are functions that will run alongside the main program. Please note that tasks continue running even after the `:exit()` event is dispatched, and is only killed when the entire plugin system stops.
---@field init nil|fun(self:self) This should initialize your plugin, and is called immediately upon loading the plugin.
---@field exit nil|fun(self:self) This should clean up your plugin, and is called immediately before unloading the plugin.
---@field ready nil|fun(self:self) This should be called by the program when the program itself is ready.


---@class MiniPlugin
---@field loaded table<string, MiniPlugin.Plugin> A table containing all loaded plugins, indexed by their names.
---@field unloaded table<string, MiniPlugin.Plugin> A table containing unloaded plugins, indexed by their names.
local MiniPlugin = {
  loaded = {},
  unloaded = {},
  running = false,
}

local mp_mt = {
  __index = function(self, k)
    error(("Plugin '%s' does not have field '%s'"):format(self.name, k), 2)
  end
}



--- Loads a plugin by its name.
---@param name string The name of the plugin to load.
---@return MiniPlugin.Plugin instance The loaded plugin instance.
function MiniPlugin.load(name)
  expect(1, name, "string")

  if MiniPlugin.running then
    error("Cannot load plugins while MiniPlugin is running", 2)
  end

  if MiniPlugin.loaded[name] then
    error(("Plugin '%s' is already loaded"):format(name), 2)
  end
  if not MiniPlugin.unloaded[name] then
    error(("Plugin '%s' is not registered"):format(name), 2)
  end

  local plugin = MiniPlugin.unloaded[name]
  plugin:init()

  MiniPlugin.loaded[name] = plugin
  MiniPlugin.unloaded[name] = nil
  return plugin
end



--- Load all registered plugins.
function MiniPlugin.loadAll()
  for name in pairs(MiniPlugin.unloaded) do
    MiniPlugin.load(name)
  end
end



--- Unload a plugin by name.
---@param name string The name of the plugin to unload.
function MiniPlugin.unload(name)
  expect(1, name, "string")

  if not MiniPlugin.loaded[name] then
    --error(("Plugin '%s' is not loaded"):format(name), 2)
    return -- This might be better?
  end

  local plugin = MiniPlugin.loaded[name]
  plugin:exit()

  MiniPlugin.unloaded[name] = plugin
  MiniPlugin.loaded[name] = nil
end



--- Unload all loaded plugins.
function MiniPlugin.unloadAll()
  for name in pairs(MiniPlugin.loaded) do
    MiniPlugin.unload(name)
  end
end



--- Get a loaded plugin by name.
---@param name string The name of the plugin.
---@return MiniPlugin.Plugin? instance The loaded plugin, or nil if not found.
function MiniPlugin.get(name)
  expect(1, name, "string")

  return MiniPlugin.loaded[name]
end



--- Builds a plugin from a file. Note that this does not load the plugin.
---@param file string The path to the plugin file.
---@return MiniPlugin.Plugin plugin The built plugin instance.
function MiniPlugin.buildFromFile(file)
  expect(1, file, "string")

  local f, err = fs.open(file, "r")
  if not f then
    error(("Failed to open plugin file '%s': %s"):format(file, err), 2)
  end

  local content = f.readAll()
  f.close()
  if not content or content == "" then
    error(("Plugin file '%s' is empty or could not be read"):format(file), 2)
  end

  local plugin, err = load(content, "@" .. file, "t", _ENV)

  if not plugin then
    error(("Failed to load plugin from file '%s': %s"):format(file, err), 2)
  end

  local instance, err = pcall(plugin)
  if not instance then
    error(("Plugin file '%s': %s"):format(file, err), 2)
  end

  if not instance or type(instance) ~= "table" or not instance.name then
    error(("Plugin file '%s' did not return a valid plugin instance"):format(file), 2)
  end

  if MiniPlugin.loaded[instance.name] or MiniPlugin.unloaded[instance.name] then
    error(("Plugin '%s' is already registered"):format(instance.name), 2)
  end

  return setmetatable(instance, mp_mt)
end



--- Builds all plugins from a directory.
---@param dir string The directory containing plugin files.
function MiniPlugin.buildFromDirectory(dir)
  expect(1, dir, "string")

  if not fs.isDir(dir) then
    error(("Directory '%s' does not exist or is not a directory"):format(dir), 2)
  end

  local files = fs.list(dir)
  if not files then
    error(("Failed to list files in directory '%s'"):format(dir), 2)
  end

  for _, file in ipairs(files) do
    local full_path = fs.combine(dir, file)
    if fs.isDir(full_path) then
      -- search the sub-directory for an init.lua file.
      local init_file = fs.combine(full_path, "init.lua")
      if fs.exists(init_file) then
        MiniPlugin.buildFromFile(init_file)
      end
    else
      MiniPlugin.buildFromFile(full_path)
    end
  end
end



--- Dispatches an event to all loaded plugins.
---@param event string The name of the event to dispatch.
---@param ... any Additional arguments to pass to the event handlers.
function MiniPlugin.dispatchEvent(event, ...)
  expect(1, event, "string")

  for _, plugin in pairs(MiniPlugin.loaded) do
    if type(plugin[event]) == "function" then
      plugin[event](plugin, ...)
    end
  end
end



--- Stop the plugin system.
function MiniPlugin.stop()
  if not MiniPlugin.running then
    error("MiniPlugin is not running", 2)
  end

  MiniPlugin.running = false
  os.queueEvent("miniplugin_stop")
end



--- Run the plugin system. This will load all plugins.
function MiniPlugin.run()
  if MiniPlugin.running then
    error("MiniPlugin is already running", 2)
  end

  MiniPlugin.loadAll()
  MiniPlugin.running = true

  --- Gathers all tasks from all loaded plugins. Runs them in parallel.
  local function gather_tasks()
    local tasks = {}
    for _, plugin in pairs(MiniPlugin.loaded) do
      for name, task in pairs(plugin.tasks) do
        if type(task) == "function" then
          table.insert(tasks, task)
        else
          error(("Task '%s' in plugin '%s' is not a function"):format(name, plugin.name), 2)
        end
      end
    end

    parallel.waitForAll(
      function() while true do os.pullEvent() end end, -- Dummy task to keep the parallel loop alive.
      table.unpack(tasks, 1, #tasks)
    )
  end



  parallel.waitForAny(
    function()
      os.pullEvent("miniplugin_stop")
      MiniPlugin.unloadAll()
    end,
    gather_tasks
  )

  MiniPlugin.running = false

  if #MiniPlugin.loaded > 0 then
    MiniPlugin.unloadAll()
  end
end



return MiniPlugin
