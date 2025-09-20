--- Doggo Movement: Keeps track of the turtle's position and orientation, and provides higher level movement functions.

---@class Doggo.Movement.State
---@field position ccTweaked.Vector The current position of the turtle.
---@field orientation Doggo.Movement.Orientation The current orientation of the turtle.
---@field last_fuel integer|"unlimited" The last amount of fuel the turtle had. Used for recovering from errors, if partway through a movement.
---@field last_action Doggo.Movement.Actions The last action the turtle performed. Used for recovering from errors, if partway through a movement.

---@class Doggo.Movement.Parameters
---@field fail_type Doggo.Movement.FailTypes What to do when a movement action fails.
---@field fail_action function|nil A user-defined action to call when a movement action fails and `fail_type` is "action".
---@field max_retries integer The maximum number of times to retry a movement action before giving up. Only applies if `fail_type` is "retry" or "action".
---@field retry_delay integer The number of seconds to wait between retries. Only applies if `fail_type` is "retry" or "action".

---@alias Doggo.Movement.FailTypes
---| "stop" # Stop movement on failure.
---| "retry" # Retry the action until it succeeds.
---| "ignore" # Ignore the failure and continue.
---| "action" # Call a user-defined action on failure.

---@alias Doggo.Movement.Actions
---| "none" # No action has been performed yet.
---| "forward" # The turtle moved forward.
---| "back" # The turtle moved back.
---| "up" # The turtle moved up.
---| "down" # The turtle moved down.
---| "turn_left" # The turtle turned left.
---| "turn_right" # The turtle turned right.
---| "done" # The turtle has finished its current action.

---@alias Doggo.Movement.AxisOrders
---| "xyz"
---| "yxz"
---| "yzx"
---| "xzy"
---| "zyx"
---| "zxy"

local expect = require "cc.expect".expect

local data_dir = require "filesystem":programPath():at("data")
local state_file = data_dir:file("doggo_movement_state.lson")

---@class Doggo.Movement
---@field state Doggo.Movement.State The current movement state of the turtle.
---@field parameters Doggo.Movement.Parameters The movement parameters.
local Movement = {
  ---@enum Doggo.Movement.Orientation
  Orientation = {
    NORTH = 0,
    EAST = 1,
    SOUTH = 2,
    WEST = 3,

    NZ = 0, -- Negative Z direction (North)
    PX = 1, -- Positive X direction (East)
    PZ = 2, -- Positive Z direction (South)
    NX = 3, -- Negative X direction (West)
  },

  state = {
    position = vector.new(0, 0, 0),
    orientation = 0, -- Facing North by default
    last_fuel = turtle.getFuelLevel(),
    last_action = "none",
  },
  parameters = {
    fail_type = "retry",
    fail_action = nil,
    max_retries = 5,
    retry_delay = 1,
  },
}



--- Saves the current movement state to a file.
function Movement.save()
  state_file:serialize(Movement.state, {compact=true})
end



--- Loads the movement state from a file, if it exists.
function Movement.load()
  local state = state_file:unserialize(Movement.state)

  ---@TODO Verify the state.
  ---@TODO Recover state based on fuel level.

  Movement.state = state
end



--- Offsets the turtle's position by 1 based on its facing.
---@param back boolean? If true, offsets the position as if the turtle moved back.
---@return ccTweaked.Vector new_position A vector representing the new position of the turtle.
function Movement.getOffset(back)
  local orientation = Movement.state.orientation
  if orientation == Movement.Orientation.NZ then
    return Movement.state.position + vector.new(0, 0, back and 1 or -1)
  elseif orientation == Movement.Orientation.PX then
    return Movement.state.position + vector.new(back and -1 or 1, 0, 0)
  elseif orientation == Movement.Orientation.PZ then
    return Movement.state.position + vector.new(0, 0, back and -1 or 1)
  elseif orientation == Movement.Orientation.NX then
    return Movement.state.position + vector.new(back and 1 or -1, 0, 0)
  end

  error("Turtle has invalid orientation: " .. tostring(orientation), 2)
