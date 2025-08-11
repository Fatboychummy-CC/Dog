--- Doggy Inventory: Simplifies inventory management for Doggo.

local expect = require "cc.expect".expect
local ph = require "parallelism_handler"
local movement = require "doggo.movement"
local equipment = require "doggo.equipment"

---@class Doggo.Inventory.CachedItem
---@field name string The item ID.
---@field displayName string The full name of the item.
---@field nbt string? The NBT hash of the item, if applicable.
---@field max_count integer The maximum stack size of the item.

---@class Doggo.Inventory
local Inventory = {}

--- Holds a cache of item IDs (plus optional NBT) to their full names.
--- i.e: ["minecraft:enchanted_book:<NBT_HASH>"] = "Protection IV"
---@type table<string, Doggo.Inventory.CachedItem>
local item_cache = {}

--- Holds a cache of items inside the turtle's inventory.
---@type ccTweaked.turtle.turtleDetails[]
local inventory_cache = {}



--- Returns a unique identifier for an item based on its name and NBT.
---@param item ccTweaked.turtle.turtleDetails|ccTweaked.turtle.turtleDetailsDetailed|ccTweaked.peripheral.item
---@return string id The unique identifier for the item.
function Inventory.getItemID(item)
  expect(1, item, "table")

  return ("%s%s%s"):format(item.name, item.nbt and ":" or "", item.nbt or "")
end



--- Caches an item and its data.
---@param item ccTweaked.turtle.turtleDetailsDetailed|ccTweaked.peripheral.item
local function cache_item(item)
  expect(1, item, "table")

  local id = Inventory.getItemID(item)

  if item_cache[id] then
    -- Item is already cached, no need to cache again.
    return
  end

  item_cache[id] = {
    name = item.name,
    displayName = item.displayName,
    nbt = item.nbt,
    max_count = item.maxCount,
  }
end



--- Returns every item in the turtle's inventory.
---@return ccTweaked.turtle.turtleDetails[] items A list with basic information about every item in the turtle's inventory.
function Inventory.getItems()
  inventory_cache = {} -- Reset the cache.

  for i = 1, 16 do
    inventory_cache[i] = turtle.getItemDetail(i) --[[@as ccTweaked.turtle.turtleDetails?]]
  end

  return inventory_cache
end



