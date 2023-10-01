--- Dog is a program run on mining turtles which is used to find ores and mine
--- them. Unlike quarry programs, this program digs in a straight line down and
--- uses either plethora's block scanner or advanced peripheral's geoscanner to
--- detect where ores are along its path and mine to them.

-- Import libraries
local aid = require("lib.turtle_aid")
local file_helper = require("lib.file_helper")
local logging = require("lib.logging")
local simple_argparse = require("lib.simple_argparse")

-- Constants
local LOG_FILE = fs.combine(file_helper.working_directory, "dog.log")

-- Variables
local args = {...}
local max_depth = 512
local log_level = logging.LOG_LEVEL.INFO
local log_window = term.current()

local parser = simple_argparse.new_parser("dog", "Dog is a program run on mining turtles which is used to find ores and mine them. Unlike quarry programs, this program digs in a straight line down and uses either plethora's block scanner or advanced peripheral's geoscanner to detect where ores are along its path and mine to them.")
parser.add_option("--depth", "The maximum depth to dig to.", max_depth)
parser.add_option("--log-level", "The log level to use.", "INFO")

local parsed = parser.parse(table.pack(...))

if parsed.options["log-level"] then
  log_level = logging.LOG_LEVEL[parsed.options["log-level"]:upper()]
end
if parsed.options["depth"] then
  ---@diagnostic disable-next-line max_depth is tested right after this
  max_depth = tonumber(parsed.options["depth"])
  if not max_depth then
    error("Max depth must be a number.", 0)
  end
end

logging.set_level(log_level)