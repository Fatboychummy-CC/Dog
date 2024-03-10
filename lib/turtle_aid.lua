-- build 1

local expect = require "cc.expect".expect
local file_helper = require "file_helper":instanced("")

---@alias turtle_facing
---| 0 # North (negative Z direction)
---| 1 # East (positive X direction)
---| 2 # South (positive Z direction)
---| 3 # West (negative X direction)

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
---| "scanner" # Block Scanner (Plethora)
---| "geoScanner" # Block Scanner (Advanced Peripherals)
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

local POSITION_CACHE = "position.dat"

local EQUIPABLE_MODULE_LOOKUP = {
    ["minecraft:diamond_pickaxe"] = "pickaxe",
    ["minecraft:netherite_pickaxe"] = "pickaxe",
    ["plethora:module_scanner"] = "scanner",
    ["plethora:module_kinetic"] = "kinetic",
    ["advancedperipherals:geo_scanner"] = "geoScanner"
}
local EQUIPABLE_MODULE_I_LOOKUP = {
    ["scanner"] = "plethora:module_scanner",
    ["kinetic"] = "plethora:module_kinetic",
    ["geoScanner"] = "advancedperipherals:geo_scanner"
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

local aid = {
    ---@type vector
    position = vector.new(0, 0, 0),
    ---@type turtle_facing
    facing = 0,
    ---@type number|"unlimited"
    fuel = turtle.getFuelLevel(),
    ---@type {left:turtle_module?, right:turtle_module?}
    currently_equipped = {}
}

--- Data about recent moves that have been made.
local retracer = {
  max_length = 10, --- The maximum number of movements to store.
  locked = false, --- If true, the retracer will not accept new movements.
  ---@type movement[] EXCEPT "done"
  steps = {},
}

--- Insert a movement into the retracer. This should check if the max length is
--- reached, and remove the oldest movement if it is.
---@param movement movement The movement to insert.
local function insert_movement(movement)
  expect(1, movement, "string")

  if retracer.locked then return end
  table.insert(retracer.steps, movement)
  if #retracer.steps > retracer.max_length then
    table.remove(retracer.steps, 1)
  end
end

--- Write movement information to the position cache file.
---@param movement movement The movement to save.
local function write_movement(movement)
  file_helper:serialize(POSITION_CACHE, { movement, aid.position, aid.facing, aid.fuel }, true)
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
    -- We also assume that if the fuel is unlimited, we moved.
    if actual_fuel < aid.fuel or actual_fuel == "unlimited" then
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

--- Load information from the position cache.
function aid.load()
  local data = file_helper:unserialize(POSITION_CACHE)

  if data then
    local movement = data[1]
    aid.position = data[2]
    aid.facing = data[3]
    aid.fuel = data[4]

    check_movement(movement)
    write_movement("done")
    return
  end

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

--- Remove the position cache file, useful for when your program ends.
function aid.clear_save()
  file_helper:delete(POSITION_CACHE)
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
  if module ~= "empty" then
    if aid.currently_equipped.left == module then
      return false, "Module already equipped on left side."
    end
    if aid.currently_equipped.right == module then
      return false, "Module already equipped on right side."
    end
  end

  ---@type fun()
  local equip = side == "left" and turtle.equipLeft or turtle.equipRight

  if module == "empty" then
    local success_1 = select_item()

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

--- Select an empty slot.
function aid.select_empty_slot()
  select_item()
end

--- Check if a module type is equipped on a specific side.
---@param module turtle_module The module to check for.
---@param side side? The side to check. Leave nil to check both sides.
---@return side? equipped_side The equipped side, or nil if not there.
function aid.is_module_equipped(module, side)
  expect(1, module, "string")
  expect(2, side, "string", "nil")

  if not side then
    if not aid.currently_equipped.left or not aid.currently_equipped.right then
      aid.get_module_info("left")
      aid.get_module_info("right")
    end
    return (aid.currently_equipped.left == module and "left") or (aid.currently_equipped.right == module and "right") or nil
  end

  if not aid.currently_equipped[side] then
    aid.get_module_info(side)
  end
  return aid.currently_equipped[side] == module and side or nil
end

--- Get information about what module is on a specific side of the turtle.
---@param side side The side to test.
---@return string module_name
function aid.get_module_info(side)
  expect(1, side, "string")

  local ok, reason = aid.swap_module("empty", side)
  if not ok and reason ~= ("Module already equipped on %s side."):format(side) then
    error(reason, 0)
  end

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

--- Get the direction to a block relative to the turtle.
---@param block vector The block position to get the direction to.
---@param yfirst boolean? If true, the turtle will attempt to move on the Y axis first.
---@param ylast boolean? If true, the turtle will attempt to move on the Y axis last.
---@return cardinal_direction|"up"|"down"? direction The direction needed to go to the block. Returns nil if the turtle is at the block already.
---@return integer distance The distance to the block.
function aid.get_direction_to(block, yfirst, ylast)
  expect(1, block, "table")
  expect(2, yfirst, "boolean", "nil")
  expect(3, ylast, "boolean", "nil")
  if yfirst and ylast then
    error("Cannot specify both yfirst and ylast.", 2)
  end

  -- Calculate the offset on each axis from the turtle
  local x, y, z = block.x - aid.position.x, block.y - aid.position.y, block.z - aid.position.z
  local distance = math.abs(x) + math.abs(y) + math.abs(z)

  if distance == 0 then
    return nil, 0
  end

  -- For each axis, determine if we need to move in that direction
  if not yfirst and not ylast then
    if x > 0 then
      return "east", distance
    elseif x < 0 then
      return "west", distance
    elseif y > 0 then
      return "up", distance
    elseif y < 0 then
      return "down", distance
    elseif z > 0 then
      return "south", distance
    elseif z < 0 then
      return "north", distance
    end
  elseif yfirst then
    if y > 0 then
      return "up", distance
    elseif y < 0 then
      return "down", distance
    elseif x > 0 then
      return "east", distance
    elseif x < 0 then
      return "west", distance
    elseif z > 0 then
      return "south", distance
    elseif z < 0 then
      return "north", distance
    end
  elseif ylast then
    if x > 0 then
      return "east", distance
    elseif x < 0 then
      return "west", distance
    elseif z > 0 then
      return "south", distance
    elseif z < 0 then
      return "north", distance
    elseif y > 0 then
      return "up", distance
    elseif y < 0 then
      return "down", distance
    end
  end

  error("Failed to calculate direction to block.", 0)
end

--- Move forward, updating the turtle's position information.
---@return boolean success
function aid.go_forward()
  write_movement("forward")
  local success = turtle.forward()

  if success then
    aid.position = aid.position + facings[aid.facing]
    aid.fuel = aid.fuel - 1
    insert_movement("forward")
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
    insert_movement("back")
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
    insert_movement("up")
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
    insert_movement("down")
  end

  write_movement("done")
  return success
end

--- Turn left, updating the turtle's position information.
---@return boolean success
function aid.turn_left()
  write_movement("left") -- turns are to be assumed successful on reboot
  insert_movement("left")
  aid.facing = (aid.facing - 1) % 4 -- again, turns are to be assumed successful
  local success = turtle.turnLeft()

  write_movement("done")
  return success
end

--- Turn right, updating the turtle's position information.
---@return boolean success
function aid.turn_right()
  write_movement("right") -- turns are to be assumed successful on reboot
  insert_movement("right")
  aid.facing = (aid.facing + 1) % 4 -- again, turns are to be assumed successful
  local success = turtle.turnRight()

  write_movement("done")
  return success
end

--- Set the maximum distance to retrace.
---@param distance number The maximum distance to retrace.
function aid.set_retrace_distance(distance)
  expect(1, distance, "number")

  retracer.max_length = distance
end

--- Retrace the turtle's path, doing the inverse of each movement other than forward and back (since the turtle turns around).
---@param allow_digging boolean? If true, the turtle will dig out blocks in the way.
function aid.retrace(allow_digging)
  retracer.locked = true
  -- First, turn around to face the direction we came from.
  aid.turn_right()
  aid.turn_right()

  -- Now, retrace the steps. Noting the most recent step is the last one in the table.
  for i = #retracer.steps, 1, -1 do
    local movement = retracer.steps[i]

    if movement == "forward" then
      aid.gravel_protected_dig()
      aid.go_forward()
    elseif movement == "back" then
      while not aid.go_back() do
        if allow_digging then
          -- this can lead to an infinite loop if bedrock magically appears
          -- behind the turtle, but since the chances of bedrock magically appearing
          -- behind the turtle are minimal, I'm not going to implement a check
          -- for bedrock here.
          aid.turn_left()
          aid.turn_left()
          aid.gravel_protected_dig()
          aid.turn_right()
          aid.turn_right()
        else
          error("Cannot retrace path, block in the way.", 0)
        end
      end
    elseif movement == "up" then
      turtle.digDown()
      aid.go_down()
    elseif movement == "down" then
      aid.gravel_protected_dig_up()
      aid.go_up()
    elseif movement == "left" then
      aid.turn_right()
    elseif movement == "right" then
      aid.turn_left()
    end
  end

  -- And wipe the retracer.
  retracer.steps = {}
  retracer.locked = false
end

--- Turn to face the specified direction.
---@param new_facing turtle_facing|cardinal_direction The direction to face.
function aid.face(new_facing)
  expect(1, new_facing, "number", "string")

  if type(new_facing) == "number" and new_facing ~= 1 and new_facing ~= 2 and new_facing ~= 3 and new_facing ~= 0 then
    error(("Bad argument #1: expected integers 0, 1, 2, or 3; got %s."):format(new_facing), 2)
  end
  if type(new_facing) == "string" then
    if new_facing ~= "north" and new_facing ~= "east" and new_facing ~= "south" and new_facing ~= "west" then
      error(("Bad argument #1: expected strings 'north', 'east', 'south', or 'west'; got %s."):format(new_facing), 2)
    end
    new_facing = new_facing == "north" and 0 or new_facing == "east" and 1 or new_facing == "south" and 2 or 3 --[[@as turtle_facing]]
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

--- Gravel should break when hitting the turtle, but just in case it for some reason acts weird.
function aid.gravel_protected_dig_up()
  repeat
    turtle.digUp()
  until not turtle.detectUp()
end

--- Locate a chest around the turtle.
---@return boolean found_chest If the turtle found a chest. If true, the turtle is now facing the chest.
function aid.find_chest()
  for i = 1, 4 do
    if peripheral.hasType("front", "inventory") then
      return true
    end
    aid.turn_right()
  end

  return false
end

return aid
