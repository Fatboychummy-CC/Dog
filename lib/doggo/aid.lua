--- Doggy Aid: This module provides helper functions for dealing with peripherals within the inventory.

local expect = require "cc.expect".expect

--- Data structure for peripheral information.
---@class Doggo.Aid.PeripheralData
---@field short_name string The short name of the peripheral.
---@field wrappable boolean? Indicates if the peripheral is wrappable.
---@field methods table<string, true>? A lookup table of methods available on the peripheral. Only available if the peripheral is present and wrappable.
---@field side string? The side of the turtle where the peripheral is located, if applicable.
---@field slot integer? The inventory slot where the peripheral is located, if applicable.
---@field present boolean Indicates if the peripheral is present in the inventory or on one of the turtle's sides.

---@class Doggo.Aid
local Aid = {}

--- Stores what is currently equipped on the left and right sides of the turtle.
---@type string?, string?
local left_side, right_side;

--- Stores the last N peripheral call owners, so we can determine which peripheral is more likely to be used.
local last_n_periph_call_owners = {}
local last_n_n = 100 -- Number of calls to consider for least used peripheral.

--- Maps the item ID to its peripheral data. Dog operates under the assumption that it only ever has a single peripheral of each type.
---@type table<string, Doggo.Aid.PeripheralData>
local peripheral_data = {
  ["plethora:block_scanner"] = {
    short_name = "block_scanner",
    present = false,
    wrappable = true,
  },
  ["advancedperipherals:geoscanner"] = {
    short_name = "geoscanner",
    present = false,
    wrappable = true,
  },
  ["minecraft:diamond_pickaxe"] = {
    short_name = "pickaxe",
    present = false,
    wrappable = false,
  }
}


--#region Backwards Compatibility
do
  -- `getEquippedLeft` and `getEquippedRight` are new methods, so we need to add 'workaround' versions of the method for older versions of CC:T.
  -- Since we can't use the method directly, we have to unequip, check, then re-equip the peripheral.

  turtle.getEquippedLeft = turtle.getEquippedLeft or function()
    local id = Aid.checkPeripheralAt(Aid.unequipPeripheral("left"))

    if id then
      Aid.equipPeripheral(id, "left")
    end
  end
  turtle.getEquippedRight = turtle.getEquippedRight or function()
    Aid.unequipPeripheral("right")
    local id = Aid.checkPeripheralAt(Aid.unequipPeripheral("left"))

    if id then
      Aid.equipPeripheral(id, "right")
    end
  end
end
--#endregion Backwards Compatibility



--- Inserts the ID of the peripheral that was called into the last N calls list.
---@param id string The ID of the peripheral that was called.
local function insert_last_n_periph_call_owner(id)
  expect(1, id, "string")

  if #last_n_periph_call_owners >= last_n_n then
    table.remove(last_n_periph_call_owners, 1) -- Remove the oldest entry.
  end
  table.insert(last_n_periph_call_owners, id) -- Add the new entry.
end



--- Determines the side of the least used peripheral from the last N calls.
---@return string? side The side of the least used peripheral.
local function least_used_peripheral()
  if not left_side then
    return "left"
  elseif not right_side then
    return "right"
  end

  local lc, rc = 0, 0
  for _, id in ipairs(last_n_periph_call_owners) do
    if id == left_side then
      lc = lc + 1
    elseif id == right_side then
      rc = rc + 1
    end
  end

  if rc < lc then
    return "right"
  end

  return "left"
end



--- Determines the first empty slot in the turtle's inventory.
---@return number? index The index of the first empty slot, or nil if no empty slot is found.
function Aid.getFirstEmptySlot()
  for i = 1, 16 do
    if turtle.getItemCount(i) == 0 then
      return i
    end
  end
end



--- Selects the first empty slot in the turtle's inventory.
---@return integer index The index of the first empty slot.
function Aid.selectFirstEmptySlot()
  local index = Aid.getFirstEmptySlot()
  if index then
    turtle.select(index)
  else
    error("No empty slot found in the turtle's inventory.")
  end

  return index
end



