---@generic T
---@class QIT<T> : {[integer]:T, n:integer}
---@field Insert fun(self:QIT, value:any)
---@field Push fun(self:QIT, value:any)
---@field Remove fun(self:QIT): any
---@field Drop fun(self:QIT): any
---@field Take fun(self:QIT, i:integer): any
---@field Clean fun(self:QIT):QIT

--- Create a new QIT.
---@generic T
---@return QIT<T>
return function()
  ---@generic T
  ---@type QIT<T>
  return {
    n = 0,

    --- Insert a value into the QIT at the end.
    ---@param self QIT
    ---@param value any The value to be inserted.
    Insert = function(self, value)
      self.n = self.n + 1
      self[self.n] = value
    end,

    --- Insert a value into the QIT at the beginning.
    ---@param self QIT
    ---@param value any The value to be inserted.
    Push = function(self, value)
      table.insert(self, 1, value)
      self.n = self.n + 1
    end,

    --- Remove a value from the end of the QIT.
    ---@param self QIT
    ---@return any value The value removed.
    Remove = function(self)
      if self.n > 0 then
        local value = self[self.n]
        self[self.n] = nil
        self.n = self.n - 1

        return value
      end
    end,

    --- Remove a value from the beginning of the QIT.
    ---@param self QIT
    ---@return any value The value removed.
    Drop = function(self)
      local value = table.remove(self, 1)

      if value ~= nil then
        self.n = self.n - 1
      end

      return value
    end,

    --- Take a value from the QIT at a specific position.
    ---@param self QIT
    ---@param i integer The position to take an item from.
    Take = function(self, i)
      if self.n >= i then
        local value = table.remove(self, i)
        self.n = self.n - 1
      end
    end,

    --- Remove all extra fields so this is just a normal array.
    ---@param self QIT
    ---@return self self
    Clean = function(self)
      self.Insert = nil
      self.Push = nil
      self.Remove = nil
      self.Drop = nil
      self.Clean = nil

      return self
    end
  }
end
