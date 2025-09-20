--- Map Chunk

local expect = require "cc.expect".expect
local Position = require "doggo.mapping.position"

---@alias Doggo.Mapping.Chunk.ChunkReference Doggo.Mapping.Chunk|string

--- A chunk is a 16x16x16 section of a map.
--- Chunks are created automatically when a map is created,
--- and are used to store the actual block data.
---
---@class Doggo.Mapping.Chunk
---@field data Doggo.Mapping.Chunk.BlockData[][][] The block data of this chunk.
---@field id string The unique identifier of this chunk.
---@field package __SENTINEL table A sentinel value to prevent accidental misuse of the chunk API.
local Chunk = {
  __SENTINEL = {}
}

local chunk_mt = {
  __index = Chunk
}

---@class Doggo.Mapping.Chunk.BlockData
---@field name string? The block name, e.g. "minecraft:stone". May be nil on loading a map, if the map is in the "small" format.
---@field walkable boolean Whether the block can be walked on.
---@field position ccTweaked.Vector The position of this block within the chunk.
---@field world_position ccTweaked.Vector The position of this block in the world.
local Block = {}

local block_mt = {
  ---@param a Doggo.Mapping.Chunk.BlockData
  ---@param b Doggo.Mapping.Chunk.BlockData
  __eq = function(a, b)
    return a.position.x == b.position.x
       and a.position.y == b.position.y
       and a.position.z == b.position.z
  end,
  __index = Block
}



local neighbour_directions = {
  vector.new(1, 0, 0),
  vector.new(-1, 0, 0),
  vector.new(0, 1, 0),
  vector.new(0, -1, 0),
  vector.new(0, 0, 1),
  vector.new(0, 0, -1),
}
--- Gets the neighboring blocks of this block.
---@param map Doggo.Mapping.Map The map this block is part of.
---@return Doggo.Mapping.Chunk.BlockData[] neighbours The neighboring blocks.
function Block:neighbours(map)
  local neighbours = {}
  for _, dir in ipairs(neighbour_directions) do
    local neighbour_pos = self.position + dir
    local neighbour_block = map:getBlock(neighbour_pos)
    if neighbour_block then
      neighbours[#neighbours + 1] = neighbour_block
    end
  end
  return neighbours
end



local function sentinel(self)
  if type(self) ~= "table" or self.__SENTINEL ~= Chunk.__SENTINEL then
    error("Use ':' to call Chunk methods", 3)
  end
end



--- Gets the unique identifier of a chunk.
---@param position ccTweaked.Vector
---@return string ID The ID of the chunk.
local function chunk_id(position)
  local chunk_pos = Position.worldToChunkSpace(position)
  return string.format("%d,%d,%d", chunk_pos.x, chunk_pos.y, chunk_pos.z)
end



--- Creates a blank block data structure.
---@param position ccTweaked.Vector The position of the block in local chunk coordinates (0-
function Chunk.unknownBlock(position)
  expect(1, position, "table")
  if not Position.isValid(position) then
    error("Invalid position", 2)
  end

  local offset = Position.worldToChunkSpace(position)
  if offset.x < 0 or offset.x > 15 or offset.y < 0 or offset.y > 15 or offset.z < 0 or offset.z > 15 then
    error(("Position out of bounds: %d,%d,%d"):format(offset.x, offset.y, offset.z), 2)
  end

  return setmetatable({
    name = nil,
    walkable = false,
    position = Position.new(offset.x, offset.y, offset.z),
    world_position = Position.new(position.x, position.y, position.z),
  }, block_mt)
end



--- Creates a new chunk.
---@param position ccTweaked.Vector The position of the chunk in chunk coordinates.
---@return Doggo.Mapping.Chunk
function Chunk.new(position)
  expect(1, position, "table")
  if not Position.isValid(position) then
    error("Invalid position", 2)
  end

  return setmetatable({
    data = {},
    id = chunk_id(position)
  }, chunk_mt)
end



--- Inserts a block into the chunk.
---@param self Doggo.Mapping.Chunk
---@param position ccTweaked.Vector The position of the block in local chunk coordinates (0-15).
---@param walkable boolean Whether the block can be walked on.
---@param name string? The name of the block, e.g. "minecraft:stone". May be nil if the block is unknown.
function Chunk:addBlock(position, walkable, name)
  sentinel(self)
  expect(1, position, "table")
  expect(2, walkable, "boolean")
  expect(3, name, "string", "nil")

  if not Position.isValid(position) then
    error("Invalid position", 2)
  end

  local offset = Position.worldToChunkSpace(position)
  if offset.x < 0 or offset.x > 15 or offset.y < 0 or offset.y > 15 or offset.z < 0 or offset.z > 15 then
    error(("Position out of bounds: %d,%d,%d"):format(offset.x, offset.y, offset.z), 2)
  end

  if not self.data[offset.x] then
    self.data[offset.x] = {}
  end

  if not self.data[offset.x][offset.y] then
    self.data[offset.x][offset.y] = {}
  end

  self.data[offset.x][offset.y][offset.z] = setmetatable({
    name = name,
    walkable = walkable,
    position = Position.new(offset.x, offset.y, offset.z),
    world_position = Position.new(position.x, position.y, position.z),
  }, block_mt)
end



--- Gets a block from the chunk.
---@param self Doggo.Mapping.Chunk
---@param position ccTweaked.Vector The position of the block in local chunk coordinates (0-15).
---@return Doggo.Mapping.Chunk.BlockData block The block data, or nil if the block is not present.
function Chunk:getBlock(position)
  sentinel(self)
  expect(1, position, "table")

  if not Position.isValid(position) then
    error("Invalid position", 2)
  end

  local offset = Position.worldToChunkSpace(position)
  if offset.x < 0 or offset.x > 15 or offset.y < 0 or offset.y > 15 or offset.z < 0 or offset.z > 15 then
    error(("Position out of bounds: %d,%d,%d"):format(offset.x, offset.y, offset.z), 2)
  end

  if not self.data[offset.x] or not self.data[offset.x][offset.y] then
    return Chunk.unknownBlock(position)
  end

  return self.data[offset.x][offset.y][offset.z]
end



--- Removes a block from the chunk (makes it an unknown block).
---@param self Doggo.Mapping.Chunk
---@param position ccTweaked.Vector The position of the block.
function Chunk:removeBlock(position)
  sentinel(self)
  expect(1, position, "table")

  if not Position.isValid(position) then
    error("Invalid position", 2)
  end

  local offset = Position.worldToChunkSpace(position)
  if offset.x < 0 or offset.x > 15 or offset.y < 0 or offset.y > 15 or offset.z < 0 or offset.z > 15 then
    error(("Position out of bounds: %d,%d,%d"):format(offset.x, offset.y, offset.z), 2)
  end

  if not self.data[offset.x] or not self.data[offset.x][offset.y] then
    return
  end

  -- Remove the block
  self.data[offset.x][offset.y][offset.z] = nil

  -- Clean up empty tables
  if not next(self.data[offset.x][offset.y]) then
    self.data[offset.x][offset.y] = nil
  end
  if not next(self.data[offset.x]) then
    self.data[offset.x] = nil
  end
end



return Chunk