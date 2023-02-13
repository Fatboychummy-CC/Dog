--- Dog - An ore-scanning turtle program that charges straight to ores, ignoring everything else.

---@type fun(index:integer, value:any, ...:string)
local expect = require "cc.expect".expect

package.path = package.path .. ";lib/fatboychummy/?.lua;lib/fatboychummy/?/init.lua"
local QIT = require "QIT"
local turtle_aid = require "turtle_aid"
local file_helper = require "file_helper"

---@generic T
---@class array<T> : {[integer]:T}

---@generic T
---@class three_dimensional_array<T> : {[integer]:{[integer]:{[integer]:T}}}

---@alias state_info {state:miner_state, data:{next:state_info?}}

---@class action : function

---@alias miner_state
---| "start" # Drop anything extra in inventory, etc.
---| "scan" # Scan for ores and do whatever with em.
---| "go_to" # Go to a specific coordinate.
---| "dig_ore" # Dig an ore at a specific position.
---| "mine" # Dig down one block.
---| "return_done" # Return home (finished)
---| "return_fuel" # Return home (low fuel)
---| "return_inv" # Return home (inventory full)
---| "done" # Finished mining, stop.

local ORE_DICT = {
    ["minecraft:iron_ore"] = true,
    ["minecraft:deepslate_iron_ore"] = true,
    ["minecraft:gold_ore"] = true,
    ["minecraft:deepslate_gold_ore"] = true,
    ["minecraft:diamond_ore"] = true,
    ["minecraft:deepslate_diamond_ore"] = true,
    ["minecraft:coal_ore"] = true,
    ["minecraft:deepslate_coal_ore"] = true,
    ["minecraft:lapis_ore"] = true,
    ["minecraft:deepslate_lapis_ore"] = true,
    ["minecraft:emerald_ore"] = true,
    ["minecraft:deepslate_emerald_ore"] = true,
    ["minecraft:quartz_ore"] = true,
    ["minecraft:redstone_ore"] = true,
    ["minecraft:deepslate_redstone_ore"] = true,
    ["minecraft:nether_gold_ore"] = true,
    ["minecraft:ancient_debris"] = true,
}

local PROG = shell.getRunningProgram()
local DIR = fs.getDir(PROG)
local ORE_CACHE_NAME = fs.combine(DIR, "ores.dat")
local DEPTH_NAME = fs.combine(DIR, "depth.dat")
local STATE_NAME = fs.combine(DIR, "state.dat")
local GENERATED_LINE_1 = "--########## DOG_BOOT ##########"
-- I should hope nobody has this at the beginning of their startup file...

---@type QIT<vector>
local ore_cache = QIT()

---@type integer
local last_depth = 0

---@type state_info
local state = { state = "start", data = {} }

---@type string
local arg1 = ...

--- Add an ore to the ore cache, tests if the ore is in the cache already before doing so to prevent duplicates.
---@param block block_info
local function add_to_ore_cache(block)
  local found = false
  local block_pos = vector.new(block.x, block.y, block.z) + turtle_aid.position

  for i = 1, ore_cache.n do
    local test = ore_cache[i]

    if test.x == block_pos.x and test.y == block_pos.y and test.z == block_pos.z then
      found = true
      break
    end
  end

  if not found then
    ore_cache:Insert(block_pos)
  end
end

--- Remove an ore from the cache.
---@param block block_info
local function remove_from_ore_cache(block)
  local block_pos = vector.new(block.x, block.y, block.z) + turtle_aid.position

  for i = 1, ore_cache.n do
    local test = ore_cache[i]

    if test.x == block_pos.x and test.y == block_pos.y and test.z == block_pos.z then
      ore_cache:Take(i)
      break
    end
  end
end

local function sort_ore_cache()
  local pos = turtle_aid.position

  -- this sort method may be a bit slow since the length is computed for every comparison.
  ---@TODO fix this.
  table.sort(ore_cache, function(a, b)
    return (pos - a):length() < (pos - b):length()
  end)
