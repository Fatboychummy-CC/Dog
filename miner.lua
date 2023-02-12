--- Dog - An ore-scanning turtle program that charges straight to ores, ignoring everything else.

---@type fun(index:integer, value:any, ...:string)
local expect = require "cc.expect".expect

package.path = package.path .. ";lib/fatboychummy/?.lua;lib/fatboychummy/?/init.lua"
local QIT = require "QIT"
local turtle_aid = require "turtle_aid"

---@generic T
---@class array<T> : {[integer]:T}

---@generic T
---@class three_dimensional_array<T> : {[integer]:{[integer]:{[integer]:T}}}

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
local ORE_CACHE = fs.combine(DIR, "ores.dat")
local GENERATED_LINE_1 = "--########## DOG_BOOT ##########"
-- I should hope nobody has this at the beginning of their startup file...

---@type QIT<vector>
local ore_cache = QIT()

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

--- Get the closest position of the "side" of the given ore block.
---@param x integer Position of the ore to test.
---@param y integer Position of the ore to test.
---@param z integer Position of the ore to test.
---@return integer x Position of the side of the ore.
---@return integer y Position of the side of the ore.
---@return integer z Position of the side of the ore.
local function get_side_of_ore(x, y, z)
  expect(1, x, "number")
  expect(2, y, "number")
  expect(3, z, "number")

  local SIDES = {
      { -1, 0, 0 },
      { 1,  0, 0 },
      { 0,  0, 1 },
      { 0,  0, -1 }
  }
  local MAX_ITERATIONS = 100

  local blocks_testing = { { x, y, z } }

  local checked = {}
  checked[x .. y .. z] = true

  --- Add the side value to the inputted position.
  ---@param i integer Side index.
  ---@param _x integer
  ---@param _y integer
  ---@param _z integer
  ---@return integer x
  ---@return integer y
  ---@return integer z
  ---@return integer distance
  local function add(i, _x, _y, _z)
    return _x + SIDES[i][1], _y + SIDES[i][2], _z + SIDES[i][3],
        (_x + SIDES[i][1] + _y + SIDES[i][2] + _z + SIDES[i][3])
  end

  --- Get the block info for the given position.
  ---@return vector position The position of the edge.
  local function get_block()
    table.sort(blocks_testing, function(a, b)
      return a[4] < b[4] -- sort by closest distance.
    end)
    local _x, _y, _z = table.unpack(blocks_testing[1], 1, 3)

    for i = 1, #ore_cache do
      local block_data = ore_cache[i]
      if block_data.x == _x and block_data.y == _y and block_data.z == _z then
        return block_data
      end
    end

    return { name = "unknown", x = _x, y = _y, z = _z, state = {} }
  end

  -- Loop:
  --   1. Insert locations around currently tested position
  --   2. Check if current position is not an ore (or if we've been looping too long)
  --   3. Remove the first location in the tested positions list.
  -- Ensure we aren't re-checking things we've already checked as well.
  local iterations = 0
  repeat
    local block = get_block()
    table.remove(blocks_testing, 1)

    for i = 1, 4 do
      local px, py, pz, distance = add(i, block.x, block.y, block.z)
      if not checked[px .. py .. pz] then
        table.insert(blocks_testing, { px, py, pz, distance })
        checked[px .. py .. pz] = true
      end
    end

    iterations = iterations + 1
  until not ORE_DICT[block.name] or iterations > MAX_ITERATIONS

  -- if, for some reason, ores span out nearly infinitely in every direction, just dig down into it.
  if iterations > MAX_ITERATIONS then
    return x, y, z
  end

  return blocks_testing[1].x, blocks_testing[1].y, blocks_testing[1].z
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
local function dig_to(x, y, z)
  -- Align X axis
  while turtle_aid.position.x ~= x do
    if turtle_aid.position.x > x then
      -- X > wanted, face -X
      turtle_aid.face(3)
      turtle_aid.gravel_protected_dig()
      turtle_aid.go_forward()
    else
      -- face +X
      turtle_aid.face(1)
      turtle_aid.gravel_protected_dig()
      turtle_aid.go_forward()
    end
  end

  -- Align Z axis
  while turtle_aid.position.z ~= z do
    if turtle_aid.position.z > z then
      -- Z > wanted, face -Z
      turtle_aid.face(0)
      turtle_aid.gravel_protected_dig()
      turtle_aid.go_forward()
    else
      -- face +Z
      turtle_aid.face(2)
      turtle_aid.gravel_protected_dig()
      turtle_aid.go_forward()
    end
  end

  -- Align Y axis
  while turtle_aid.position.y ~= y do
    if turtle_aid.position.y > y then
      turtle.digDown()
      turtle_aid.go_down()
    else
      turtle_aid.go_up()
      turtle_aid.gravel_protected_dig_up()
    end
  end
end

--- Mine to the edge of an ore given the specified position.
---@param x integer The X position of the ore.
---@param y integer The Y position of the ore.
---@param z integer The Z position of the ore.
local function mine_to_ore(x, y, z)
  dig_to(get_side_of_ore(x, y, z))
end

--- Return to the turtle's home location (0,0,0)
local function return_home()
  dig_to(0, 0, 0)
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
