-- build 1

local expect = require "cc.expect".expect
local file_helper = require "file_helper"
local QIT = require "QIT"

---@alias turtle_facing
---| `0` # North (negative Z direction)
---| `1` # East (positive X direction)
---| `2` # South (positive Z direction)
---| `3` # West (negative X direction)

---@alias movement
---| "forward"
---| "back"
---| "left"
---| "right"
---| "up"
---| "down"
---| "done"

---@class vector : {x:integer, y:integer, z:integer}
---@operator add(vector):vector
---@operator sub(vector):vector
---@operator mul(number):vector
---@operator div(number):vector
---@operator unm:vector
---@field dot fun(self:vector, o:vector):vector
---@field cross fun(self:vector, o:vector):vector
---@field length fun(self:vector):number
---@field normalize fun(self:vector):vector
---@field round fun(self:vector):vector
---@field new fun(x:number, y:number, z:number):vector

---@alias side
---| "left"
---| "right"

---@alias cardinal_direction
---| "north"
---| "east"
---| "south"
---| "west"

---@alias turtle_module
---| "scanner" # Block Scanner
---| "kinetic" # Kinetic Augment
---| "pickaxe" # Pickaxe (diamond or netherite)
---| "empty"   # Nothing
---| "unknown" # Module could not be determined. This cannot be passed to methods expecting a turtle_module, but it may be returned.

---@class block_info
---@field name string The name of the block scanned.
---@field state table Some state information about the block.
---@field x integer The x position relative to the turtle.
---@field y integer The y position relative to the turtle.
---@field z integer The z position relative to the turtle.

local DIR = fs.getDir(shell.getRunningProgram())
local POSITION_CACHE = fs.combine(DIR, "position.dat")

local EQUIPABLE_MODULE_LOOKUP = {
    ["minecraft:diamond_pickaxe"] = "pickaxe",
    ["minecraft:netherite_pickaxe"] = "pickaxe",
    ["plethora:module_scanner"] = "scanner",
    ["plethora:module_kinetic"] = "kinetic"
}
local EQUIPABLE_MODULE_I_LOOKUP = {
    ["scanner"] = "plethora:module_scanner",
    ["kinetic"] = "plethora:module_kinetic"
}

local EQUIPABLE_PICKAXES = {
    "minecraft:diamond_pickaxe",
    "minecraft:netherite_pickaxe"
}

local PICKAXES = {
    "minecraft:diamond_pickaxe",
    "minecraft:netherite_pickaxe",
    "minecraft:golden_pickaxe",
    "minecraft:iron_pickaxe",
    "minecraft:stone_pickaxe",
    "minecraft:wooden_pickaxe"
}

---@type {[turtle_facing]:vector}
local facings = {
    [0] = vector.new(0, 0, -1), -- negative Z direction, north
    vector.new(1, 0, 0), -- positive X direction, east
    vector.new(0, 0, 1), -- positive Z direction, south
    vector.new( -1, 0, 0) -- negative X direction, west
}

---@class turtle_aid
local aid = {
    ---@type vector
    position = vector.new(),
    ---@type turtle_facing
    facing = 0,
    ---@type integer
    fuel = turtle.getFuelLevel(),
    ---@type {left:turtle_module?, right:turtle_module?}
    currently_equipped = {}
}

--- Write movement information to the position cache file.
---@param movement movement The movement to save.
local function write_movement(movement)
  file_helper.serialize(POSITION_CACHE, { movement, aid.position, aid.facing, aid.fuel }, true)
end

--- Test the last movement that was written to file and check if it went through.
---@param movement movement
local function check_movement(movement)
  if movement == "left" then -- assume turns succeed
    aid.facing = (aid.facing - 1) % 4
  elseif movement == "right" then -- assume turns succeed
    aid.facing = (aid.facing + 1) % 4
  elseif movement ~= "done" then
    local actual_fuel = turtle.getFuelLevel()

    -- If the fuel is lower than we expected it to be, that means we moved!
    if actual_fuel < aid.fuel then
      if movement == "forward" then
        aid.position = aid.position + facings[aid.facing]
      elseif movement == "back" then
        aid.position = aid.position - facings[aid.facing]
      elseif movement == "up" then
        aid.position = aid.position + vector.new(0, 1, 0)
      elseif movement == "down" then
        aid.position = aid.position + vector.new(0, -1, 0)
      end
    end
  end
end

