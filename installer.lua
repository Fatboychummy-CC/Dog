--- Simple program to be used as an installer script. Copy to repos and insert what is needed.

local to_get = {
  "extern:dog.lua:https://raw.githubusercontent.com/Fatboychummy-CC/Dog/refresh/dog.lua",
  "extern:lib/turtle_aid.lua:https://raw.githubusercontent.com/Fatboychummy-CC/Dog/refresh/lib/turtle_aid.lua",
  "L:lib/file_helper.lua:file_helper.lua",
  "L:lib/logging.lua:logging.lua",
  "L:lib/simple_argparse.lua:simple_argparse.lua",
}
local program_name = "Dog"
local pinestore_id = 200 -- Set this to the ID of the pinestore project if you wish to note to pinestore that a download has occurred.


-- #################
-- Advanced settings
-- #################

-- Set this to true if you wish to use the diffs to determine which files to
-- download. Otherwise, it will download all files in `to_get`.
-- Explanation of diffs is below.
local use_diffs = false

-- The 'diffs' are used to determine which files are needed to download for 
-- whichever version of the program you wish to install.
-- The key is the name of the version you wish to install, and the table it
-- resolves to should be filled with strings containing either the name of
-- another diff, a + followed by the index in `to_get` of the file you wish to
-- download, or a - followed by the index in `to_get` of the file you wish to
-- not download (if including other diffs that have a file you don't want).
-- You can also use "all" to include all files.
-- # Note: Diffs are resolved breadth-first.
-- # You can use ranges to include multiple files (i.e: '+1-3' to include 1 to 3).
local diffs = {
  lib_only = {
    "+1-2",
  },
  tests = {
    "lib_only",
    "+3"
  },
  all = {
    "all"
  },
  all_but_one = {
    "all",
    "-1"
  }
}
--[[
  What version do you wish to install?
  - lib_only
  - tests
  - all
  - all_but_one
  > 
]]

-- #########################################

local RAW_URL_LIBRARIES = "https://raw.githubusercontent.com/Fatboychummy-CC/Libraries/main/"
local RAW_URL_PROGRAMS = "https://raw.githubusercontent.com/Fatboychummy-CC/etc-programs/main/"
local PASTE_URL = "https://pastebin.com/raw/"
local PINESTORE_ROOT = "https://pinestore.cc/"
local PINESTORE_PROJECT_ENDPOINT = PINESTORE_ROOT .. "api/project/"
local PINESTORE_DOWNLOAD_ENDPOINT = PINESTORE_ROOT .. "api/log/download"
local p_dir
local dir_argument = ...
if dir_argument then
  p_dir = shell.resolve(dir_argument)
else
  p_dir = shell.dir()
end

local completion_choice = require "cc.completion".choice

local function print_warning(...)
  term.setTextColor(colors.orange)
  print(...)
  term.setTextColor(colors.white)
end

local function parse_pinestore_response(data)
  local success, response = pcall(textutils.unserializeJSON, data)
  if not success or not response then
    print_warning("Failed to parse response from pinestore.")
    return false
  end

  if response and not response.success then
    print_warning("Failed to get information from pinestore.")
    print_warning(response.error)
    return false
  end

  return response
end

local function download_file(url, filename)
  print("Downloading", filename)
  local h_handle, err = http.get(url) --[[@as Response]]
  if h_handle then
    local data = h_handle.readAll()
    h_handle.close()

    local f_handle, err2 = fs.open(fs.combine(p_dir, filename), 'w') --[[@as WriteHandle]]
    if f_handle then
      f_handle.write(data)
      f_handle.close()
      print("Done.")
      return
    end
    printError(url)
    error(("Failed to write file: %s"):format(err2), 0)
  end
  printError(url)
  error(("Failed to connect: %s"):format(err), 0)
end

local function get_version_to_download()
  if use_diffs then
    print("What version do you wish to install?")
    local versions = {}
    for k in pairs(diffs) do
      print("-", k)
      table.insert(versions, k)
    end
    write("> ")
    local version = read(nil, nil, function(partial)
      return completion_choice(partial, versions) --[[@as string[] ]]
    end)
    if diffs[version] then
      return version
    else
      printError("Invalid version.")
      return get_version_to_download()
    end
  else
    return "all"
  end
end

--- Calculate what files are needed to download.
local function calculate_diffs(version)
  local files = {}

  if not version or not diffs[version] then
    error("Invalid version.", 0)
  end


  local seen_diffs = {}
  local to_resolve = {}

  --- Resolve a single diff.
  ---@param diff table<string> The diff to resolve.
  local function resolve_diff(diff)
    if seen_diffs[diff] then
      print_warning(("Multiple references to diff '%s'. This is probably fine, but if this warning is being spammed you have a loop."):format(diff))
    end
    seen_diffs[diff] = true

    for i, v in ipairs(diff) do
      if v == "all" then
        for j = 1, #to_get do
          files[j] = true
        end
      elseif v:match("^%+") then
        local index = tonumber(v:sub(2))
        if index then
          files[index] = true
        else
          local i1, i2 = v:match("^%+(%d+)%-(%d+)$")
          i1 = tonumber(i1)
          i2 = tonumber(i2)

          if i1 and i2 then
            for j = i1, i2 do
              files[j] = true
            end
          else
            error(("Invalid index in diff: %s, position %d"):format(v, i), 0)
          end
        end
      elseif v:match("^-") then
        local index = tonumber(v:sub(2))
        if index then
          files[index] = false
        else
          local i1, i2 = v:match("^%-(%d+)%-(%d+)$")
          i1 = tonumber(i1)
          i2 = tonumber(i2)

          if i1 and i2 then
            for j = i1, i2 do
              files[j] = false
            end
          else
            error(("Invalid index in diff: %s, position %d"):format(v, i), 0)
          end
        end
      elseif diffs[v] then
        -- We will fully resolve this diff before moving on to any "child" diffs.
        table.insert(to_resolve, v)
      else
        error(("Invalid diff: %s"):format(v), 0)
      end
    end
  end

  to_resolve[1] = version
  while #to_resolve > 0 do
    local diff = table.remove(to_resolve, 1)
    resolve_diff(diffs[diff])
  end

  -- Convert files to a list
  local to_return = {}

  for i = 1, #to_get do
    if files[i] then
      table.insert(to_return, to_get[i])
    end
  end

  return to_return
end

local function get(...)
  local remotes = table.pack(...)

  for i = 1, remotes.n do
    local remote = remotes[i]

    local extern_file, extern_url = remote:match("^extern:(.-):(.+)$")
    local paste_file, paste = remote:match("^paste:(.-):(.+)$")
    local local_file, remote_file = remote:match("^L:(.-):(.+)$")
    local use_libraries = true

    if not local_file then
      local_file, remote_file = remote:match("^E:(.-):(.+)$")
      use_libraries = false
    end

    if extern_file then
      -- downlaod from external location
      download_file(extern_url, extern_file)
    elseif paste_file then
      -- download from pastebin
      local cb = ("%x"):format(math.random(0, 1000000))
      download_file(PASTE_URL .. textutils.urlEncode(paste) .. "?cb=" .. cb, paste_file)
    elseif local_file then
      -- download from main repository.
      if use_libraries then
        download_file(RAW_URL_LIBRARIES .. remote_file, local_file)
      else
        download_file(RAW_URL_PROGRAMS .. remote_file, local_file)
      end
    else
      error(("Could not determine information for '%s'"):format(remote), 0)
    end
  end
end

-- Installation is from the installer's directory.
if p_dir:match("^rom") then
  error("Attempting to install to the ROM. Please rerun but add arguments for install location (or run the installer script in the folder you wish to install to).", 0)
end

print(("You are about to install %s."):format(program_name))

-- Get the short description of the project from pinestore (if it exists).
if pinestore_id then
  local handle = http.get(PINESTORE_PROJECT_ENDPOINT .. tostring(pinestore_id))
  if handle then
    local data = parse_pinestore_response(handle.readAll())
    handle.close()

    if data then
      if type(data) == "table" and data.project and data.project.description_short then
        term.setTextColor(colors.white)
        write("Description from ")
        term.setTextColor(colors.green)
        write("PineStore")
        term.setTextColor(colors.white)
        print(":")
        print(data.project.description_short .. '\n')
      end
    end
  else
    print_warning("Failed to connect to PineStore. Installation will continue, but no description can be provided.")
  end
end

write(("Going to install to:\n  /%s\n\nIs this where you want it to be installed? (y/n): "):format(fs.combine(p_dir, "/*")))

local key
repeat
  local _, _key = os.pullEvent("key")
  key = _key
until key == keys.y or key == keys.n

if key == keys.y then
  print("y")
  sleep()

  local version = get_version_to_download()
  local actual_to_get = calculate_diffs(version)

  print(("Installing %s."):format(program_name))
  get(table.unpack(actual_to_get))

  if type(pinestore_id) == "number" then
    local handle, err, err_handle = http.post(
      PINESTORE_DOWNLOAD_ENDPOINT,
        textutils.serializeJSON({
          projectId = pinestore_id,
        }),
        {["Content-Type"] = "application/json"}
    )
    if not handle then
      if err_handle and err_handle.getResponseCode() == 429 then
        -- Too many requests, something else logged a download already.
        -- We don't need to do anything here, but we'll leave this blank if
        -- statement here for clarity.
      else
        print_warning("Failed to connect to PineStore:", err)
      end
    end
  end
else
  print("n")
  sleep()
  error("Installation cancelled.", 0)
end
