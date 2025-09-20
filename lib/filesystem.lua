--- A better alternative to the file_helper library. Each returned object is a
--- "file" object, that can be further used in other functions.
---
--- This library is a wrapper around the `fs` library, and provides a more
--- object-oriented approach to working with files and directories. It is very
--- quick and intuitive to use.

local expect = require "cc.expect".expect

---@alias FS_FilePath string|FS_Root

--- An instance of a file object. By default, this object refers to `/`.
---@class FS_Root
---@field path string The path to the file.
---@operator concat(FS_FilePath): FS_Root
---@operator len: integer
local filesystem = {
  path = "",
  __SENTINEL = {}
}

local ROOT_SENTINEL = {}
local root_metatable

--- Create a new instance of the filesystem object.
---@param path FS_FilePath? The path to the file.
local function new(path)
  return setmetatable({
    path = path and tostring(path) or ""
  }, root_metatable)
end

local function sentinel(obj)
  if obj.__SENTINEL ~= ROOT_SENTINEL then
    error("Filesystem objects use ':' syntax.", 3)
  end
end

local function sentinel_other(arg_index, obj)
  if type(obj) ~= "string" and (type(obj) == "table" and obj.__SENTINEL ~= ROOT_SENTINEL) then
    error(
      ("bad argument #%d (expected string or filesystem, got %s)"):format(arg_index, type(obj)),
      3
    )
  end
end

root_metatable = {
  __index = filesystem,
  __tostring = function(self)
    return self.path
  end,
  __concat = function(self, other)
    sentinel_other(2, other)

    return new(fs.combine(tostring(self), tostring(other)))
  end,
  __len = function(self)
    return #tostring(self)
  end
}

--- Create an object instance based on the path. This method *extends* the
--- current path (i.e: `self.path .. path`), unless the given path is absolute.
---
--- Works the same as concatenating a filesystem object with a string (or
--- another filesystem object).
---
---
---@param path FS_FilePath The path to the file.
---@return FS_Root instance The object instance.
function filesystem:at(path)
  sentinel(self)
  sentinel_other(1, path)

  return self .. path
end

--- Create an object instance based on an absolute path.
---@param path FS_FilePath The path to the file.
---@return FS_Root instance The object instance.
function filesystem:absolute(path)
  sentinel(self)
  sentinel_other(1, path)

  return new(path)
end

--- Create an object instance based on the directory the program is running in.
---@return FS_Root instance The object instance.
function filesystem:programPath()
  sentinel(self)

  local dir = fs.getDir(shell.getRunningProgram())
  return new(dir)
end

--- Get a file object for a given filename within the instance directory.
---@param path FS_FilePath? The path to the file.
---@return FS_File file The file object.
function filesystem:file(path)
  sentinel(self)
  sentinel_other(1, path)
  path = path or ""

  --- An instance of a file object. This object refers to a literal file or
  --- directory on the filesystem.
  ---@class FS_File : FS_Root
  local file = self .. path

  --- Get the entire contents of the file.
  ---@return string contents The contents of the file.
  ---@overload fun():nil, string Upon error.
  function file:readAll()
    sentinel(self)

    local handle, err = fs.open(tostring(self), "r")
    if not handle then
      ---@cast err string
      return nil, err
    end

    local contents = handle.readAll()
    handle.close()

    return contents
  end

  --- Write data to the file. This method will overwrite the file if it already
  --- exists.
  ---@param data string The data to write to the file.
  function file:write(data)
    sentinel(self)
    expect(1, data, "string")

    local handle, err = fs.open(tostring(self), "w")
    if not handle then
      ---@cast err string
      error(err, 2)
    end

    handle.write(data)
    handle.close()
  end

  --- Append data to the file. This method will create the file if it doesn't
  --- exist.
  ---@param data string The data to append to the file.
  function file:append(data)
    sentinel(self)
    expect(1, data, "string")

    local handle, err = fs.open(tostring(self), "a")
    if not handle then
      ---@cast err string
      error(err, 2)
    end

    handle.write(data)
    handle.close()
  end

  --- Open the file in the given mode.
  ---@param mode "r"|"rb"|"w"|"wb"|"a"|"ab" The mode to open the file in.
  ---@return ccTweaked.fs.ReadHandle|ccTweaked.fs.BinaryReadHandle|ccTweaked.fs.WriteHandle|ccTweaked.fs.BinaryWriteHandle? handle The file handle.
  ---@return string? error The error message if the file could not be opened.
  ---@overload fun(mode: "r"):ccTweaked.fs.ReadHandle?, string?
  ---@overload fun(mode: "rb"):ccTweaked.fs.BinaryReadHandle?, string?
  ---@overload fun(mode: "w"|"a"):ccTweaked.fs.WriteHandle?, string?
  ---@overload fun(mode: "wb"|"ab"):ccTweaked.fs.BinaryWriteHandle?, string?
  ---@nodiscard
  function file:open(mode)
    sentinel(self)
    expect(1, mode, "string")

    return fs.open(tostring(self), mode)
  end

  --- Delete the file or directory.
  function file:delete()
    sentinel(self)

    fs.delete(tostring(self))
  end

  --- Get the size of the file in bytes.
  ---@return integer size The size of the file in bytes.
  function file:size()
    sentinel(self)

    return fs.getSize(tostring(self))
  end

  --- Get the attributes of the file
  ---@return ccTweaked.fs.fileAttributes attributes The attributes of the file.
  function file:attributes()
    sentinel(self)
    return fs.attributes(tostring(self))
  end

  --- Rename/Move the file to the given path.
  ---@param path FS_FilePath The new path for the file.
  function file:moveTo(path)
    sentinel(self)
    sentinel_other(1, path)

    fs.move(tostring(self), tostring(path))
  end

  --- Copy the file to the given path.
  ---@param path FS_FilePath The path to copy the file to.
  function file:copyTo(path)
    sentinel(self)
    sentinel_other(1, path)

    fs.copy(tostring(self), tostring(path))
  end

  --- Create this file, if it doesn't exist. Does nothing if the file already exists.
  function file:touch()
    sentinel(self)

    if not fs.exists(tostring(self)) then
      local handle, err = fs.open(tostring(self), "w")
      if handle then handle.close() return end
      error(err, 2)
    end
  end

  --- Serialize data into the file.
  ---@param data any The data to serialize.
  ---@param opts table Options for serialization, same as on https://tweaked.cc/module/textutils.html#v:serialize
  function file:serialize(data, opts)
    sentinel(self)

    self:write(textutils.serialize(data, opts))
  end

  --- Unserialize data from the file.
  ---@param default any The default value to return if the file is empty.
  ---@return any data The unserialized data.
  function file:unserialize(default)
    sentinel(self)

    local contents = self:readAll()
    if not contents then
      return default
    end

    return textutils.unserialize(contents)
  end

  --- Empty the file. This does not delete the file, but rather overwrites it with
  --- an empty string. Creates the file if it doesn't exist.
  function file:nullify()
    sentinel(self)

    local handle, err = fs.open(tostring(self), "w")
    if handle then handle.close() return end
    error(err, 2)
  end

  return file
