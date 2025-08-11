--- Doggo Crafting: Aids crafting.

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
---@class Doggo.Crafting.Recipe
---@field recipe string[]
---@field items table<string, string>

---@class Doggo.Crafting
local Crafting = {}



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
---@param recipe Doggo.Crafting.Recipe The recipe to get the item costs for.
---@return table<string, integer> costs A table mapping item IDs to their required counts.
function Crafting.getRecipeCosts(recipe)
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
---@param recipe Doggo.Crafting.Recipe The recipe to use for crafting.
---@param count integer? The number of items to craft. If nil, crafts as many as possible.
---@param only_craft_exact boolean? If true, only crafts the exact number of items specified by `count`. If requesting 5 items, but only enough to craft 3, will not craft any items.
---@return integer crafted The number of items successfully crafted.
function Crafting.craft(recipe, count, only_craft_exact)
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
    local item_id = Inventory.getItemID(item)
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
---@param recipe Doggo.Crafting.Recipe The recipe to use for crafting.
---@param count integer? The number of items to craft. If nil, crafts as many as possible.
---@param only_craft_exact boolean? If true, only crafts the exact number of items specified by `count`.
---@return integer crafted The number of items successfully crafted.
function Crafting.interfacedCraft(interface, recipe, count, only_craft_exact)
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


return Crafting