local function get_direction()
  local ok, side = aid.quick_equip("scanner")
  if ok then
    local scan = peripheral.call(side, "scan")

    ---@type cardinal_direction
    local turtle_facing

    for i = 1, #scan do
      local block = scan[i]
      if block.x == 0 and block.y == 0 and block.z == 0 then
        turtle_facing = block.state.facing
        break
      end
    end

    if turtle_facing == "north" then
      aid.facing = 0
    elseif turtle_facing == "east" then
      aid.facing = 1
    elseif turtle_facing == "south" then
      aid.facing = 2
    elseif turtle_facing == "west" then
      aid.facing = 3
    else
      error(("Got unknown direction from scanner: %s"):format(turtle_facing), 0)
    end
  else
    error("Cannot determine direction. Need block scanner.", 0)
  end
end

--- Load information from the position cache.
function aid.load()
  local data = file_helper.unserialize(POSITION_CACHE)

  if data then
    local movement = data[1]
    aid.position = data[2]
    aid.facing = data[3]
    aid.fuel = data[4]

    check_movement(movement)
    write_movement("done")
    return
  end

  get_direction()
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

--- Attempt to select an equipable pickaxe.
---@return boolean success If the turtle found a suitable pickaxe to select.
local function select_equipable_pickaxe()
  local success = false

  for i = 1, #EQUIPABLE_PICKAXES do
    success = select_item(EQUIPABLE_PICKAXES[i])
    if success then break end
  end

  return success
end

--- Attempt to select any pickaxe.
---@return boolean success If the turtle found any pickaxe to select.
local function select_any_pickaxe()
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
function aid.swap_module(module, side)
  expect(1, module, "string")
  expect(2, side, "string")

  if aid.currently_equipped.left == module then
    return false, "Module already equipped on left side."
  end
  if aid.currently_equipped.right == module then
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
      local success_1 = select_equipable_pickaxe()

      if not success_1 then
        return false, "Could not find module of type 'pickaxe'"
      end
    else
      local success_1 = select_item(EQUIPABLE_MODULE_I_LOOKUP[module])
      if not success_1 then
        return false, ("Could not find module of type '%s'"):format(module)
      end
    end
  end

  equip() -- equip the newly selected module.
  aid.currently_equipped[side] = module
  return true
end

--- Get information about what module is on a specific side of the turtle.
---@param side side The side to test.
---@return string module_name
function aid.get_module_info(side)
  expect(1, side, "string")

  aid.swap_module("empty", side)

  local info = turtle.getItemDetail()

  if info then
    local module = EQUIPABLE_MODULE_LOOKUP[info.name] or "unknown"
    -- re-equip the item.
    if side == "left" then
      turtle.equipLeft()
    else
      turtle.equipRight()
    end

    aid.currently_equipped[side] = module
    return module
  end

  aid.currently_equipped[side] = "empty"
  return "empty"
end

--- Determine the best attachment for a specified module. Avoids mixing pickaxes into the inventory.
---@param module turtle_module
---@return boolean already_equipped If the module is already equipped.
---@return side side If already equipped, the side it's on, otherwise the best attachment point.
function aid.best_attachment(module)
  if aid.currently_equipped.left == module then
    -- Module is already on left side.
    return true, "left"
  elseif aid.currently_equipped.right == module then
    -- Module is already on the right side.
    return true, "right"
  end

  if aid.currently_equipped.left == "pickaxe" and aid.currently_equipped.right == "pickaxe" then
    error("Why did you equip two pickaxes? I don't know which one to use!", 0)
  end

  -- Pickaxe is equipped on the left side, best attachment is the right side.
  if aid.currently_equipped.left == "pickaxe" then
    return false, "right"
  end

  -- Pickaxe is either equipped on the right side, or nothing is equipped on the left side. Best is left.
  return false, "left"
end

--- Get the best attachment point and equip a module on that attachement point.
---@param module turtle_module The module to equip.
---@return boolean success
---@return string|side error_or_side The reason for failure, or the side the module is equipped on on success.
function aid.quick_equip(module)
  expect(1, module, "string")

  local already_equipped, side = aid.best_attachment(module)
  if not already_equipped then
    local ok, reason = aid.swap_module(module, side)

    ---@diagnostic disable-next-line if not `already_equipped`, side guaranteed exists.
    return ok, ok and side or reason
  end

  return true, side
end