end

--- Check that a file is a dog-generated file or not.
---@param filename string The file to test.
---@return boolean
local function check_file_for_dog(filename)
  local h = io.open(filename, 'r')

  if not h then
    return false
  end

  local line = h:read("*l")
  h:close()

  return line == GENERATED_LINE_1
end

--- Create a startup file to recover after a chunk unload.
--- Will move any other startups that exist temporarily.
local function build_startup()
  if fs.exists("startup") and not check_file_for_dog("startup") then
    fs.move("startup", "dog_old_startup")
  end
  if fs.exists("startup.lua") and not check_file_for_dog("startup.lua") then
    fs.move("startup.lua", "dog_old_startup.lua")
  end

  local h, err = io.open("startup.lua", 'w')
  if h then
    h:write(("%s\nshell.run(\"%s reload\")"):format(GENERATED_LINE_1, PROG))
    h:close()
  else
    error(("Cannot write startup file: %s"):format(err), 0)
  end
end

--- Delete the temporary startup file and restore the old startup files.
local function remove_startup()
  if fs.exists("startup") and check_file_for_dog("startup") then
    fs.delete("startup")
    if fs.exists("dog_old_startup") then
      fs.move("dog_old_startup", "startup")
    end
  end
  if fs.exists("startup.lua") and check_file_for_dog("startup.lua") then
    fs.delete("startup.lua")
    if fs.exists("dog_old_startup.lua") then
      fs.move("dog_old_startup.lua", "startup")
    end
  end
end

--- Get the closest position of the "side" of the given ore block.
---@param x integer Position of the ore to test.
---@param y integer Position of the ore to test.
---@param z integer Position of the ore to test.
---@return {pos:vector, prev:vector}
local function get_side_of_ore(x, y, z)
  expect(1, x, "number")
  expect(2, y, "number")
  expect(3, z, "number")

  ---@class ore_test_info : {pos:vector, prev:vector}

  ---@type QIT<ore_test_info>
  local blocks_testing = QIT()
  blocks_testing:Insert({pos = vector.new(x, y, z), prev = vector.new(x, y, z)})

  local function is_ore_block(_x, _y, _z)
    for i = 1, ore_cache.n do
      local pos = ore_cache[i]
      if pos.x == _x and pos.y == _y and pos.z == _z then
        return true
      end
    end
    return false
  end

  while #blocks_testing > 0 do
    ---@type ore_test_info
    local info = blocks_testing:Drop()

    -- Check if this is a side of the ore
    if not is_ore_block(info.pos.x, info.pos.y, info.pos.z) then
      return info
    end

    -- Add the surrounding blocks to be tested
    -- I know there's an easier way but I am lazy
    table.insert(blocks_testing, {pos = vector.new(info.pos.x + 1, info.pos.y, info.pos.z), prev = info.pos})
    table.insert(blocks_testing, {pos = vector.new(info.pos.x - 1, info.pos.y, info.pos.z), prev = info.pos})
    table.insert(blocks_testing, {pos = vector.new(info.pos.x, info.pos.y, info.pos.z + 1), prev = info.pos})
    table.insert(blocks_testing, {pos = vector.new(info.pos.x, info.pos.y, info.pos.z - 1), prev = info.pos})
  end

  error("This code should not be reached.", 0)
end


--- Scan for ores, adds ores to a memory list, and returns the scan data.
---@return array<block_info> scan_data The scan data.
local function scan()
  local ok, side = turtle_aid.quick_equip("scanner")
  if not ok then
    error(side, 0)
  end

  ---@type array<block_info>
  local scan_data = peripheral.call(side, "scan")

  for i = 1, #scan_data do
    local block = scan_data[i]

    if ORE_DICT[block.name] then
      add_to_ore_cache(block)
    end
  end

  return scan_data
end

