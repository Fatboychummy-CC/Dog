--- A simple argument parsing library for ComputerCraft.

---@class argparse-argument
---@field name string The name of the argument.
---@field description string The description of the argument.
---@field default any The default value of the argument.

---@class argparse-flag : argparse-argument
---@field short string? The short name of the flag.

---@class argparse-option : argparse-argument
---@field short string? The short name of the option.

---@class argparse-parsed
---@field options table<string, any> The options passed to the program.
---@field flags table<string, boolean> The flags passed to the program.
---@field arguments table<string, any> The arguments passed to the program.

---@class arg_pattern
---@field pattern string The pattern to match against.
---@field func fun(flag_info: table<string, argparse-flag>, parsed: argparse-parsed, ...: string) The function to run when the pattern matches.

--[[
  Setup should look like so:
  parser = argparse.new_parser("My Program", "This program does something cool.")
  parser.add_flag("h", "help", "Print this help message.") where f is the short flag, help is the long flag
  parser.add_option("f", "file", "The file to read from.", "file.txt") where "file.txt" is the default value
  parser.add_argument("name", "The name of the person to greet.", true) these should be added in order, with boolean required.
  parser.add_argument("age", "The age of the person to greet.", false) example of a non-required argument
  parser.add_argument("greeting", "The greeting to use.", false, "Hello") example of a non-required argument with a default value
  
  parsed = parser.parse(args) where args is the table of arguments passed to the program.
  If the user inputs invalid arguments, it is up to YOU to handle that.
  
  Assuming the arguments passed were:
  {
    "-h",
    "--file=file.txt",
    "Bob",
    "20",
    "Hello"
  }
  The output would look like
  parsed = {
    options = {
      file = "file.txt"
    },
    flags = {
      help = true
    },
    arguments = {
      name = "Bob",
      age = 20,
      greeting = "Hello"
    }
  }
]]

--- The patterns and functions used to parse arguments. These are used in order.
---@type table<number, arg_pattern>
local arg_patterns = {
  {
    pattern = "^%-%-(%w+)%=(.+)$",
    func = function(flag_info, parsed, name, value)
      parsed.options[name] = value
    end
  },
  {
    pattern = "^%-%-(%w+)$",
    func = function(flag_info, parsed, name)
      parsed.flags[name] = true
    end
  },
  {
    pattern = "^%-(%w+)$",
    func = function(flag_info, parsed, name)
      for i = 1, #name do
        -- find what flags this short flag refers to
        for _, flag in pairs(flag_info) do
          if flag.short == name:sub(i, i) then
            parsed.flags[flag.name] = true
            break
          end
        end
      end
    end
  },
  {
    pattern = "^(.+)$",
    func = function(flag_info, parsed, value)
      table.insert(parsed.arguments, value)
    end
  }
}

local expect = require "cc.expect".expect

---@class argparse
local argparse = {}

--- Create a new parser.
---@param program_name string The name of the program.
---@param program_description string The description of the program.
---@return argparse-parser
function argparse.new_parser(program_name, program_description)
  expect(1, program_name, "string")
  expect(2, program_description, "string")

  ---@class argparse-parser
  local parser = {
    program_name = program_name,
    program_description = program_description,
    flags = {}, ---@type table<string, argparse-flag>
    options = {}, ---@type table<string, argparse-option>
    arguments = {} ---@type table<string, argparse-argument>
  }

  --- Add a flag to the parser.
  ---@param short string? The short name of the flag.
  ---@param long string The long name of the flag.
  ---@param description string The description of the flag.
  function parser.add_flag(short, long, description)
    expect(1, short, "string", "nil")
    expect(2, long, "string")
    expect(3, description, "string")

    parser.flags[long] = {
      name = long,
      short = short,
      description = description
    }
  end

  --- Add an option to the parser.
  ---@param long string The long name of the option.
  ---@param description string The description of the option.
  ---@param default any The default value of the option.
  function parser.add_option(long, description, default)
    expect(1, long, "string")
    expect(2, description, "string")

    parser.options[long] = {
      name = long,
      description = description,
      default = default
    }
  end

  --- Add an argument to the parser.
  ---@param name string The name of the argument.
  ---@param description string The description of the argument.
  ---@param required boolean Whether or not the argument is required.
  ---@param default any The default value of the argument.
  function parser.add_argument(name, description, required, default)
    expect(1, name, "string")
    expect(2, description, "string")
    expect(3, required, "boolean")

    if required and type(default) ~= "nil" then
      error("Required arguments cannot have a default value.", 2)
    end

    table.insert(parser.arguments, {
      name = name,
      description = description,
      required = required,
      default = default
    })
  end

  --- Parse the arguments passed to the program.
  ---@param args table The arguments passed to the program.
  ---@return argparse-parsed
  function parser.parse(args)
    ---@type argparse-parsed
    local output = {
      options = {},
      flags = {},
      arguments = {}
    }

    for _, arg in ipairs(args) do
      for _, pattern in ipairs(arg_patterns) do
        local matched = table.pack(arg:match(pattern.pattern))
        if matched.n > 0 and matched[1] ~= nil then
          pattern.func(parser.flags, output, table.unpack(matched, 1, matched.n))
          break
        end
      end
    end

    return output
  end

  --- Generate a usage string given the current parser configuration.
  ---@return string
  function parser.usage()
    local output = parser.program_name .. " - " .. parser.program_description .. "\n\n"

    output = output .. "Usage: " .. parser.program_name .. " [options]"

    if next(parser.arguments) then
      output = output .. " "

      for _, argument in ipairs(parser.arguments) do
        if argument.required then
          output = output .. "<" .. argument.name .. "> "
        else
          output = output .. "[" .. argument.name .. "] "
        end
      end
    end

    output = output .. "\n\n"

    if next(parser.arguments) then
      output = output .. "Arguments:\n"

      for _, argument in ipairs(parser.arguments) do
        output = output .. "  " .. argument.name .. ": " .. argument.description

        if argument.default then
          output = output .. " Default: " .. tostring(argument.default)
        end

        output = output .. "\n"
      end

      output = output .. "\n"
    end

    if next(parser.options) then
      output = output .. "Options:\n"

      for _, option in pairs(parser.options) do
        output = output .. "  "

        if option.short then
          output = output .. "-" .. option.short .. ", "
        else
          output = output .. "    "
        end

        output = output .. "--" .. option.name .. ": " .. option.description

        if option.default then
          output = output .. " Default: " .. tostring(option.default)
        end

        output = output .. "\n"
      end

      output = output .. "\n"
    end

    if next(parser.flags) then
      output = output .. "Flags:\n"

      for _, flag in pairs(parser.flags) do
        output = output .. "  "

        if flag.short then
          output = output .. "-" .. flag.short .. ", "
        else
          output = output .. "    "
        end

        output = output .. "--" .. flag.name .. ": " .. flag.description .. "\n"
      end

      output = output .. "\n"
    end

    return output
  end

  return parser
end

return argparse