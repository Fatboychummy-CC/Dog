local file_helper = require "file_helper"

---@alias turtle_facing
---| `0` # North (negative Z direction)
---| `1` # East (positive X direction)
---| `2` # South (positive Z direction)
---| `3` # West (negative X direction)

---@alias movement
---| "forward"
---| "back"
---| "left"
---| "right"
---| "up"
---| "down"
---| "done"

local DIR = fs.getDir(shell.getRunningProgram())
local POSITION_CACHE = fs.combine(DIR, "position.dat")


---@type {[turtle_facing]:vector}
local facings = {
  [0] = vector.new(0, 0, -1), -- negative Z direction, north
  vector.new(1, 0, 0), -- positive X direction, east
  vector.new(0, 0, 1), -- positive Z direction, south
  vector.new(-1, 0, 0) -- negative X direction, west
}

local tracker = {
  ---@type vector
  position = vector.new(),

  ---@type turtle_facing
  turtle_facing = 0,

  ---@type integer
  fuel = turtle.getFuelLevel()
}

--- Write movement information to the position cache file.
---@param movement movement The movement to save.
local function write_movement(movement)
  file_helper.serialize(POSITION_CACHE, { movement, tracker.position, tracker.facing, tracker.fuel }, true)
end

--- Move forward, updating the turtle's position information.
---@return boolean success
function tracker.go_forward()
  write_movement("forward")
  local success = turtle.forward()

  if success then
    tracker.position = tracker.position + facings[tracker.facing]
  end

  write_movement("done")
  return success
end

--- Move back, updating the turtle's position information.
---@return boolean success
function tracker.go_back()
  write_movement("back")
  local success = turtle.back()

  if success then
    tracker.position = tracker.position + facings[(tracker.facing + 2) % 4]
  end

  write_movement("done")
  return success
end

--- Move up, updating the turtle's position information.
---@return boolean success
function tracker.go_up()
  write_movement("up")
  local success = turtle.up()

  if success then
    tracker.position = tracker.position + vector.new(0, 1, 0)
  end

  write_movement("done")
  return success
end

--- Move down, updating the turtle's position information.
---@return boolean success
function tracker.go_down()
  write_movement("down")
  local success = turtle.down()

  if success then
    tracker.position = tracker.position + vector.new(0, -1, 0)
  end

  write_movement("done")
  return success
end

--- Turn left, updating the turtle's position information.
---@return boolean success
function tracker.turn_left()
  write_movement("left") -- turns are to be assumed successful on reboot
  local success = turtle.turnLeft()

  if success then
    tracker.facing = (tracker.facing - 1) % 4
  end

  write_movement("done")
  return success
end

--- Turn right, updating the turtle's position information.
---@return boolean success
function tracker.turn_right()
  write_movement("right") -- turns are to be assumed successful on reboot
  local success = turtle.turnRight()

  if success then
    tracker.facing = (tracker.facing + 1) % 4
  end

  write_movement("done")
  return success
end

return tracker