end

--- Create a directory at the given path within the instance directory.
---@param path FS_FilePath? The path to the directory. If not provided, creates the directory at the instance path.
function filesystem:mkdir(path)
  sentinel(self)
  sentinel_other(1, path)

  if path then
    fs.makeDir(fs.combine(tostring(self), tostring(path)))
  else
    fs.makeDir(tostring(self))
  end
end

--- Remove a file or directory at the given path within the instance directory.
---@param path FS_FilePath? The path to the file or directory. If not provided, removes the instance path.
function filesystem:rm(path)
  sentinel(self)
  sentinel_other(1, path)

  if path then
    fs.delete(fs.combine(tostring(self), tostring(path)))
  else
    fs.delete(tostring(self))
  end
end

--- Check if a file or directory exists at the given path within the instance directory.
---@param path FS_FilePath? The path to the file or directory. If not provided, checks if the instance path exists.
---@return boolean exists Whether the file or directory exists.
function filesystem:exists(path)
  sentinel(self)
  sentinel_other(1, path)

  if not path then
    return fs.exists(tostring(self))
  end
  return fs.exists(fs.combine(tostring(self), tostring(path)))
end

--- Check if the given path is a directory within the instance directory.
---@param path FS_FilePath? The path to the file or directory. If not provided, checks if the instance path is a directory.
---@return boolean is_directory Whether the path is a directory.
function filesystem:isDirectory(path)
  sentinel(self)
  sentinel_other(1, path)

  if not path then
    return fs.isDir(tostring(self))
  end
  return fs.isDir(fs.combine(tostring(self), tostring(path)))
end

--- Check if the given path is a file within the instance directory.
---@param path FS_FilePath? The path to the file or directory. If not provided, checks if the instance path is a file.
---@return boolean is_file Whether the path is a file.
function filesystem:isFile(path)
  sentinel(self)
  sentinel_other(1, path)

  if not path then
    return not fs.isDir(tostring(self))
  end
  return not fs.isDir(fs.combine(tostring(self), tostring(path)))
end

--- List the files and directories in the directory.
---@param path FS_FilePath? The path to the directory. If not provided, lists the instance directory.
---@return FS_File[] files The files and directories in the directory.
function filesystem:list(path)
  sentinel(self)
  sentinel_other(1, path)

  local files
  if path then
    files = fs.list(fs.combine(tostring(self), tostring(path)))
  else
    files = fs.list(tostring(self))
  end
  local result = {}

  for _, file in ipairs(files) do
    table.insert(result, self:file(file))
  end

  return result
end

--- Get the parent directory of the file.
---@return FS_Root parent The parent directory of the file.
function filesystem:parent()
  sentinel(self)

  return new(fs.getDir(tostring(self)))
end

return new()
