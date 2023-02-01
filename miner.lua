--- Dog - An ore-scanning turtle program that charges straight to ores, ignoring everything else.

---@type fun(index:integer, value:any, ...:string)
local expect = require "cc.expect".expect

---@alias side
---| "left"
---| "right"

---@alias turtle_module
---| "scanner" # Block Scanner
---| "kinetic" # Kinetic Augment
---| "pickaxe" # Pickaxe (diamond or netherite)
---| "empty"   # Nothing
---| "unknown" # Module could not be determined. This cannot be passed to methods expecting a turtle_module, but it may be returned.

---@generic T
---@class array<T> : {[integer]:T}

---@generic T
---@class three_dimensional_array<T> : {[integer]:{[integer]:{[integer]:T}}}

---@class block_info
---@field name string The name of the block scanned.
---@field state table Some state information about the block.
---@field x integer The x position relative to the turtle.
---@field y integer The y position relative to the turtle.
---@field z integer The z position relative to the turtle.

local MODULE_LOOKUP = {
  ["minecraft:diamond_pickaxe"] = "pickaxe",
  ["minecraft:netherite_pickaxe"] = "pickaxe",
  ["plethora:module_scanner"] = "scanner",
  ["plethora:module_kinetic"] = "kinetic"
}
local MODULE_I_LOOKUP = {
  ["scanner"] = "plethora:module_scanner",
  ["kinetic"] = "plethora:module_kinetic"
}

local PICKAXES = {
  "minecraft:diamond_pickaxe",
  "minecraft:netherite_pickaxe"
}

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

---@type {left:turtle_module?, right:turtle_module?}
local currently_equipped = {}

---@type three_dimensional_array<string>
local ore_cache = {}

--- Shorthand to turtle.select(1)
local function sel1()
  turtle.select(1)
end

--- Select an item in the turtle's inventory.
---@param name string? The item to select, or nil to select the first available empty slot.
---@return boolean selected If the turtle succeeded in finding the item to select.
local function select_item(name)
  expect(1, name, "string", "nil")

  for i = 1, 16 do
    local item_data = turtle.getItemDetail(i)

    if not name then
      if not item_data then
        turtle.select(i)
        return true
      end
    elseif item_data and item_data.name == name then
      turtle.select(i)
      return true
    end
  end

  return false
end

--- Attempt to select a pickaxe.
---@return boolean success If the turtle found a pickaxe to select.
local function select_pickaxe()
  local success = false

  for i = 1, #PICKAXES do
    success = select_item(PICKAXES[i])
    if success then break end
  end

  return success
end

--- Swap a module to a specific side.
---@param module turtle_module The name of the module to swap to.
---@param side side The side to swap modules.
---@return boolean success If the turtle could swap the module.
---@return string? reason If the turtle failed to swap the module, the reason will be stored here.
local function swap_module(module, side)
  expect(1, module, "string")
  expect(2, side, "string")

  if currently_equipped.left == module then
    return false, "Module already equipped on left side."
  end
  if currently_equipped.right == module then
    return false, "Module already equipped on right side."
  end

  ---@type fun()
  local equip = side == "left" and turtle.equipLeft or turtle.equipRight

  if module == "empty" then
    local success_1 = select_item("empty")

    if not success_1 then
      return false, "No empty slots to unequip current module into."
    end
  else
    if module == "pickaxe" then
      local success_1 = select_pickaxe()

      if not success_1 then
        return false, "Could not find module of type 'pickaxe'"
      end
    else
      local success_1 = select_item(MODULE_I_LOOKUP[module])
      if not success_1 then
        return false, ("Could not find module of type '%s'"):format(module)
      end
    end

  end

  equip() -- equip the newly selected module.
  currently_equipped[side] = module
  return true
end

--- Get information about what module is on a specific side of the turtle.
---@param side side The side to test.
---@return string module_name
local function get_module_info(side)
  expect(1, side, "string")

  swap_module("empty", side)

  local info = turtle.getItemDetail()

  if info then
    local module = MODULE_LOOKUP[info.name] or "unknown"
    -- re-equip the item.
    if side == "left" then
      turtle.equipLeft()
    else
      turtle.equipRight()
    end

    currently_equipped[side] = module
    return module
  end

  currently_equipped[side] = "empty"
  return "empty"
end

--- Dig forward, optionally using the internal pickaxe if desired. This requires a kinetic augment and pickaxe.
---@param use_internal_pick boolean? Use the internal pickaxe (with kinetic augment).
local function dig_forward(use_internal_pick)
  -- we want to ensure we don't accidentally have two pickaxes in our inventory for this.
  ---@type side
  local swapped_side = currently_equipped.left == "pickaxe" and "right" or "left"

  if use_internal_pick then
    local ok, err = swap_module("kinetic", swapped_side)
    ok = select_pickaxe()

    -- Kinetic augment digging may require multiple swings.
    -- This will immediately fail on bedrock.
    repeat
      local digging = peripheral.call("right", "swing")
    until not digging
  else
    turtle.dig()
  end
end

--- Get the closest position of the "side" of the given ore block.
---@param scan_data array<block_info>
---@param x integer Position of the ore to test.
---@param y integer Position of the ore to test.
---@param z integer Position of the ore to test.
---@return integer x Position of the side of the ore.
---@return integer y Position of the side of the ore.
---@return integer z Position of the side of the ore.
local function get_side_of_ore(scan_data, x, y, z)
  expect(1, scan_data, "table")
  expect(2, x, "number")
  expect(3, y, "number")
  expect(4, z, "number")

  local SIDES = {
    { -1, 0, 0 },
    { 1, 0, 0 },
    { 0, 0, 1 },
    { 0, 0, -1 }
  }
  local MAX_ITERATIONS = 10

  local blocks_testing = { { x, y, z } }

  local checked = {}
  checked[x .. y .. z] = true

  --- Add the side value to the inputted position.
  ---@param i integer Side index.
  ---@param _x integer
  ---@param _y integer
  ---@param _z integer
  ---@return integer
  ---@return integer
  ---@return integer
  local function add(i, _x, _y, _z)
    return _x + SIDES[i][1], _y + SIDES[i][2], _z + SIDES[i][3]
  end

  --- Get the block info for the given position.
  ---@return block_info
  local function get_block()
    local _x, _y, _z = table.unpack(blocks_testing[1], 1, 3)

    for i = 1, #scan_data do
      local block_data = scan_data[i]
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
      local px, py, pz = add(i, block.x, block.y, block.z)
      if not checked[px .. py .. pz] then
        table.insert(blocks_testing, {})
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
