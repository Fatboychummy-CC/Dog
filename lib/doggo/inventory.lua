--- Doggy Inventory: Simplifies inventory management for Doggo.

local expect = require "cc.expect".expect
local ph = require("lib.parallelism_handler")

---@class Doggo.Inventory
local Inventory = {}



--- Returns every item in the turtle's inventory.
---@return ccTweaked.peripheral.itemList items A list with basic information about every item in the turtle's inventory.
function Inventory.getItems()
  local items = {}

  for i = 1, 16 do
    items[i] = turtle.getItemDetail(i)
  end

  return items
end



--- Returns detailed information about every item in the turtle's inventory.
---@return ccTweaked.peripheral.itemList detailed_items A list with detailed information about every item.
function Inventory.getDetailedItems()
  local handler = ph()

  for i = 1, 16 do
    handler:add_task(function()
      return turtle.getItemDetail(i, true)
    end)
  end

  return handler:execute()
end



--- Returns the number of free slots in the turtle's inventory.
---@return integer free_slots The number of free slots in the turtle's inventory.
function Inventory.getFreeSlots()
  local free_slots = 0

  for i = 1, 16 do
    if turtle.getItemCount(i) == 0 then
      free_slots = free_slots + 1
    end
  end

  return free_slots
end



-- Returns the number of used slots in the turtle's inventory.
---@return integer used_slots The number of used slots in the turtle's inventory.
function Inventory.getUsedSlots()
  return 16 - Inventory.getFreeSlots()
end



--- Dumps the turtle's inventory into the given chest.
---@param direction "up"|"down"|nil The direction to dump the inventory into. If nil, it will dump into the chest in front of the turtle.
---@param exclude string[]? A list of item IDs to exclude from the dump.
function Inventory.dump(direction, exclude)
  expect(1, direction, "string", "nil")
  expect(2, exclude, "table", "nil")
  exclude = exclude or {}

  local exclude_set = {}
  for _, id in ipairs(exclude) do
    exclude_set[id] = true
  end

  for i = 1, 16 do
    local item = turtle.getItemDetail(i)
    if item and not exclude_set[item.name] then
      turtle.select(i)
      if direction then
        if direction == "up" then
          turtle.dropUp()
        else
          turtle.dropDown()
        end
      else
        turtle.drop()
      end
    end
  end
end



---@TODO Some kind of interface method to interface with a chest, grab specific items, etc.
---@TODO Crafting interface.
