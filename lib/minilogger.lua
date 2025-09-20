local expect = require "cc.expect".expect
local LOG_DIR = require "filesystem":programPath():at("logs")

local LOG_FILE = LOG_DIR:file("latest.log")
local OLD_LOG = LOG_DIR:file("old.log")

local _colors = colors

local function rotate_logs()
  if LOG_FILE:exists() then
    if OLD_LOG:exists() then OLD_LOG:delete() end
    LOG_FILE:moveTo(OLD_LOG)
    LOG_FILE:nullify()
  end
end
rotate_logs()

---@class minilogger
local minilogger = {
  ---@enum log_level
  LOG_LEVELS = {
    DEBUG = 0,
    OKAY = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
    FATAL = 5
  },
}
local LOG_LEVELS = minilogger.LOG_LEVELS

local LOG_LEVEL = LOG_LEVELS.INFO

local MAX_LOG_SIZE = 1024 * 256 -- 256 KB

local LOG_WIN = term.current()

---@type table<log_level, string>
local LEVELS_LOG = {}
for k, v in pairs(LOG_LEVELS) do
  LEVELS_LOG[v] = k
end

---@type table<string, true>
local disabled_origins = {}


-- Split line by newlines, including double-newlines.
local function split_lines(line)
  local lines = {}
  for l in line:gmatch("([^\n]*)\n?") do
    table.insert(lines, l)
  end
  return lines
end



local function log_to_file(level, origin, msg)
  if LOG_FILE:exists() and LOG_FILE:size() >= MAX_LOG_SIZE then
    rotate_logs()
  end

  local level_name = LEVELS_LOG[level]
  local initial_start = ("[%s]:%s: "):format(level_name, origin)
  local initial_between = ("\n[%s]:%s| "):format(level_name, (" "):rep(#origin))

  LOG_FILE:append(initial_start .. table.concat(split_lines(msg), initial_between) .. "\n")
end



--- Log a message to the log window.
---@param level log_level The level of the log message.
---@param origin string The origin of the log message.
---@param ... any The message to log.
local function log(level, origin, ...)
  expect(1, level, "number")
  expect(2, origin, "string")

  if level < LOG_LEVEL then
    return
  end

  if disabled_origins[origin] then
    return
  end

  if level < 0 or level > 5 or level % 1 ~= 0 then
    error("Invalid log level", 2)
  end

  local args = table.pack(...)
  for i = 1, args.n do
    local arg = args[i]
    args[i] = tostring(arg)
  end

  local old = term.redirect(LOG_WIN)

  local main_color = level == LOG_LEVELS.DEBUG and _colors.gray or _colors.white
  local level_color = level == LOG_LEVELS.DEBUG and _colors.gray or
    level == LOG_LEVELS.OKAY and _colors.green or
    level == LOG_LEVELS.INFO and _colors.white or
    level == LOG_LEVELS.WARN and _colors.yellow or
    level == LOG_LEVELS.ERROR and _colors.red or
    level == LOG_LEVELS.FATAL and _colors.white or
    _colors.white
  local background_color = level == LOG_LEVELS.FATAL and _colors.red or _colors.black

  term.setTextColor(main_color)
  term.setBackgroundColor(background_color)
  term.write("[")

  term.setTextColor(level_color)
  term.write(LEVELS_LOG[level])

  term.setTextColor(main_color)
  term.write("]: " .. origin .. ": ")

  local msg = table.concat(args, " ", 1, args.n)
  print(msg)

  log_to_file(level, origin, msg)

  term.redirect(old)
end

--- Log a message to the log window, using a format string.
---@param level log_level The level of the log message.
---@param origin string The origin of the log message.
---@param fmt string The format string.
---@param ... any The arguments to the format string.
local function logf(level, origin, fmt, ...)
  expect(1, level, "number")
  expect(2, origin, "string")
  expect(3, fmt, "string")

  log(level, origin, fmt:format(...))
end

--- Create a minilogger for a specific origin.
---@param origin string The origin of the logger.
---@return minilogger-logger minilogger The logger.
function minilogger.new(origin)
  expect(1, origin, "string")

  ---@class minilogger-logger
  local _minilogger = {
    debug = function(...)
      log(LOG_LEVELS.DEBUG, origin, ...)
    end,
    debugf = function(fmt, ...)
      logf(LOG_LEVELS.DEBUG, origin, fmt, ...)
    end,
    okay = function(...)
      log(LOG_LEVELS.OKAY, origin, ...)
    end,
    okayf = function(fmt, ...)
      logf(LOG_LEVELS.OKAY, origin, fmt, ...)
    end,
    info = function(...)
      log(LOG_LEVELS.INFO, origin, ...)
    end,
    infof = function(fmt, ...)
      logf(LOG_LEVELS.INFO, origin, fmt, ...)
    end,
    warn = function(...)
      log(LOG_LEVELS.WARN, origin, ...)
    end,
    warnf = function(fmt, ...)
      logf(LOG_LEVELS.WARN, origin, fmt, ...)
    end,
    error = function(...)
      log(LOG_LEVELS.ERROR, origin, ...)
    end,
    errorf = function(fmt, ...)
      logf(LOG_LEVELS.ERROR, origin, fmt, ...)
    end,
    fatal = function(...)
      log(LOG_LEVELS.FATAL, origin, ...)
    end,
    fatalf = function(fmt, ...)
      logf(LOG_LEVELS.FATAL, origin, fmt, ...)
    end
  }

  return _minilogger
end

--- Set the log level.
---@param level log_level The new log level.
function minilogger.set_log_level(level)
  expect(1, level, "number")

  if level < 0 or level > 4 or level % 1 ~= 0 then
    error("Invalid log level", 2)
  end

  LOG_LEVEL = level
end

--- Set the log window
---@param win ccTweaked.term.Redirect The new log window.
function minilogger.set_log_window(win)
  expect(1, win, "table")

  LOG_WIN = win
  win.setBackgroundColor(_colors.black)
  win.clear()
end

--- Set the colors
--- Only need the following:
--- - gray
--- - white
--- - green
--- - yellow
--- - red
--- - lightGray
--- - black
---@param colors table<string, ccTweaked.colors.color> The new colors.
function minilogger.set_colors(colors)
  expect(1, colors, "table")

  _colors = colors
end

--- Disables a source of logging.
---@param origin string The logger to disable.
function minilogger.disable(origin)
  expect(1, origin, "string")

  disabled_origins[origin] = true
end

--- Enables a source of logging.
---@param origin string The logger to enable.
function minilogger.enable(origin)
  expect(1, origin, "string")

  disabled_origins[origin] = nil
end

return minilogger
