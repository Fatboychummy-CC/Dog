--- Pathfinding module for Doggo

local expect = require "cc.expect".expect

local Movement = require "doggo.movement"
local Mapping = require "doggo.mapping"

---@class Doggo.Pathfinding
local Pathfinding = {}



--- Attempts to create a path to a specified position.
---@param x integer The X coordinate of the position to move to.
---@param y integer The Y coordinate of the position to move to.
---@param z integer The Z coordinate of the position to move to.
---@param map Doggo.Mapping.Map The map to use for pathfinding.
---@param depth_limit integer? The maximum depth to search for a path (Default 100)
---@return Doggo.Pathfinding.Path? path The found path, or nil if no path was found.
---@return ccTweaked.Vector? closest_position The closest position found during pathfinding, if pathing failed.
---@return Doggo.Pathfinding.Path? closest_path The path to the closest position found during pathfinding, if pathing failed.
function Pathfinding.pathfind(x, y, z, map, depth_limit)
  expect(1, x, "number")
  expect(2, y, "number")
  expect(3, z, "number")
  expect(4, map, "table")
  expect(5, depth_limit, "number", "nil")
  depth_limit = depth_limit or 100

  local start = Movement.state.position
  local goal = vector.new(x, y, z)

  local open_set = FIFO()

  ---@TODO Rest of this once I figure out how the maps will look.
end



return Pathfinding