--- Unequips the peripheral from the specified side, if it is present.
---@param side "left"|"right" The side from which to unequip the peripheral.
---@return integer index The index of the slot where the peripheral was unequipped.
function Aid.unequipPeripheral(side)
  expect(1, side, "string")
  if side ~= "left" and side ~= "right" then
    error("Bad argument #1: Expected 'left' or 'right', got " .. side, 2)
  end

  local index = Aid.selectFirstEmptySlot()
  if side == "left" then
    turtle.equipLeft()
    left_side = nil
  else
    turtle.equipRight()
    right_side = nil
  end

  -- Should automatically register that the peripheral is now in the inventory instead of on a side.
  Aid.checkPeripheralAt(index)
  return index
end



--- Finds an item in the turtle's inventory by its ID.
---@param id string The ID of the item to find.
---@return integer? slot The slot number where the item is found, or nil if not found.
function Aid.findItemInInventory(id)
  expect(1, id, "string")

  for i = 1, 16 do
    local detail = turtle.getItemDetail(i)
    if detail and detail.name == id then
      return i
    end
  end
end



--- Equips the specified peripheral on the given side.
---@param id string The ID of the peripheral to equip.
---@param side "left"|"right"|nil The side to equip the peripheral on. Leave blank to auto-select the side.
---@param force boolean? If true, forces the peripheral to be equipped if no side is available, when no side is specified.
---@return string? side The side on which the peripheral was equipped, or nil if it could not be equipped.
function Aid.equipPeripheral(id, side, force)
  expect(1, id, "string")
  if not peripheral_data[id] then
    error("Bad argument #1: Peripheral ID '" .. id .. "' does not exist.", 2)
  end
  expect(2, side, "string", "nil")
  if side and side ~= "left" and side ~= "right" then
    error("Bad argument #2: Expected 'left' or 'right', got " .. side, 2)
  end

  local data = peripheral_data[id]
  if not data.present then
    error("Peripheral '" .. id .. "' is not present in the turtle.", 2)
  end

  -- Simple resolution: peripheral already equipped on a correct side.
  if side and data.side == side then
    if side == "left" then
      left_side = id
    else
      right_side = id
    end
    return side -- Already equipped on the correct side.
  end
  if not side and data.side then
    if data.side == "left" then
      left_side = id
    else
      right_side = id
    end
    return data.side -- Already equipped on any side.
  end

  -- Less simple resolution: peripheral is equipped on a different side.
  if side and data.side ~= side then
    Aid.unequipPeripheral(data.side) -- Unequip from the current side.
    Aid.equipPeripheral(id, side)
    return side -- Now equipped on the correct side.
  end

  -- If no side is specified, auto-select the side.
  if not left_side then
    -- Find the item in the inventory.
    local slot = Aid.findItemInInventory(id)
    if not slot then
      ---@FIXME Try again, but only once, and also without rewriting this entire function.
      error("This specific case is not yet implemented. This is likely not a YOU issue.", 2)
    end
  elseif not right_side then
    --- Find the item in the inventory.
    local slot = Aid.findItemInInventory(id)
    if not slot then
      ---@FIXME Try again, but only once, and also without rewriting this entire function.
      error("This specific case is not yet implemented. This is likely not a YOU issue.", 2)
    end
  end

  -- Both sides taken, no side specified.
  if force then
    local least_used = least_used_peripheral()
    if least_used then
      Aid.unequipPeripheral(least_used) -- Unequip the least used peripheral.
      return Aid.equipPeripheral(id, least_used)
    end
  end

  return nil -- No side available, and not forced to equip.
end



--- Checks if a peripheral is present in the target slot. Updates the peripheral data accordingly.
---@param slot integer The slot number to check.
---@return string? id The ID of the peripheral if present, or nil if not.
function Aid.checkPeripheralAt(slot)
  expect(1, slot, "number")

  local detail = turtle.getItemDetail(slot)
  if detail then
    local id = detail.name
    local data = peripheral_data[id]
    if data then
      data.present = true
      data.slot = slot

      return id
    end
  end
end