--- Dig to a specified position.
---@param x integer The X position.
---@param y integer The Y position.
---@param z integer The Z position.
---@return action action
local function dig_to(x, y, z)
  -- Align X axis
  if turtle_aid.position.x > x then
    -- X > wanted, face -X
    return function()
      turtle_aid.face(3)
      turtle_aid.gravel_protected_dig()
      turtle_aid.go_forward()
    end
  elseif turtle_aid.position.x < x then
    -- face +X
    return function()
      turtle_aid.face(1)
      turtle_aid.gravel_protected_dig()
      turtle_aid.go_forward()
    end
  end

  -- Align Z axis
  if turtle_aid.position.z > z then
    -- Z > wanted, face -Z
    return function()
      turtle_aid.face(0)
      turtle_aid.gravel_protected_dig()
      turtle_aid.go_forward()
    end
  elseif turtle_aid.position.z < z then
    -- face +Z
    return function()
      turtle_aid.face(2)
      turtle_aid.gravel_protected_dig()
      turtle_aid.go_forward()
    end
  end

  -- Align Y axis
  if turtle_aid.position.y > y then
    return function()
      turtle.digDown()
      turtle_aid.go_down()
    end
  elseif turtle_aid.position.y < y then
    return function()
      turtle_aid.go_up()
      turtle_aid.gravel_protected_dig_up()
    end
  end

  --- This should never happen, but this means we're at the desired position.
  return function()
    ---@diagnostic disable-next-line go_to state requires next state.
    state.state = state.data.next
  end
end

--- Mine to the edge of an ore given the specified position.
---@param x integer The X position of the ore.
---@param y integer The Y position of the ore.
---@param z integer The Z position of the ore.
local function mine_to_ore(x, y, z)
  local info = get_side_of_ore(x, y, z)
  dig_to(info.pos.x, info.pos.y, info.pos.z)
end

--- Return to the turtle's home location (0,0,0)
---@return action
local function return_home()
  return dig_to(0, 0, 0)
end

local function mine_tick()

end

---@type action
local function at_home()
  if state.state == "start" then
    turtle_aid.dump_inventory(turtle_aid.base_excluded_items())
    state.state = "scan"
  end
end

---@type action
local function mine_action()
  turtle.digDown()
  turtle_aid.go_down()
end

--- Get the next action to run.
---@return action? action The action to run, no action if the program is complete.
local function get_next_action()
  if state.state == "start" then
    return at_home
  elseif state.state == "mine" then
    return mine_action
  elseif state.state == "go_to" then
    return dig_to(state.data.x, state.data.y, state.data.z)
  elseif state.state == "scan" then
    return function()
      scan()

      if ore_cache.n > 0 then
        sort_ore_cache()
        state.state = "go_to"
        state.data = { get_side_of_ore(ore_cache[1].x, ore_cache[1].y, ore_cache[1].z) }
        state.data.next = { state = "dig_ore" }
      end
    end
  end
end



--- Main action loop:
---
--- 1. Dig down a block.
--- 2. Scan, add any ores found to the list.
--- 3. If ores in list, continue, else return to #1.
--- 4. Dig towards the ore, mine the ore (scanning along the way).
--- 5. When no more ores remain in the ore cache, return to the last position we were digging down from.
--- 6. Go to #1
local function action_loop()
  while true do
    local action = get_next_action()

    if action then
      action()
    else
      return
    end
  end
end

--- Main program body.
local function main()
  build_startup()

  if arg1 == "reload" then
    turtle_aid.load()
    ore_cache = file_helper.unserialize(ORE_CACHE_NAME)
    last_depth = file_helper.unserialize(DEPTH_NAME)
    state = file_helper.unserialize(STATE_NAME)
  end

  if turtle_aid.is_at(0, 0, 0) then
    at_home()
  end

  if state.state ~= "return_done" and state.state ~= "done" then
    action_loop()
  end

  if state.state ~= "done" then
    state.state = "return_done"
    state.data = {}
    return_home()
    state.state = "done"
    state.data = {}
  end

  at_home()
  remove_startup()
end

local ok, err = pcall(main)

-- for now, just basic error handling.
if not ok then
  printError(err)
end