end



--- Contains the basic turtle movement "primitives", but overridden to update/save the movement state.
---@class Doggo.Movement.Turtle
Movement.turtle = {}



--- Performs a movement action, updating the turtle's position and orientation.
---@param action Doggo.Movement.Actions The action to perform.
---@param func function The function to call for the action (e.g., turtle.forward, turtle.turnLeft).
---@param callback_success function|nil A callback function to call if the action is successful.
---@return boolean success True if the action was successful, false otherwise.
---@return string? reason If the action failed, a reason why it failed.
local function do_movement(action, func, callback_success)
  -- Prepare for movement.
  Movement.state.last_action = action
  Movement.state.last_fuel = turtle.getFuelLevel()
  Movement.save()

  local success, reason
  for _ = 1, Movement.parameters.max_retries do
    success, reason = func()
    if success or Movement.parameters.fail_type == "ignore" then
      break
    end
    if Movement.parameters.fail_type == "stop" then
      error("Movement action failed: " .. tostring(reason), 2)
    end
    if Movement.parameters.fail_type == "action" and Movement.parameters.fail_action then
      Movement.parameters.fail_action(action, reason)
    end

    -- If we reach here, fail type is "retry" or "action".
    sleep(Movement.parameters.retry_delay)
  end

  if not success then
    Movement.state.last_action = "done"
    Movement.save()
    return false, reason
  end

  Movement.state.last_action = "done"
  Movement.state.last_fuel = turtle.getFuelLevel()

  if callback_success then
    callback_success()
  end

  Movement.save()

  return true
end



--- Moves the turtle forward once, incrementing the position based on the current orientation.
---@return boolean success True if the turtle moved successfully, false otherwise.
---@return string? reason If the movement failed, a reason why it failed.
function Movement.turtle.forward()
  return do_movement("forward", turtle.forward, function()
    -- Update the position based on the current orientation.
    Movement.state.position = Movement.getOffset()
  end)
end



--- Moves the turtle back once, decrementing the position based on the current orientation.
---@return boolean success True if the turtle moved successfully, false otherwise.
---@return string? reason If the movement failed, a reason why it failed.
function Movement.turtle.back()
  return do_movement("back", turtle.back, function()
    -- Update the position based on the current orientation.
    Movement.state.position = Movement.getOffset(true)
  end)
end



--- Moves the turtle up once, incrementing the Y position.
---@return boolean success True if the turtle moved successfully, false otherwise.
---@return string? reason If the movement failed, a reason why it failed.
function Movement.turtle.up()
  return do_movement("up", turtle.up, function()
    -- Increment the Y position.
    Movement.state.position = Movement.state.position + vector.new(0, 1, 0)
  end)
end



--- Moves the turtle down once, decrementing the Y position.
---@return boolean success True if the turtle moved successfully, false otherwise.
---@return string? reason If the movement failed, a reason why it failed.
function Movement.turtle.down()
  return do_movement("down", turtle.down, function()
    -- Decrement the Y position.
    Movement.state.position = Movement.state.position + vector.new(0, -1, 0)
  end)
end



--- Turns the turtle left, updating its orientation.
---@return boolean success True if the turtle turned successfully, false otherwise.
---@return string? reason If the turn failed, a reason why it failed.
function Movement.turtle.turnLeft()
  return do_movement("turn_left", turtle.turnLeft, function()
    Movement.state.orientation = (Movement.state.orientation - 1) % 4
  end)
end



--- Turns the turtle right, updating its orientation.
---@return boolean success True if the turtle turned successfully, false otherwise.
---@return string? reason If the turn failed, a reason why it failed.
function Movement.turtle.turnRight()
  return do_movement("turn_right", turtle.turnRight, function()
    Movement.state.orientation = (Movement.state.orientation + 1) % 4
  end)
end



