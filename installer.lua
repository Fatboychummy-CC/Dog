--- Simple program to be used as an installer script. Copy to repos and insert what is needed.

local to_get = {
  "extern:dog.lua:https://raw.githubusercontent.com/Fatboychummy-CC/Dog/refresh/dog.lua",
  "extern:lib/turtle_aid.lua:https://raw.githubusercontent.com/Fatboychummy-CC/Dog/refresh/lib/turtle_aid.lua",
  "lib/file_helper.lua:file_helper.lua",
  "lib/logging.lua:logging.lua",
  "lib/simple_argparse.lua:simple_argparse.lua",
}
local program_name = "Dog"

-- #########################################

local RAW_URL = "https://raw.githubusercontent.com/Fatboychummy-CC/Libraries/main/"
local PASTE_URL = "https://pastebin.com/raw/"
local p_dir = ... or shell.dir()

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

local function get(...)
  local remotes = table.pack(...)

  for i = 1, remotes.n do
    local remote = remotes[i]

    local extern_file, extern_url = remote:match("^extern:(.-):(.+)$")
    local paste_file, paste = remote:match("^paste:(.-):(.+)$")
    local local_file, remote_file = remote:match("^(.-):(.+)$")

    if extern_file then
      -- downlaod from external location
      download_file(extern_url, extern_file)
    elseif paste_file then
      -- download from pastebin
      local cb = ("%x"):format(math.random(0, 1000000))
      download_file(PASTE_URL .. textutils.urlEncode(paste) .. "?cb=" .. cb, paste_file)
    elseif local_file then
      -- download from main repository.
      download_file(RAW_URL .. remote_file, local_file)
    else
      error(("Could not determine information for '%s'"):format(remote), 0)
    end
  end
end

-- Installation is from the installer's directory.
if p_dir:match("^rom") then
  error("Attempting to install to the ROM. Please rerun but add arguments for install location (or run the installer script in the folder you wish to install to).", 0)
end

write(("Going to install to:\n  /%s\n\nIs this where you want it to be installed? (y/n): "):format(fs.combine(p_dir, "*")))

local key
repeat
  local _, _key = os.pullEvent("key")
  key = _key
until key == keys.y or key == keys.n

if key == keys.y then
  print("y")
  sleep()
  print(("Installing %s."):format(program_name))
  get(table.unpack(to_get))
else
  print("n")
  sleep()
  error("Installation cancelled.", 0)
end