--- Checks the inventory for all available peripherals, updating the internal storage of peripheral data.
function Aid.checkPeripherals()
  for _, data in pairs(peripheral_data) do
    data.present = false
  end

  --- Registers a peripheral based on the item stack.
  ---@param item ccTweaked.peripheral.item|ccTweaked.turtle.turtleDetails? item The item stack to register.
  ---@param slot integer? The slot number of the item stack, if applicable.
  ---@param side string? The side of the turtle where the peripheral is located, if applicable.
  local function register(item, slot, side)
    if not item then return end -- Ignore nil items.

    -- Ensure the peripheral is equipped and equipable.
    if item.name and peripheral_data[item.name] then
      local data = peripheral_data[item.name]
      data.present = true
      data.slot = slot
      data.side = side

      local side_equipped = Aid.equipPeripheral(item.name, nil, true)
      if not side_equipped then
        error("Cannot check peripherals, inventory full or other issue with equipping '" .. data.short_name .. "'.", 2)
      end

      if data.wrappable then
        data.methods = peripheral.getMethods(side_equipped) -- Get the methods available on the peripheral.
      else
        data.methods = nil -- Not wrappable, so no methods.
      end
    end
  end

  -- First, check what's on the sides.
  register(turtle.getEquippedLeft(), nil, "left")
  register(turtle.getEquippedRight(), nil, "right")

  -- Then, each slot inventory slot.
  for i = 1, 16 do
    register(turtle.getItemDetail(i) --[[@as ccTweaked.turtle.turtleDetails?]], i) -- Check each inventory slot.
  end
end



--- Determines which peripheral has a given method.
--- If multiple peripherals have the same method, will return whichever it comes across first.
---@param method string The method to check for.
---@return string? id The ID of the peripheral that has the method, or nil if no peripheral has the method.
function Aid.getPeripheralWithMethod(method)
  expect(1, method, "string")

  for id, data in pairs(peripheral_data) do
    if data.present and data.wrappable and (data.methods and data.methods[method]) then
      return id -- Found a peripheral with the method.
    end
  end
end



--- Calls a method on a peripheral, with any needed special cases handled.
---@param object Doggo.Aid.PeripheralData The peripheral data object to call the method on.
---@param method string The method to call on the peripheral.
---@param ... any The arguments to pass to the method.
---@return ... any The return values from the peripheral call, or `nil, "error message"` if the call failed.
local function internal_call(object, method, ...)
  expect(1, object, "table")
  expect(2, method, "string")

  if object.short_name == "pickaxe" then
    insert_last_n_periph_call_owner(object.short_name) -- Record the peripheral that was called.
    if not object.side then
      return nil, "Peripheral '" .. object.short_name .. "' is not equipped on any side."
    end
    return turtle.dig(object.side) -- Special case for pickaxe, since it doesn't have a peripheral.
  end

  if not object.wrappable then
    return nil, "Peripheral '" .. object.short_name .. "' is not wrappable. Don't know what to do with it!"
  end

  if not object.side then
    return nil, "Peripheral '" .. object.short_name .. "' is not equipped on any side."
  end

  return peripheral.call(object.side, method, ...)
end



--- Calls a method on any of the present peripherals, auto-equipping the peripheral if necessary.
--- Works essentially the same as `peripheral.call`, but does not need the peripheral's name, and can auto-equip the peripheral to make the call.
---@param method string The method to call.
---@param ... any The arguments to pass to the method.
---@return ... any The return values from the peripheral call, or `nil, "error message" if the call failed.
function Aid.call(method, ...)
  expect(1, method, "string")

  local id = Aid.getPeripheralWithMethod(method)
  if not id then
    return nil, "No peripheral with method '" .. method .. "' found."
  end

  local data = peripheral_data[id]
  if not data.present then
    return nil, "Peripheral '" .. id .. "' is not present."
  end

  if data.side then -- Already equipped!
    return internal_call(data, method, ...)
  end

  -- Not equipped, so we need to equip it.
  Aid.equipPeripheral(id, nil, true) -- Auto-select the side and force equip.
  if not data.side then
    return nil, "Failed to equip peripheral '" .. id .. "'"
  end

  return internal_call(data, method, ...)
end



--- Adds a peripheral entry to the peripheral data, so that it can be used later.
--- Only accepts wrappable peripherals.
---@param id string The ID of the peripheral to add.
---@param short_name string The short name of the peripheral.
function Aid.addPeripheral(id, short_name)
  expect(1, id, "string")
  expect(2, short_name, "string")

  if peripheral_data[id] then
    return
  end

  peripheral_data[id] = {
    short_name = short_name,
    wrappable = true,
    methods = {},
    present = false,
  }
end



return Aid