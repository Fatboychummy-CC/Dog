--- Doggy Aid: This module provides helper functions for dealing with peripherals and the inventory.

local expect = require "cc.expect".expect

--- Data structure for peripheral information.
---@class Dog.Aid.PeripheralData
---@field short_name string The short name of the peripheral.
---@field wrappable boolean? Indicates if the peripheral is wrappable.
---@field methods table<string, true>? A lookup table of methods available on the peripheral. Only available if the peripheral is present and wrappable.
---@field side string? The side of the turtle where the peripheral is located, if applicable.
---@field slot integer? The inventory slot where the peripheral is located, if applicable.
---@field present boolean Indicates if the peripheral is present in the inventory or on one of the turtle's sides.

---@class Dog.Aid
local Aid = {}


--- Maps the item ID to its peripheral data. Dog operates under the assumption that it only ever has a single peripheral of each type.
---@type table<string, Dog.Aid.PeripheralData>
local peripheral_data = {
  ["plethora:block_scanner"] = {
    short_name = "plethora:block_scanner",
    present = false,
    wrappable = true,
  },
  ["advancedperipherals:geoscanner"] = {
    short_name = "advancedperipherals:geoscanner",
    present = false,
    wrappable = true,
  },
  ["minecraft:diamond_pickaxe"] = {
    short_name = "minecraft:diamond_pickaxe",
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
  else
    turtle.equipRight()
  end

  -- Should automatically register that the peripheral is now in the inventory instead of on a side.
  Aid.checkPeripheralAt(index)
  return index
end



--- Equips the specified peripheral on the given side.
---@param id string The ID of the peripheral to equip.
---@param side "left"|"right"|nil The side to equip the peripheral on. Leave blank to auto-select the side.
function Aid.equipPeripheral(id, side)
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
    error("Peripheral '" .. id .. "' is not present in the turtle's inventory.", 2)
  end

  if side and data.side == side then
    return -- Already equipped on the correct side.
  end

  if not side and data.side then
    return -- Already equipped on any side.
  end

  if side and data.side ~= side then
    Aid.unequipPeripheral(data.side) -- Unequip from the current side.
  end


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
  for id, data in pairs(peripheral_data) do
    data.present = false
  end
end