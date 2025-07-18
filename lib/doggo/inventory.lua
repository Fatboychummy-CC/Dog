--- Doggy Inventory: Simplifies inventory management for Doggo.

local expect = require "cc.expect".expect
local ph = require "parallelism_handler"
local movement = require "doggo.movement"
local equipment = require "doggo.equipment"

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



--- Returns a unique identifier for an item based on its name and NBT.
---@param item ccTweaked.turtle.turtleDetails|ccTweaked.turtle.turtleDetailsDetailed|ccTweaked.peripheral.item
---@return string id The unique identifier for the item.
local function get_item_id(item)
  expect(1, item, "table")

  return ("%s%s%s"):format(item.name, item.nbt and ":" or "", item.nbt or "")
end



--- Caches an item and its data.
---@param item ccTweaked.turtle.turtleDetailsDetailed|ccTweaked.peripheral.item
local function cache_item(item)
  expect(1, item, "table")

  local id = get_item_id(item)

  if item_cache[id] then
    -- Item is already cached, no need to cache again.
    return
  end

  item_cache[id] = {
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
    if item and not exclude_set[get_item_id(item)] then
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
      if get_item_id(item) == id then
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
      if get_item_id(item) == id then
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
      if get_item_id(item) == id then
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



--- We lazily assume that the recipe is argument #1, hopefully we won't change that in the future :D
local function validate_recipe(recipe)
  if type(recipe.recipe) ~= "table" then
    error("Bad argument #1: missing field 'recipe'.", 3)
  end
  if type(recipe.items) ~= "table" then
    error("Bad argument #1: missing field 'items'.", 3)
  end

  -- Recipe table should contain up to 3 strings of max length 3
  for i, recipe_row in ipairs(recipe.recipe) do
    if i > 3 then
      error("Bad argument #1: recipe has too many rows.", 3)
    end
    if type(recipe_row) ~= "string" or #recipe_row > 3 then
      error("Bad argument #1: invalid item at index " .. i .. ".", 3)
    end
  end

  -- Items table should contain single character keys and string values
  for key, value in pairs(recipe.items) do
    if #key ~= 1 or type(value) ~= "string" then
      error("Bad argument #1: invalid item '" .. key .. "'.", 3)
    end
  end
end



--- Gets the item costs of a recipe.
---@param recipe Doggo.Inventory.CraftingRecipe The recipe to get the item costs for.
---@return table<string, integer> costs A table mapping item IDs to their required counts.
function Inventory.getRecipeCosts(recipe)
  expect(1, recipe, "table")
  validate_recipe(recipe)

  local costs = {}
  local char_costs = {}

  -- Determine the amount of each character in the recipe.
  for _, row in ipairs(recipe.recipe) do
    for char in row:gmatch(".") do
      char_costs[char] = (char_costs[char] or 0) + 1
    end
  end

  -- Calculate the total cost for each item based on the characters.
  -- We do this in two steps so we ignore any characters that don't exist in the items table.
  for char, item_id in pairs(recipe.items) do
    costs[item_id] = (costs[item_id] or 0) + (char_costs[char] or 0)
  end

  -- Prune 0 costs. This shouldn't happen, but I don't want 0 costs in the result.
  for item_id, count in pairs(costs) do
    if count == 0 then
      costs[item_id] = nil
    end
  end

  return costs
end



--- Crafts an item using the given recipe with whatever the turtle has in its inventory. Will fail if the turtle has any extra items.
---@param recipe Doggo.Inventory.CraftingRecipe The recipe to use for crafting.
---@param count integer? The number of items to craft. If nil, crafts as many as possible.
---@param only_craft_exact boolean? If true, only crafts the exact number of items specified by `count`. If requesting 5 items, but only enough to craft 3, will not craft any items.
---@return integer crafted The number of items successfully crafted.
function Inventory.craft(recipe, count, only_craft_exact)
  expect(1, recipe, "table")
  validate_recipe(recipe)
  expect(2, count, "number", "nil")
  expect(3, only_craft_exact, "boolean", "nil")
  if count and count <= 0 then
    return 0
  end

  -- Determine the cost *per craft*.
  local costs = Inventory.getRecipeCosts(recipe)
  if not next(costs) then
    ---@TODO Check: Should we just return 0 here instead?
    error("Invalid recipe: Recipe cost is zero.", 2)
  end

  local current_items = {}
  local inventory = Inventory.getItems()
  for _, item in pairs(inventory) do
    local item_id = get_item_id(item)
    if not costs[item_id] then
      -- If the item is not in the recipe, we can't craft anything.
      return 0
    end
    current_items[item_id] = (current_items[item_id] or 0) + item.count
  end

  -- Calculate the maximum number of items we can craft, based on what is in the inventory currently.
  local max_craftable = math.huge
  for item_id, required_count in pairs(costs) do
    local available_count = current_items[item_id] or 0
    max_craftable = math.min(max_craftable, math.floor(available_count / required_count))
  end
  if max_craftable <= 0 then
    return 0 -- Not enough items to craft anything.
  end

  -- Check if we can craft the requested amount, and update the count accordingly (if `only_craft_exact` is false).
  if count and max_craftable < count then
    if only_craft_exact then
      return 0 -- Not enough items to craft the requested amount.
    else
      count = max_craftable -- Adjust to the maximum we can craft.
    end
  elseif not count then
    count = max_craftable -- Craft as many as possible.
  end

  ---@TODO Craft.


end



--- Crafts an item using the given recipe, but interfaced with a chest to find items that are needed.
---@param interface Doggo.InventoryInterface The interface to use for finding and storing items.
---@param recipe Doggo.Inventory.CraftingRecipe The recipe to use for crafting.
---@param count integer? The number of items to craft. If nil, crafts as many as possible.
---@param only_craft_exact boolean? If true, only crafts the exact number of items specified by `count`.
---@return integer crafted The number of items successfully crafted.
function Inventory.interfacedCraft(interface, recipe, count, only_craft_exact)
  expect(1, recipe, "table")
  validate_recipe(recipe)
  expect(2, count, "number", "nil")
  expect(3, interface, "table")
  expect(4, only_craft_exact, "boolean", "nil")

  if interface.isClosed() then
    error("Interface is closed.", 2)
  end

  local costs = Inventory.getRecipeCosts(recipe)

  ---@TODO Locate items in the interface and turtle's inventory.
  ---@TODO Check if we can craft the requested amount.
  ---@TODO Collect items from the interface, drop unneeded items into the interface.
  ---@TODO Call `Inventory.craft` to actually craft the item.
  ---@TODO If we need to craft more still, recursively call self with `count` adjusted.
end


---@TODO Crafting interface.
