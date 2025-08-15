--- Map. Map. Map.

local expect = require "cc.expect".expect

---@class Doggo.Mapping.Map
---@field name string The name of the map.
---@field width integer The width of the map, in blocks.
---@field height integer The height of the map, in blocks.
---@field depth integer The depth of the map, in blocks.
---@field x_offset integer The x offset of the map, in blocks. Can be used in tandem with GPS to use real positions.
---@field y_offset integer The y offset of the map, in blocks. Can be used in tandem with GPS to use real positions.
---@field z_offset integer The z offset of the map, in blocks. Can be used in tandem with GPS to use real positions.
---@field walkable_cost integer The cost of walking on the map for a regular walkable node.
---@field unknown_cost integer The cost of walking on the map for an unknown node.
---@field data Doggo.Mapping.Map.Data The data for the map.
---@field waypoints Doggo.Mapping.Map.Waypoint[] The waypoints for the map.
---@field waypoints_lookup Doggo.Mapping.Map.Waypoint[][][] The waypoints structured as a lookup table.
---@field package __SENTINEL table Sentinel value for detecting whether or not Map methods are being used correctly.
local Map = {
  __SENTINEL = {}
}

local map_mt = {
  __index = Map
}

---@class Doggo.Mapping.Map.Node
---@field name string? The name of the block, or nil if loaded from a minified map.
---@field walkable boolean Whether the block can be walked on.
---@field unknown boolean Whether the block is unknown. Used for saving/loading.
---@field cost number The cost of moving through the block. By default, unknown blocks have a cost of 5, but are marked walkable.
---@field is_waypoint boolean Whether or not this position resolves to a waypoint. Not saved.
---@field waypoint Doggo.Mapping.Map.Waypoint? The waypoint associated with this position, if any. Not saved.

---@alias Doggo.Mapping.Map.Data Doggo.Mapping.Map.DataX[]
---@alias Doggo.Mapping.Map.DataX Doggo.Mapping.Map.DataY[]
---@alias Doggo.Mapping.Map.DataY Doggo.Mapping.Map.Node[]




local function sentinel(self)
  if type(self) ~= "table" or self.__SENTINEL ~= Map.__SENTINEL then
    error("Use ':' to call Map methods", 3)
  end
end



--- Creates a 3-dimensional array that always returns an "unknown" node when the object does not exist.
---@return Doggo.Mapping.Map.Data
local function new_map_data(map)

  local innest_mt = {
    __index = function(_, z)
      return {
        name = "doggo:unknown",
        walkable = false,
        cost = map.unknown_cost,
      }
    end
  }
  local inner_mt = {
    __index = function(_, y, z)
      return setmetatable({}, innest_mt)
    end
  }
  local outer_mt = {
    __index = function(_, x, y, z)
      return setmetatable({}, inner_mt)
    end
  }

  return setmetatable({}, outer_mt)
end



--- Creates a new 3D map of the given size.
---
--- Note that it is better to use many small maps than one large one.
--- Note as well that you can resize your maps!
--- Note a third time that the map is 0-indexed!
---@param name string The name of the map, used to identify it.
---@param width integer The width of the map, in blocks.
---@param height integer The height of the map, in blocks.
---@param depth integer The depth of the map, in blocks.
function Map.new(name, width, height, depth)
  expect(1, name, "string")
  expect(2, width, "number")
  expect(3, height, "number")
  expect(4, depth, "number")

  local map = setmetatable(
    {
      name = name,
      width = width,
      height = height,
      depth = depth,
      x_offset = 0,
      y_offset = 0,
      z_offset = 0,
      walkable_cost = 1,
      unknown_cost = 5,
    },
    map_mt
  )

  map.data = new_map_data(map)

  return map
end



--- Sets the offset of the map. This offsets every input position by the map's offset.
--- Note that it needs to be *negative* offsets, for example, if the turtle is at 10, 20, 5, the offsets should be -10, -20, -5.
---@param self Doggo.Mapping.Map
---@param x integer The x offset, in blocks.
---@param y integer The y offset, in blocks.
---@param z integer The z offset, in blocks.
function Map:setOffset(x, y, z)
  sentinel(self)
  expect(2, x, "number")
  expect(3, y, "number")
  expect(4, z, "number")

  self.x_offset = x
  self.y_offset = y
  self.z_offset = z
end



--- Sets the default cost of walkable blocks.
---@param self Doggo.Mapping.Map
---@param cost number The cost of walkable blocks.
function Map:setWalkableCost(cost)
  sentinel(self)
  expect(2, cost, "number")

  self.walkable_cost = cost