--- Dig forward, using internal pickaxe. This requires a kinetic augment and pickaxe.
function aid.dig_forward()
  -- we want to ensure we don't accidentally have two pickaxes in our inventory for this.
  ---@type side
  local swapped_side = aid.currently_equipped.left == "pickaxe" and "right" or "left"

  local ok, err = aid.swap_module("kinetic", swapped_side)
  ok = select_any_pickaxe()
  ---@TODO error check here

  -- Kinetic augment digging may require multiple swings.
  -- This will immediately fail on bedrock.
  repeat
    local digging = peripheral.call(swapped_side, "swing")
  until not digging
end

--- Move forward, updating the turtle's position information.
---@return boolean success
function aid.go_forward()
  write_movement("forward")
  local success = turtle.forward()

  if success then
    aid.position = aid.position + facings[aid.facing]
    aid.fuel = aid.fuel - 1
  end

  write_movement("done")
  return success
end

--- Move back, updating the turtle's position information.
---@return boolean success
function aid.go_back()
  write_movement("back")
  local success = turtle.back()

  if success then
    aid.position = aid.position - facings[aid.facing]
    aid.fuel = aid.fuel - 1
  end

  write_movement("done")
  return success
end

--- Move up, updating the turtle's position information.
---@return boolean success
function aid.go_up()
  write_movement("up")
  local success = turtle.up()

  if success then
    aid.position = aid.position + vector.new(0, 1, 0)
    aid.fuel = aid.fuel - 1
  end

  write_movement("done")
  return success
end

--- Move down, updating the turtle's position information.
---@return boolean success
function aid.go_down()
  write_movement("down")
  local success = turtle.down()

  if success then
    aid.position = aid.position + vector.new(0, -1, 0)
    aid.fuel = aid.fuel - 1
  end

  write_movement("done")
  return success
end

--- Turn left, updating the turtle's position information.
---@return boolean success
function aid.turn_left()
  write_movement("left") -- turns are to be assumed successful on reboot
  local success = turtle.turnLeft()

  if success then
    aid.facing = (aid.facing - 1) % 4
  end

  write_movement("done")
  return success
end

--- Turn right, updating the turtle's position information.
---@return boolean success
function aid.turn_right()
  write_movement("right") -- turns are to be assumed successful on reboot
  local success = turtle.turnRight()

  if success then
    aid.facing = (aid.facing + 1) % 4
  end

  write_movement("done")
  return success
end

--- Turn to face the specified direction.
---@param new_facing turtle_facing The direction to face.
function aid.face(new_facing)
  expect(1, new_facing, "number")
  if new_facing ~= 1 or new_facing ~= 2 or new_facing ~= 3 or new_facing ~= 0 then
    error(("Bad argument #1: expected integers 0, 1, 2, or 3; got %s."):format(new_facing), 2)
  end

  if aid.facing == new_facing then
    return
  elseif (aid.facing + 1) % 4 == new_facing then
    aid.turn_right()
  else
    repeat
      aid.turn_left()
    until aid.facing == new_facing
  end
end

function aid.gravel_protected_dig()
  repeat
    turtle.dig()
  until not turtle.detect()
end

function aid.gravel_protected_dig_up()
  repeat
    turtle.digUp()
  until not turtle.detectUp()
end

--- Test that we are at a specific position.
---@param x integer The X position.
---@param y integer The Y position.
---@param z integer The Z position.
---@return boolean at_position
function aid.is_at(x, y, z)
  return aid.position.x == x and aid.position.y == y and aid.position.z == z
end

---@generic T
---@parameter t array<T> The array to check.
---@parameter value T The value to test.
---@return boolean is_in
local function is_in(t, value)
  for i = 1, #t do
    if t[i] == value then
      return true
    end
  end

  return false
end


function aid.base_excluded_items()
  ---@type QIT<string>
  local exclude = QIT()

  for module in pairs(EQUIPABLE_MODULE_LOOKUP) do
    if not is_in(exclude, module) then
      exclude:Insert(module)
    end
  end

  for pick in pairs(PICKAXES) do
    if not is_in(exclude, pick) then
      exclude:Insert(pick)
    end
  end

  return exclude:Clean()
end

--- Dump items from the turtle's inventory
---@param exclusion array<integer> The slots to ignore.
function aid.dump_inventory(exclusion)
  for i = 1, 16 do
    local item = turtle.getItemDetail(i)

    if item and is_in(exclusion, item.name) then
      turtle.select(i)
      turtle.refuel() -- nom the fuel
      turtle.drop()
    end
  end
end

return aid
