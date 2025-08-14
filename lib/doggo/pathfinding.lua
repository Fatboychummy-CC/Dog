--- Pathfinding module for Doggo

local expect = require "cc.expect".expect

local Movement = require "doggo.movement"
local Mapping = require "doggo.mapping"

---@class Doggo.Pathfinding.Path
---@field nodes Doggo.Pathfinding.PathNode[] The nodes in the path, in order, from start to finish.
---@field length integer The length of the path, in nodes.

---@class Doggo.Pathfinding.PathNode
---@field position ccTweaked.Vector The position of the node.
---@field parent Doggo.Pathfinding.PathNode? The parent node, or nil if this is the root node.

---@class Doggo.Pathfinding
local Pathfinding = {}



--- Creates a new FIFO queue.
---@return Doggo.Pathfinding.Queues.FIFO
local function FIFO()
  ---@class Doggo.Pathfinding.Queues.FIFO
  local queue = {
    head = 1,
    tail = 1,
    data = {}
  }

  ---Enqueues a new item to the back of the queue.
  ---@param item any The item to enqueue.
  function queue:enqueue(item)
    self.data[self.tail] = item
    self.tail = self.tail + 1
  end

  ---Dequeues an item from the front of the queue.
  ---@return any The dequeued item, or nil if the queue is empty.
  function queue:dequeue()
    if self.head >= self.tail then
      return nil
    end

    local item = self.data[self.head]
    self.data[self.head] = nil
    self.head = self.head + 1
    return item
  end

  ---Returns the number of items in the queue.
  ---@return integer The number of items in the queue.
  function queue:size()
    return self.tail - self.head
  end

  return queue
end



--- Attempts to create a path to a specified position.
---@param x integer The X coordinate of the position to move to.
---@param y integer The Y coordinate of the position to move to.
---@param z integer The Z coordinate of the position to move to.
---@param map Doggo.Mapping.CollisionMap The map to use for pathfinding.
---@param depth_limit integer? The maximum depth to search for a path (Default 100)
---@return Doggo.Pathfinding.Path? path The found path, or nil if no path was found.
---@return ccTweaked.Vector? closest_position The closest position found during pathfinding, if pathing failed.
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