end



--- Sets the default cost of unknown blocks.
---@param self Doggo.Mapping.Map
---@param cost number The cost of unknown blocks.
function Map:setUnknownCost(cost)
  sentinel(self)
  expect(2, cost, "number")

  self.unknown_cost = cost
end



--- Pushes a new block to the map.
---@param self Doggo.Mapping.Map
---@param x integer The x position of the block, in blocks.
---@param y integer The y position of the block, in blocks.
---@param z integer The z position of the block, in blocks.
---@param walkable boolean Whether the block can be walked on.
---@param name string? The name, if known.
function Map:pushBlock(x, y, z, walkable, name)
  sentinel(self)
  expect(2, x, "number")
  expect(3, y, "number")
  expect(4, z, "number")
  expect(5, walkable, "boolean")
  expect(6, name, "string", true)

  if x < 0 or y < 0 or z < 0 or x > self.width or y > self.height or z > self.depth then
    return -- Do nothing.
  end

  if not self.data[x] then
    self.data[x] = {}
  end
  if not self.data[x][y] then
    self.data[x][y] = {}
  end

  self.data[x][y][z] = {
    name = name or "doggo:unknown",
    walkable = walkable,
    unknown = false,
    cost = self.walkable_cost,
  }
end
Map.set = Map.pushBlock -- Short alias.



--- Sets a position to unknown.
---@param self Doggo.Mapping.Map
---@param x integer The x position of the block, in blocks.
---@param y integer The y position of the block, in blocks.
---@param z integer The z position of the block, in blocks.
function Map:setUnknown(x, y, z)
  sentinel(self)
  expect(2, x, "number")
  expect(3, y, "number")
  expect(4, z, "number")

  local block = self:getBlock(x, y, z)
  if block then
    block.unknown = true
  end
end
Map.unset = Map.setUnknown -- Short alias.


--- Gets the block at a given position.
---@param self Doggo.Mapping.Map
---@param x integer The x position of the block, in blocks.
---@param y integer The y position of the block, in blocks.
---@param z integer The z position of the block, in blocks.
---@return Doggo.Mapping.Map.Node
function Map:getBlock(x, y, z)
  sentinel(self)
  expect(2, x, "number")
  expect(3, y, "number")
  expect(4, z, "number")

  return self.data[x][y][z]
end
Map.at = Map.getBlock -- Short alias.



--- Resizes the map, destroying anything outside the new bounds.
---@param self Doggo.Mapping.Map
---@param width integer The new width of the map, in blocks.
---@param height integer The new height of the map, in blocks.
---@param depth integer The new depth of the map, in blocks.
function Map:resize(width, height, depth)
  sentinel(self)
  expect(2, width, "number")
  expect(3, height, "number")
  expect(4, depth, "number")

  self.width = width
  self.height = height
  self.depth = depth

  local marked = {}

  for x, Xs in pairs(self.data) do
    if x > width then
      marked[x] = true
    else
      for y, Ys in pairs(Xs) do
        if y > height then
          if not marked[x] then marked[x] = {} end
          marked[x][y] = true
        else
          for z, _ in pairs(Ys) do
            if z > depth then
              if not marked[x][y] then marked[x][y] = {} end
              marked[x][y][z] = true
            end
          end
        end
      end
    end
  end

  for x, Xs in pairs(marked) do
    if type(Xs) == "table" then
      for y, Ys in pairs(Xs) do
        if type(Ys) == "table" then
          for z in pairs(Ys) do
            self.data[x][y][z] = nil -- Remove the block.
          end
        else
          self.data[x][y] = nil -- Remove the whole section.
        end
      end
    else
      self.data[x] = nil -- Remove the whole section.
    end
  end
end



--- Adds a waypoint to the map.
---@param self Doggo.Mapping.Map
---@param waypoint Doggo.Mapping.Map.Waypoint The waypoint to add.
function Map:addWaypoint(waypoint)
  sentinel(self)
  expect(2, waypoint, "table")

  table.insert(self.waypoints, waypoint)
end



---@TODO Allow splicing maps together (this does not fully *combine* them, just allows them to access each-other as if they were a single map.)
---@TODO Allow rotating maps in any direction (90 degree steps).
---@TODO Allow flipping maps along all axes.
---@TODO Add map searching for block IDs.
---@TODO Add waypoint/landmark system for turtle navigation checkpoints.
---@TODO Add support for temporary obstacles (other turtles, players).



return Map