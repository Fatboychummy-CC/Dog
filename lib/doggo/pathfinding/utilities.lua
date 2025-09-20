--- Pathfinding utility methods.

---@class Doggo.Pathfinding.Utilities
local Utilities = {}


--#region Localization Optimization
local table_remove = table.remove
--#endregion Localization Optimization



--- Creates a new FIFO queue.
---@return Doggo.Pathfinding.Utilities.FIFO
function Utilities.FIFO()
  ---@class Doggo.Pathfinding.Utilities.FIFO
  ---@field [integer] any The items in the queue.
  local queue = {
    n = 0
  }

  ---Enqueues a new item to the back of the queue.
  ---@param item any The item to enqueue.
  function queue:enqueue(item)
    self[self.n] = item
    self.n = self.n + 1
  end

  ---Dequeues an item from the front of the queue.
  ---@return any The dequeued item, or nil if the queue is empty.
  function queue:dequeue()
    if self.n == 0 then
      return nil
    end

    local item = table_remove(self, 1)
    self.n = self.n - 1
    return item
  end

  return queue
end



return Utilities