--- Waypoints for Doggo Mapping Library
---
--- Represents a point of interest, or a pathfinding target.
--- Waypoints can be linked together to form paths, and the turtle will try to pathfind through pathfinding target waypoints.

local pathfinding = require "doggo.pathfinding"

--- Waypoint type does not really matter, except if you want to use the waypoint as a pathfinding target.
--- Otherwise, set it to something that helps you identify the waypoint.
---@alias Doggo.Mapping.Map.Waypoint.Type
---| "path_target" A pathfinding target waypoint. The turtle will try to pathfind through these waypoints when given a destination, especially if linked with another waypoint.
---| "none" A generic waypoint with no special properties, default type.
---| string Any other string can be used as a custom type.

---@class Doggo.Mapping.Map.Waypoint.Link
---@field waypoint_1 Doggo.Mapping.Map.Waypoint The first waypoint in the link.
---@field waypoint_2 Doggo.Mapping.Map.Waypoint The second waypoint in the link.
---@field path Doggo.Pathfinding.Path The path between the two waypoints.

---@class Doggo.Mapping.Map.Waypoint
---@field display_name string The display name of the waypoint.
---@field type Doggo.Mapping.Map.Waypoint.Type The type of the waypoint.
---@field id string The ID of the waypoint. Defaults to `doggo:waypoint`.
---@field position ccTweaked.Vector The position of the waypoint in the map.
---@field link Doggo.Mapping.Map.Waypoint.Link? The waypoint link data, if any.
---@field package __SENTINEL table Sentinel value for detecting whether or not Waypoint methods are being used correctly.
local Waypoint = {
  __SENTINEL = {},
}

local waypoint_mt = {
  __index = Waypoint
}



local function sentinel(self)
  if type(self) ~= "table" or self.__SENTINEL ~= Waypoint.__SENTINEL then
    error("Use ':' to call Waypoint methods", 3)
  end
end



--- Creates a new waypoint.
---@param display_name string The display name of the waypoint.
---@param position ccTweaked.Vector The position of the waypoint in the map.
---@param type Doggo.Mapping.Map.Waypoint.Type? The type of the waypoint. Defaults to "none".
---@param id string? The ID of the waypoint. Defaults to "doggo:waypoint".
---@return Doggo.Mapping.Map.Waypoint waypoint The newly created waypoint.
function Waypoint.new(display_name, position, type, id)
  type = type or "none"
  id = id or "doggo:waypoint"

  local waypoint = setmetatable({
    display_name = display_name,
    position = position,
    type = type,
    id = id,
  }, waypoint_mt)

  return waypoint
end



--- Link this waypoint to another waypoint.


return Waypoint