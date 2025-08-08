--- Doggo Movement: Keeps track of the turtle's position and orientation, and provides higher level movement functions.

---@class Doggo.Movement.State
---@field position ccTweaked.Vector The current position of the turtle.
---@field orientation Doggo.Movement.Orientation The current orientation of the turtle.
---@field last_fuel integer|"unlimited" The last amount of fuel the turtle had. Used for recovering from errors, if partway through a movement.
---@field last_action Doggo.Movement.Actions The last action the turtle performed. Used for recovering from errors, if partway through a movement.

---@alias Doggo.Movement.Actions
---| "none" # No action has been performed yet.
---| "forward" # The turtle moved forward.
---| "back" # The turtle moved back.
---| "up" # The turtle moved up.
---| "down" # The turtle moved down.
---| "turn_left" # The turtle turned left.
---| "turn_right" # The turtle turned right.
---| "done" # The turtle has finished its current action.

local data_dir = require "filesystem":programPath():at("data")
local state_file = data_dir:file("doggo_movement_state.lson")

---@class Doggo.Movement
---@field state Doggo.Movement.State The current movement state of the turtle.
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
  }
}



--- Saves the current movement state to a file.
function Movement.save()
  state_file:serialize(Movement.state, {compact=true})
end



--- Loads the movement state from a file, if it exists.
function Movement.load()
  local state = state_file:deserialize(Movement.state)

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

  local success, reason = func()
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



return Movement