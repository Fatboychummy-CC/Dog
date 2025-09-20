--- Additional vector methods for use with positions.

local expect = require "cc.expect".expect

---@class Doggo.Mapping.Position
local Position = {}



--- Creates a new position.
---@param x integer The x coordinate.
---@param y integer The y coordinate.
---@param z integer The z coordinate.
---@return ccTweaked.Vector position The new position.
function Position.new(x, y, z)
  expect(1, x, "number")
  expect(2, y, "number")
  expect(3, z, "number")

  if x % 1 ~= 0 or y % 1 ~= 0 or z % 1 ~= 0 then
    error("Coordinates must be integers", 2)
  end

  return vector.new(x, y, z)
end



--- Verifies if a table is a valid position.
---@param tbl table The table to verify.
---@return boolean is_valid Whether the table is a valid position.
function Position.isValid(tbl)
  return type(tbl) == "table" and
         type(tbl.x) == "number" and
         type(tbl.y) == "number" and
         type(tbl.z) == "number" and
         tbl.x % 1 == 0 and
         tbl.y % 1 == 0 and
         tbl.z % 1 == 0
end



--- Converts a world position to chunk space (0-15).
---@param position ccTweaked.Vector The world position.
---@return ccTweaked.Vector chunk_space_position The position in chunk space.
function Position.worldToChunkSpace(position)
  expect(1, position, "table")
  if not Position.isValid(position) then
    error("Invalid position", 2)
  end

  return vector.new(position.x % 16, position.y % 16, position.z % 16)
end



--- Converts a world position to chunk coordinates.
---@param position ccTweaked.Vector The world position.
---@return ccTweaked.Vector chunk_coordinates The position in chunk coordinates.
function Position.worldToChunkCoordinates(position)
  expect(1, position, "table")
  if not Position.isValid(position) then
    error("Invalid position", 2)
  end

  return vector.new(
    math.floor(position.x / 16),
    math.floor(position.y / 16),
    math.floor(position.z / 16)
  )
end



--- Converts a chunk coordinate to its 0,0,0 world position.
---@param position ccTweaked.Vector The chunk coordinates.
---@return ccTweaked.Vector world_position The world position of the chunk's 0,0,0 corner.
function Position.chunkToWorldPosition(position)
  expect(1, position, "table")
  if not Position.isValid(position) then
    error("Invalid position", 2)
  end

  return vector.new(
    position.x * 16,
    position.y * 16,
    position.z * 16
  )
end



return Position