--- Turns the turtle to face a specific orientation.
---@param orientation Doggo.Movement.Orientation The orientation to face.
function Movement.face(orientation)
  expect(1, orientation, "number")

  if orientation < 0 or orientation > 3 or orientation % 1 ~= 0 then
    error("Invalid orientation: " .. tostring(orientation), 2)
  end

  if Movement.state.orientation == orientation then
    return -- Already facing the correct direction.
  end

  if (orientation + 1) % 4 == Movement.state.orientation then
    -- Quickest way is to turn right once.
    Movement.turtle.turnRight()
    return
  end

  -- Otherwise, just turn left until we face the correct direction.
  while Movement.state.orientation ~= orientation do
    Movement.turtle.turnLeft()
  end
end



local function align_x(target_x)
  if Movement.state.position.x == target_x then
    return
  end

  if Movement.state.position.x < target_x then
    -- Need to move +X
    Movement.face(Movement.Orientation.PX)
  else
    -- Need to move -X
    Movement.face(Movement.Orientation.NX)
  end

  while Movement.state.position.x ~= target_x do
    Movement.turtle.forward()
  end
end



local function align_y(target_y)
  if Movement.state.position.y == target_y then
    return
  end

  while Movement.state.position.y < target_y do
    Movement.turtle.up()
  end

  while Movement.state.position.y > target_y do
    Movement.turtle.down()
  end
end



local function align_z(target_z)
  if Movement.state.position.z == target_z then
    return
  end

  if Movement.state.position.z < target_z then
    -- Need to move +Z (South)
    Movement.face(Movement.Orientation.PZ)
  else
    -- Need to move -Z (North)
    Movement.face(Movement.Orientation.NZ)
  end

  while Movement.state.position.z ~= target_z do
    Movement.turtle.forward()
  end
end



--- Moves the turtle to a specified position.
---@param x integer The X coordinate of the position to move to.
---@param y integer The Y coordinate of the position to move to.
---@param z integer The Z coordinate of the position to move to.
---@param axis_order Doggo.Movement.AxisOrders? The order in which to align axis, default `xyz`.
function Movement.moveTo(x, y, z, axis_order)
  expect(1, x, "number")
  expect(2, y, "number")
  expect(3, z, "number")
  expect(4, axis_order, "string", "nil")
  axis_order = axis_order or "xyz"

  if axis_order then
    if #axis_order ~= 3 then
      error("Bad argument #4 to moveTo: Expected a string of length 3, got " .. #axis_order, 2)
    end

    if not axis_order:match("^[xyz]+$") then
      error("Bad argument #4 to moveTo: Expected a string containing only 'x', 'y', and 'z', got " .. axis_order, 2)
    end

    local axes = {}
    for _, axis in axis_order:gmatch(".") do
      if not axes[axis] then
        axes[axis] = true
      else
        error("Bad argument #4 to moveTo: Duplicate axis '" .. axis .. "' in order " .. axis_order, 2)
      end
    end
  end

  for _, axis in axis_order:gmatch(".") do
    if axis == "x" then
      align_x(x)
    elseif axis == "y" then
      align_y(y)
    elseif axis == "z" then
      align_z(z)
    else
      error("Invalid axis in order: " .. axis, 2)
    end
  end
end



--- Moves the turtle n times in the specified direction.
---@param n integer The number of blocks to move.
---@param direction Doggo.Movement.Orientation? The direction to move in. If nil, moves in the current facing direction.
function Movement.move(n, direction)
  expect(1, n, "number")
  expect(2, direction, "number", "nil")

  direction = direction or Movement.state.orientation

  Movement.face(direction)
  for i = 1, n do
    Movement.turtle.forward()
  end
end



--- Follows a path created by `Movement.pathfind`.
--- @param path Doggo.Pathfinding.Path The path to follow.
function Movement.followPath(path)
  expect(1, path, "table")

  ---@TODO Implement this after we determine what a path will look like.
end

return Movement