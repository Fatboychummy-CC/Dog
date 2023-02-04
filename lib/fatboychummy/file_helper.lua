local QIT = require "QIT"

---@class file_helper
local file = {}

--- Return a table of lines from a file.
---@param filename string The file to be read.
---@param default string[]? The value returned when the file does not exist.
---@return string[] lines
function file.getLines(filename, default)
  local lines = QIT()

  if not fs.exists(filename) then
    return default or {}
  end

  for line in io.lines(filename) do
    lines:Insert(line)
  end

  return lines:Clean()
end

--- Return a string containing the entirety of the file read.
---@param filename string The file to be read.
---@param default string? The value returned when the file does not exist.
---@return string data
function file.getAll(filename, default)
  local h = io.open(filename, 'r')

  if not h then
    return default or ""
  end

  local data = h:read "*a"
  h:close()

  return data
end

--- Write data to a file
---@param filename string The file to write to.
---@param data string The data to write.
function file.write(filename, data)
  local h, err = io.open(filename, 'w')

  if not h then
    error(("Failed to open '%s' for writing."):format(err), 2)
  end

  h:write(data):close()
end

--- Return a string containing the entirety of the file read.
---@param filename string The file to be read.
---@param default any The value returned when th e file does not exist.
---@return any data
function file.unserialize(filename, default)
  local h = io.open(filename, 'r')

  if not h then
    return default or ""
  end

  local data = textutils.unserialise(h:read "*a")
  h:close()

  return data
end

--- Write data to a file
---@param filename string The file to write to.
---@param data any The data to write, this will be serialized.
---@param compact boolean? Use textutils.serialize's compact mode.
function file.serialize(filename, data, compact)
  local h, err = io.open(filename, 'w')

  if not h then
    error(("Failed to open '%s' for writing."):format(err), 2)
  end

  h:write(textutils.serialize(data, { compact = compact })):close()
end

return file
