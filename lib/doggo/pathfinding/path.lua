--- Paths should hopefully be self-explanatory.

local Position = require "doggo.mapping.position"
local Movement = require "doggo.movement"
local Storage = require "doggo.pathfinding.storage"

---@alias Doggo.Pathfinding.Action.Type
---| "move" Move the turtle forward.
---| "turn" Turn the turtle to face a different direction.
---| "up" Move the turtle up.
---| "down" Move the turtle down.

---@class Doggo.Pathfinding.Action
---@field type Doggo.Pathfinding.Action.Type
---@field count integer? -- Number of times to repeat the action, for moves only.
---@field target_orientation Doggo.Movement.Orientation? -- For turns only.

---@class Doggo.Pathfinding.Path
---@field actions Doggo.Pathfinding.Action[] The list of actions in the path.
---@field start_position ccTweaked.Vector The starting position of the path.
---@field end_position ccTweaked.Vector The ending position of the path.
---@field start_orientation Doggo.Movement.Orientation The starting orientation of the path.
---@field package __SENTINEL table Sentinel value for detecting whether or not Path methods are being used correctly.
local Path = {
  __SENTINEL = {}
}

local path_mt = {
  __index = Path
}

local function sentinel(self)
  if type(self) ~= "table" or self.__SENTINEL ~= Path.__SENTINEL then
    error("Use ':' to call Path methods", 3)
  end
end



--- Creates a new path.
function Path.new()
  return setmetatable({
    actions = {},
    start_position = Position.new(0, 0, 0),
    end_position = Position.new(0, 0, 0),
    start_orientation = Movement.Orientation.NORTH,
  }, path_mt)
end



--- Unserializes a path from a binary string.
---@param serialized string The serialized path.
---@return Doggo.Pathfinding.Path? path The unserialized path, or nil if the string was invalid.
---@return string? err The error message, if any.
function Path.unserialize(serialized)
  expect(1, serialized, "string")
  local data, err = Storage.unserialize(serialized)
  if not data then
    return nil, err
  end

  return (setmetatable(data, path_mt))
end



--- Adds a forward movement action to the path.
---@param count integer The number of blocks to move forward.
function Path:forward(count)
  sentinel(self)
  expect(1, count, "number")

  if count < 1 or count % 1 ~= 0 then
    error("Count must be a positive integer", 2)
  end

  table.insert(self.actions, {
    type = "move",
    count = count,
  })
end



--- Adds a turn action to the path.
---@param target_orientation Doggo.Movement.Orientation The orientation to turn to.
function Path:turn(target_orientation)
  sentinel(self)
  expect(1, target_orientation, "Doggo.Movement.Orientation")

  table.insert(self.actions, {
    type = "turn",
    target_orientation = target_orientation,
  })
end



--- Adds an upward movement action to the path.
---@param count integer The number of blocks to move up.
function Path:up(count)
  sentinel(self)
  expect(1, count, "number")

  if count < 1 or count % 1 ~= 0 then
    error("Count must be a positive integer", 2)
  end

  table.insert(self.actions, {
    type = "up",
    count = count,
  })
end



--- Adds a downward movement action to the path.
---@param count integer The number of blocks to move down.
function Path:down(count)
  sentinel(self)
  expect(1, count, "number")

  if count < 1 or count % 1 ~= 0 then
    error("Count must be a positive integer", 2)
  end

  table.insert(self.actions, {
    type = "down",
    count = count,
  })
end



--- Simulates running the path to see if the end position is correct.
function Path:simulate()
  sentinel(self)

  -- ...
end



--- Serializes the path to a binary string.
---@return string serialized The serialized path.
function Path:serialize()
  sentinel(self)
  return Storage.serialize(self)
end



return Path