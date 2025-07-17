--- Doggy Inventory: Simplifies inventory management for Doggo.

local expect = require "cc.expect".expect
local ph = require "parallelism_handler"
local movement = require "doggo.movement"
local aid = require "doggo.aid"

---@class Doggo.Inventory.CachedItem
---@field id string The item ID.
---@field name string The full name of the item.
---@field nbt string? The NBT hash of the item, if applicable.
---@field max_count integer The maximum stack size of the item.

--- Represents a crafting recipe.
--- ```lua
--- local recipe = {
---   recipe = {
---     "AAA",
---     "XBX",
---     "XBX"
---   },
---   items = {
---     A = "minecraft:iron_ingot",
---     B = "minecraft:stick",
---   }
--- }
--- ```
---@class Doggo.Inventory.CraftingRecipe
---@field recipe string[]
---@field items table<string, string>

---@class Doggo.Inventory
local Inventory = {}

--- Holds a cache of item IDs (plus optional NBT) to their full names.
--- i.e: ["minecraft:enchanted_book:<NBT_HASH>"] = "Protection IV"
---@type table<string, Doggo.Inventory.CachedItem>
local item_cache = {}



--- Caches an item and its data.
---@param item ccTweaked.turtle.turtleDetailsDetailed|ccTweaked.peripheral.item
local function cache_item(item)
  expect(1, item, "table")

  if item_cache[item.name] then
    -- Item is already cached, no need to cache again.
    return
  end

  item_cache[item.name] = {
    id = item.name,
    name = item.displayName,
    nbt = item.nbt,
    max_count = item.maxCount,
  }
end



--- Returns every item in the turtle's inventory.
---@return ccTweaked.turtle.turtleDetails[] items A list with basic information about every item in the turtle's inventory.
function Inventory.getItems()
  ---@type ccTweaked.turtle.turtleDetails[]
  local items = {}

  for i = 1, 16 do
    items[i] = turtle.getItemDetail(i) --[[@as ccTweaked.turtle.turtleDetails?]]
  end

  return items
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
      if item.name == id then
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
      if item.name == id then
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
      if item.name == id then
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



  return interface
end



--- Crafts an item using the given recipe with whatever the turtle has in its inventory. Will fail if the turtle has any extra items.
---@param recipe Doggo.Inventory.CraftingRecipe The recipe to use for crafting.
---@param count integer? The number of items to craft. If nil, crafts as many as possible.
---@return integer crafted The number of items successfully crafted.
function Inventory.craft(recipe, count)
  expect(1, recipe, "table")
  expect(2, count, "number", "nil")
  if type(recipe.recipe) ~= "table" then
    error("Bad argument #1: missing field 'recipe'.", 2)
  end
  if type(recipe.items) ~= "table" then
    error("Bad argument #1: missing field 'items'.", 2)
  end

  -- Recipe table should contain up to 3 strings of max length 3
  for i, recipe_row in ipairs(recipe.recipe) do
    if i > 3 then
      error("Bad argument #1: recipe has too many rows.", 2)
    end
    if type(recipe_row) ~= "string" or #recipe_row > 3 then
      error("Bad argument #1: invalid item at index " .. i .. ".", 2)
    end
  end

  -- Items table should contain single character keys and string values
  for key, value in pairs(recipe.items) do
    if #key ~= 1 or type(value) ~= "string" then
      error("Bad argument #1: invalid item '" .. key .. "'.", 2)
    end
  end

  ---@TODO Determine count of each item needed based on the recipe
  ---@TODO Check if the turtle has enough of each item (multiply by count)
  ---@TODO Check if any additional items are in the turtle's inventory (return 0)
  ---@TODO Craft.
end



--- Crafts an item using the given recipe, but interfaced with a chest to find items that are needed.
---@param recipe Doggo.Inventory.CraftingRecipe The recipe to use for crafting.
---@param count integer? The number of items to craft. If nil, crafts as many as possible.
---@param interface Doggo.InventoryInterface The interface to use for finding items.
---@return integer crafted The number of items successfully crafted.
function Inventory.interfacedCraft(recipe, count, interface)
  expect(1, recipe, "table")
  expect(2, count, "number", "nil")
  expect(3, interface, "table")

  ---@TODO This entire method.
end


---@TODO Crafting interface.
