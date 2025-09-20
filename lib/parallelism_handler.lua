--- Parallelism handler: parallelizes certain peripheral calls.
local function new_parallelism_handler()
  ---@class ParallelismHandler
  local parallelism_handler = {
    tasks = {},
    limit = 128,
    n = 0
  }

  --- Add a task to the parallelism handler.
  --- This method respects the task limit, and will execute the tasks if the limit is reached.
  ---@param task function The task to add.
  ---@param ... any The arguments to pass to the task
  function parallelism_handler:add_task(task, ...)
    self.n = self.n + 1
    self.tasks[self.n] = {
      task = task,
      args = table.pack(...),
    }

    if self.n >= self.limit then
      self:execute()
    end
  end


  --- Add a task to the parallelism handler, does not execute if the limit is reached.
  ---@param task function The task to add.
  ---@param ... any The arguments to pass to the task
  function parallelism_handler:add_task_no_execute(task, ...)
    self.n = self.n + 1
    self.tasks[self.n] = {
      task = task,
      args = table.pack(...),
    }
  end


  --- Execute all tasks in parallel.
  function parallelism_handler:execute()
    local _tasks = {}
    local _results = {}
    for i, task in ipairs(self.tasks) do
      _tasks[i] = function()
        _results[i] = task.task(table.unpack(task.args, 1, task.args.n))
      end
    end

    parallel.waitForAll(table.unpack(_tasks))
    self.tasks = {}
    self.n = 0
    return _results
  end

  return parallelism_handler
end

return new_parallelism_handler