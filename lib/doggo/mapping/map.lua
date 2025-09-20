--- Map. Map. Map.

local expect = require "cc.expect".expect
local Chunk = require "doggo.mapping.chunk"
local Position = require "doggo.mapping.position"

---@class Doggo.Mapping.Map
---@field name string The name of the map.
---@field offset ccTweaked.Vector The world offset of the chunk at 0,0,0.
---@field data Doggo.Mapping.Chunk[][][] The chunks structured as a 3D array.
---@field waypoints Doggo.Mapping.Map.Waypoint[] The waypoints for the map.
---@field waypoints_locations Doggo.Mapping.Map.Waypoint[][][] The waypoints structured as a lookup table of x, y, z coordinates.
---@field waypoints_ids table<string, Doggo.Mapping.Map.Waypoint> The waypoints structured as a lookup table of names.
---@field package __SENTINEL table Sentinel value for detecting whether or not Map methods are being used correctly.
local Map = {
  __SENTINEL = {}
}

local map_mt = {
  __index = Map
}



local function sentinel(self)
  if type(self) ~= "table" or self.__SENTINEL ~= Map.__SENTINEL then
    error("Use ':' to call Map methods", 3)
  end
end



--- Creates a new map.
---@param name string The name of the map.
---@param offset ccTweaked.Vector? The world offset of the chunk at 0,0,0. Defaults to (0,0,0).
---@return Doggo.Mapping.Map
function Map.new(name, offset)
  expect(1, name, "string")
  expect(2, offset, "table", "nil")

  offset = offset or Position.new(0, 0, 0)

  if not Position.isValid(offset) then
    error("Invalid offset", 2)
  end

  if offset.x % 1 ~= 0 or offset.y % 1 ~= 0 or offset.z % 1 ~= 0 then
    error("Offsets must be integers", 2)
  end

  local self = setmetatable({
    name = name,
    offset = offset,
    data = {},
    waypoints = {},
    waypoints_locations = {},
    waypoints_ids = {},
  }, map_mt)

  return self
end



--- Adds a new chunk to the map, at the given chunk position.
---@param self Doggo.Mapping.Map
---@param position ccTweaked.Vector The position of the chunk in chunk coordinates.
---@return Doggo.Mapping.Chunk chunk The newly created chunk.
function Map:addChunk(position)
  sentinel(self)
  expect(1, position, "table")

  if not Position.isValid(position) then
    error("Invalid position", 2)
  end

  if self.data[position.x] and
     self.data[position.x][position.y] and
     self.data[position.x][position.y][position.z] then
    error("Chunk already exists at this position", 2)
  end

  local chunk = Chunk.new(position)
  self.data[position.x] = self.data[position.x] or {}
  self.data[position.x][position.y] = self.data[position.x][position.y] or {}
  self.data[position.x][position.y][position.z] = chunk

  return chunk
end



--- Get the chunk at the given chunk position.
---@param self Doggo.Mapping.Map
---@param position ccTweaked.Vector The position of the chunk in chunk coordinates.
---@return Doggo.Mapping.Chunk? chunk The chunk at the given position, or nil if it doesn't exist.
function Map:getChunk(position)
  sentinel(self)
  expect(1, position, "table")

  if not Position.isValid(position) then
    error("Invalid position", 2)
  end

  if not self.data[position.x] or
     not self.data[position.x][position.y] then
    return nil
  end

  return self.data[position.x][position.y][position.z]
end



--- Inserts a block into the map at the given world position.
---@param self Doggo.Mapping.Map
---@param position ccTweaked.Vector The world position of the block.
---@param walkable boolean Whether or not the block is walkable.
---@param name string? The name of the block, or nil if unknown.
function Map:addBlock(position, walkable, name)
  sentinel(self)
  expect(1, position, "table")
  expect(2, walkable, "boolean")
  expect(3, name, "string", "nil")

  if not Position.isValid(position) then
    error("Invalid position", 2)
  end

  local chunk_coords = Position.worldToChunkCoordinates(position)
  local chunk = self:getChunk(chunk_coords)
  if not chunk then
    chunk = self:addChunk(chunk_coords)
  end

  chunk:addBlock(position, walkable, name)
end



--- Gets the block at the given world position.
---@param self Doggo.Mapping.Map
---@param position ccTweaked.Vector The world position of the block.
---@return Doggo.Mapping.Chunk.BlockData block The block data.
function Map:getBlock(position)
  sentinel(self)
  expect(1, position, "table")

  if not Position.isValid(position) then
    error("Invalid position", 2)
  end

  local chunk_coords = Position.worldToChunkCoordinates(position)
  local chunk = self:getChunk(chunk_coords)
  if not chunk then
    return Chunk.unknownBlock(position)
  end

  return chunk:getBlock(position)
end



--- Adds a waypoint to the map.
---@param self Doggo.Mapping.Map
---@param waypoint Doggo.Mapping.Map.Waypoint The waypoint to add.
function Map:addWaypoint(waypoint)
  sentinel(self)
  expect(1, waypoint, "table")

  if not Position.isValid(waypoint.position) then
    error("Invalid waypoint position", 2)
  end

  table.insert(self.waypoints, waypoint)

  local pos = waypoint.position
  self.waypoints_locations[pos.x] = self.waypoints_locations[pos.x] or {}
  self.waypoints_locations[pos.x][pos.y] = self.waypoints_locations[pos.x][pos.y] or {}
  self.waypoints_locations[pos.x][pos.y][pos.z] = waypoint
end



--- Removes a waypoint from the map.
---@param self Doggo.Mapping.Map
---@param waypoint Doggo.Mapping.Map.Waypoint The waypoint to remove.
function Map:removeWaypoint(waypoint)
  sentinel(self)
  expect(1, waypoint, "table")

  local pos = waypoint.position
  if self.waypoints_locations[pos.x] and
     self.waypoints_locations[pos.x][pos.y] and
     self.waypoints_locations[pos.x][pos.y][pos.z] == waypoint then
    -- Remove the waypoint from the lookup table
    self.waypoints_locations[pos.x][pos.y][pos.z] = nil

    -- Clean up empty tables
    if not next(self.waypoints_locations[pos.x][pos.y]) then
      self.waypoints_locations[pos.x][pos.y] = nil
    end
    if not next(self.waypoints_locations[pos.x]) then
      self.waypoints_locations[pos.x] = nil
    end
  end

  local index
  for i, wp in ipairs(self.waypoints) do
    if wp == waypoint then
      index = i
      break
    end
  end

  if not index then
    return
  end

  table.remove(self.waypoints, index)
end



--- Get waypoints within a given range.
---@param self Doggo.Mapping.Map
---@param position ccTweaked.Vector The center position.
---@param range number The range to search within.
---@return Doggo.Mapping.Map.Waypoint[] waypoints The waypoints within the given range.
function Map:getWaypointsInRange(position, range)
  sentinel(self)
  expect(1, position, "table")
  expect(2, range, "number")

  if not Position.isValid(position) then
    error("Invalid position", 2)
  end

  if range < 0 then
    error("Range must be non-negative", 2)
  end

  local waypoints_in_range = {}

  for _, waypoint in ipairs(self.waypoints) do
    if (position - waypoint.position):length() <= range then
      table.insert(waypoints_in_range, waypoint)
    end
  end

  return waypoints_in_range
end



return Map