--- Returns detailed information about every item in the turtle's inventory.
---@return ccTweaked.turtle.turtleDetailsDetailed[] detailed_items A list with detailed information about every item.
function Inventory.getDetailedItems()
  local handler = ph()

  for i = 1, 16 do
    handler:add_task(function()
      local detail = turtle.getItemDetail(i, true) --[[@as ccTweaked.turtle.turtleDetailsDetailed?]]

      if detail then
        cache_item(detail)
      end

      return detail
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
    if item and not exclude_set[Inventory.getItemID(item)] then
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



--- Interfaces with a chest on the given side.
--- If given a side other than "front", "top", or "bottom", will turn to face that side.
---@param side ccTweaked.peripheral.computerSide The side of the turtle to interface with the chest.
---@return Doggo.InventoryInterface interface An interface to interact with the chest.
function Inventory.interface(side)
  expect(1, side, "string")

  if side ~= "front" and side ~= "top" and side ~= "bottom" then
    if side == "right" then
      ---@FIXME Fill this in when movement is implemented.
    elseif side == "left" then
      ---@FIXME Fill this in when movement is implemented.
    elseif side == "back" then
      ---@FIXME Fill this in when movement is implemented.
    end

    --- Since we will now be facing the chest.
    side = "front"
  end

  --- Facing the chest now, or it's above/below us.

  --- An interface for interacting with a chest in a more abstract way.
  ---@class Doggo.InventoryInterface
  ---@field items ccTweaked.peripheral.itemList A list of items in the chest.
  ---@field size integer The number of slots in the chest.
  local interface = {
    items = {},
    size = 0,
  }
  local closed = false
  local function _closed()
    if closed then
      error("Interface closed.", 3)
    end
  end



  --- Rescans the inventory and updates the items list.
  function interface.rescan()
    _closed()
    local handler = ph()

    interface.items = {}

    local list = peripheral.call(side, "list") --[[@as ccTweaked.peripheral.itemList]]
    for slot, item in pairs(list) do
      handler:add_task(function()
        local detail = peripheral.call(side, "getItemDetail", slot) --[[@as ccTweaked.turtle.turtleDetailsDetailed?]]
        if detail then
          cache_item(detail)
        end
        interface.items[slot] = item
      end)
    end

    handler:add_task(function()
      interface.size = peripheral.call(side, "size")
    end)

    handler:execute()
  end



  --- Locates an item by its ID.
  ---@return ... integer slots The slots where the item is located.
  function interface.locateItem(id)
    _closed()
    expect(1, id, "string")

    local slots = {}
    for slot, item in pairs(interface.items) do
      if Inventory.getItemID(item) == id then
        table.insert(slots, slot)
      end
    end

    return table.unpack(slots)
  end



  --- Counts the number of a specific item in the chest.
  ---@param id string The item ID to count.
  ---@return integer count The number of items found.
  function interface.countItem(id)
    _closed()
    expect(1, id, "string")

    local count = 0
    for _, item in pairs(interface.items) do
      if Inventory.getItemID(item) == id then
        count = count + item.count
      end
    end

    return count
  end



  --- Collects a specific item from the chest.
  ---@TODO This method can be parallelised, I just am too lazy to do it right now.
  ---@param id string The item ID to collect.
  ---@param count integer The number of items to collect.
  ---@return integer collected The number of items successfully collected.
  function interface.collectItem(id, count)
    _closed()
    expect(1, id, "string")
    expect(2, count, "number")

    local collected = 0
    for slot, item in pairs(interface.items) do
      if Inventory.getItemID(item) == id then
        local to_collect = math.min(item.count, count - collected)

        -- Transfer that many items to the first slot.
        local moved = interface.transferTo(slot, 1, to_collect, true)
        collected = collected + moved

        if side == "top" then
          turtle.suckUp(to_collect)
        elseif side == "bottom" then
          turtle.suckDown(to_collect)
        else
          turtle.suck(to_collect)
        end
      end

      if collected >= count then
        break
      end
    end

    return collected
  end



  --- Locates the first empty slot in the chest.
  ---@return integer? slot The first empty slot, or nil if no empty slots are found.
  function interface.findEmptySlot()
    _closed()
    for slot = 1, interface.size do
      if not interface.items[slot] then
        return slot
      end
    end
  end



  --- Transfers an item from one position on the inventory to another.
  ---@param from integer The slot to transfer from.
  ---@param to integer The slot to transfer to.
  ---@param limit integer? The number of items to transfer. If nil, transfers the entire stack.
  ---@param force boolean? If true, moves any items in the destination slot to the next available slot, then transfers the item.
  ---@return integer moved The number of items transferred.
  function interface.transferTo(from, to, limit, force)
    _closed()
    expect(1, from, "number")
    expect(2, to, "number")
    expect(3, limit, "number", "nil")
    expect(4, force, "boolean", "nil")

    if force then
      if interface.items[to] then
        -- Move the existing item in the destination slot to the next available slot.
        local next_slot = interface.findEmptySlot()
        if next_slot then
          interface.transferTo(to, next_slot)
        else
          return 0
        end
      end
    end

    return peripheral.call(side, "pushItems", side, from, limit, to)
  end



  --- Closes the interface, disallowing further interactions.
  function interface.close()
    _closed()
    closed = true
    interface.items = nil
    interface.size = 0
  end



  function interface.isClosed()
    return closed
  end



  interface.rescan() -- Initial scan to populate the items list.
  return interface
end



--- Moves an item from one slot to another, preserving the turtle item cache.
---@param from_slot integer The slot to move the item from.
---@param to_slot integer The slot to move the item to.
---@param limit integer? The maximum number of items to move. If nil, moves the entire stack.
---@return integer moved The number of items successfully moved.
function Inventory.moveItems(from_slot, to_slot, limit)
  expect(1, from_slot, "number")
  expect(2, to_slot, "number")
  expect(3, limit, "number", "nil")

  if from_slot == to_slot then
    return 0 -- No need to move.
  end

  local from_item = inventory_cache[from_slot]
  local to_item = inventory_cache[to_slot]

  if from_item.name ~= to_item.name then
    -- If the items are different, we can't move them.
    return 0
  end

  turtle.select(from_slot)
  local success = turtle.transferTo(to_slot, limit)

  if not success then
    return 0
  end

  -- Update the cache
  Inventory.getItems()

  -- Check how many items were actually moved.
  if not inventory_cache[from_slot] then
    -- The entire stack was moved.
    return from_item.count
  elseif not inventory_cache[to_slot] then
    -- This case shouldn't be possible, but would mean we moved 0 items.
    return 0
  end

  -- We moved *some* items, subtract the current count from the original.
  return from_item.count - inventory_cache[from_slot].count
end



--- Gets the next available slot in the turtle's inventory.
---@return integer? slot The next available slot, or nil if no slots are available.
function Inventory.availableSlot()
  for i = 1, 16 do
    if not inventory_cache[i] then
      return i -- Found an empty slot.
    end
  end
  return nil -- No empty slots found.
end



--- Forcefully moves an item from one slot to another, moving anything that is in the way to the next available slot.
---
--- - If the `to_slot` is occupied by a *different* item, moves it to the next available slot.
--- - If the `to_slot` is occupied by the same item, moves *overflow* to the next available slot.
---@param from_slot integer The slot to move the item from.
---@param to_slot integer The slot to move the item to.
---@param limit integer? The maximum number of items to move. If nil, moves the entire stack.
---@param no_overflow boolean? If true, does not move overflow items to the next available slot -- Leaves them in the `from_slot`.
---@return integer moved The number of items successfully moved.
function Inventory.forceMoveItems(from_slot, to_slot, limit, no_overflow)
  expect(1, from_slot, "number")
  expect(2, to_slot, "number")
  expect(3, limit, "number", "nil")
  if from_slot == to_slot then
    return 0 -- No need to move.
  end
  local from_item = inventory_cache[from_slot]
  local to_item = inventory_cache[to_slot]
  if not from_item then
    return 0
  end
  if not to_item then
    -- If the destination slot is empty, just move the item.
    return Inventory.moveItems(from_slot, to_slot, limit)
  end
  if from_item.name == to_item.name then
    -- If the items are the same, we can move them directly then handle overflow.
    local moved = Inventory.moveItems(from_slot, to_slot, limit)
    if moved < limit and not no_overflow then
      -- Move the overflow
      local overflow_limit = limit and (limit - moved) or nil
      return moved + Inventory.moveItems(from_slot, Inventory.availableSlot() or to_slot, overflow_limit)
    end
    return moved
  end

  -- Items are different, we can only move to the overflow.
  if not no_overflow then
    -- Move the item in the `to_slot` to the next available slot.
    local next_slot = Inventory.availableSlot()
    if next_slot then
      return Inventory.moveItems(to_slot, next_slot)
    end
  end

  -- We are unable to move the item if we reach this point.
  return 0
end



--- Locates an item in the turtle's inventory.
---@param id string The item ID to locate.
---@return ... integer slots The slots where the item is located.
function Inventory.locateItem(id)
  expect(1, id, "string")

  local slots = {}
  for slot, item in pairs(inventory_cache) do
    if get_item_id(item) == id then
      table.insert(slots, slot)
    end
  end

  return table.unpack(slots)
end



--- "Defrags" the turtle's inventory by moving items around to fill partially filled slots.
function Inventory.defrag()
  local items = Inventory.getItems()

  ---@TODO Finish this function.
end



--- Listens for inventory changes and updates the inventory cache.
--- Needs to be ran in parallel.
function Inventory.listen()
  while true do
    os.pullEvent("turtle_inventory")
    Inventory.getDetailedItems()
  end
end



--- Periodically rescans the inventory and updates the inventory cache.
--- Needs to be ran in parallel.
---@param period number? The time in seconds between rescans. Defaults to 5 seconds.
function Inventory.periodicRescan(period)
  expect(1, period, "number", "nil")
  period = period or 5

  while true do
    os.sleep(period)
    Inventory.getDetailedItems()
  end
end



Inventory.getDetailedItems()
return Inventory
