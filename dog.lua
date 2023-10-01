--- Dog is a program run on mining turtles which is used to find ores and mine
--- them. Unlike quarry programs, this program digs in a straight line down and
--- uses either plethora's block scanner or advanced peripheral's geoscanner to
--- detect where ores are along its path and mine to them.

local expect = require "cc.expect".expect

-- Import libraries
local aid = require("lib.turtle_aid")
local file_helper = require("lib.file_helper")
local logging = require("lib.logging")
local simple_argparse = require("lib.simple_argparse")

-- Constants
local LOG_FILE = fs.combine(file_helper.working_directory, "data/dog.log") -- Logger does not use file_helper, so we need to manually tell it to use this directory.
local STATE_FILE = "data/dog.state"

-- Variables
local max_depth = 512
local log_level = logging.LOG_LEVEL.INFO
local log_window = term.current()
local geoscanner_range = 8
local scan = nil ---@type fun():table<integer, table> Set during initialization.

local parser = simple_argparse.new_parser("dog", "Dog is a program run on mining turtles which is used to find ores and mine them. Unlike quarry programs, this program digs in a straight line down and uses either plethora's block scanner or advanced peripheral's geoscanner to detect where ores are along its path and mine to them.")
parser.add_option("depth", "The maximum depth to dig to.", max_depth)
parser.add_option("loglevel", "The log level to use.", "INFO")
parser.add_option("georange", "The range to use for the geoscanner, if using Advanced Peripherals.", 8)
parser.add_flag("h", "help", "Show this help message and exit.")
parser.add_flag("f", "fuel", "Attempt to refuel as needed from ores mined.")
parser.add_argument("max_offset", "The maximum offset from the centerpoint to mine to.", false,  8)

local parsed = parser.parse(table.pack(...))

if parsed.flags.help then
  local _, h = term.getSize()
  textutils.pagedPrint(parser.usage())
  return
end

if parsed.options.loglevel then
  log_level = logging.LOG_LEVEL[parsed.options.loglevel:upper()]
  if not log_level then
    error("Invalid log level.", 0)
  end
end
if parsed.options.depth then
  ---@diagnostic disable-next-line max_depth is tested right after this
  max_depth = tonumber(parsed.options.depth)
  if not max_depth then
    error("Max depth must be a number.", 0)
  end
end
if parsed.options.georange then
  ---@diagnostic disable-next-line geoscanner_range is tested right after this
  geoscanner_range = tonumber(parsed.options.georange)
  if not geoscanner_range then
    error("Geo range must be a number.", 0)
  end
end

logging.set_level(log_level)
logging.set_window(log_window)

-- Initial setup
do
  -- Stage 1: Check for scanner and pickaxe, equip them if not already done.
  local setup_context = logging.create_context("Setup")
  setup_context.info("Checking for pickaxe and scanner.")

  local scanner, geoscanner = aid.is_module_equipped("scanner"), aid.is_module_equipped("geoScanner")

  if scanner or geoscanner then
    setup_context.debug("Found scanner.")
    if scanner and geoscanner then
      error("Who ported which mod to which loader, and why?", 0)
    end
  else
    if aid.swap_module("scanner", "left") then
      scanner = "left"
      setup_context.debug("Found scanner.")
    elseif aid.swap_module("geoScanner", "left") then
      geoscanner = "left"
      setup_context.debug("Found geoscanner.")
    else
      error("No scanner or geoscanner found.", 0)
    end
  end

  if aid.is_module_equipped("pickaxe") then
    setup_context.debug("Found pickaxe.")
  else
    if aid.swap_module("pickaxe", "right") then
      setup_context.debug("Found pickaxe.")
    else
      error("No pickaxe found.", 0)
    end
  end

  if scanner then
    setup_context.debug("Using scanner on", scanner, "side.")
    scan = function()
      return peripheral.call(scanner, "scan")
    end
  end

  if geoscanner then
    setup_context.debug("Using geoscanner on", geoscanner, "side.")
    scan = function()
      return peripheral.call(geoscanner, "scan", geoscanner_range)
    end
  end
end

-- The following turtle states are used:
-- 1. digdown - The turtle is digging down.
-- 2. seeking - The turtle is mining directly to a specific ore.
-- 3. returning_home - The turtle is returning to the surface.
-- 4. returning_from_seek - The turtle is returning to the last depth reached before seeking.
--
-- The turtle should follow the following steps, on EVERY block. Entering a new
-- should be counted as a "tick".
--
-- 1. Check current state.
-- 2. If digging down:
--   1. Check if the block below is bedrock.
--   2. If it is, change state to returning_home.
--   3. If it is not:
--     1. Scan around the turtle for ores.
--     2. If there are ores, change state to seeking, add ore position to state_info.
--     3. If there are not ores, dig down, then move down.
-- 3. If seeking:
--   1. Calculate direction needed to move to the ore.
--   2. Check if bedrock is blocking the way.
--     1. If it is, change state to returning_home.
--   3. If the turtle is beside the ore, mine it but do not move into it.
--     1. If it is not, move in the calculated direction, breaking blocks as needed.
--   4. If the turtle has collected the ore, scan for ores.
--     1. If there are ores, keep state as seeking, add new ore position to state_info.
--     2. If there are no ores, change state to returning_from_seek.
-- 4. If returning_home:
--   1. Check if the turtle is at the surface.
--   2. If it is, end program.
--   3. If it is not, calculate offset to centerpoint, move in that direction.
--     1. If the turtle is already at the centerpoint, move up.
-- 5. If returning_from_seek:
--   1. Check if the turtle is at the last depth reached before seeking.
--   2. If it is, and the turtle is at the centerpoint, change state to digging down.
--   3. If it is not, calculate offset to centerpoint, move in that direction.
--
-- The turtle does not automatically check fuel levels unless the fuel flag is
-- set. If the fuel flag is set, the turtle will check fuel levels every time it
-- moves, and if it is below 1000, it will attempt to refuel from ores mined.
-- If the turtle is unable to refuel and the distance to home is within 50 of
-- the remaining fuel, it will return home and end the program.
--
-- The turtle will also check for inventory space every time it mines a block,
-- and if it is full, it will return home then return to the last depth reached.
--
-- During all of the above, the turtle should save its state to a file every
-- time it changes state. This file should be loaded on startup, and if it
-- exists, the turtle should resume from where it left off. If the file does
-- not exist, the turtle should assume it is starting from the surface.

local ORE_DICT = {
  ["minecraft:iron_ore"] = true,
  ["minecraft:deepslate_iron_ore"] = true,
  ["minecraft:gold_ore"] = true,
  ["minecraft:deepslate_gold_ore"] = true,
  ["minecraft:diamond_ore"] = true,
  ["minecraft:deepslate_diamond_ore"] = true,
  ["minecraft:coal_ore"] = true,
  ["minecraft:deepslate_coal_ore"] = true,
  ["minecraft:lapis_ore"] = true,
  ["minecraft:deepslate_lapis_ore"] = true,
  ["minecraft:emerald_ore"] = true,
  ["minecraft:deepslate_emerald_ore"] = true,
  ["minecraft:quartz_ore"] = true,
  ["minecraft:redstone_ore"] = true,
  ["minecraft:deepslate_redstone_ore"] = true,
  ["minecraft:nether_gold_ore"] = true,
  ["minecraft:ancient_debris"] = true,
}

local state = {
  state = "digdown",
  state_info = {}
}

--- Strip the scan data down to just the coordinates and block name, then offset every block by the turtle's offset from home.
---@param data table<integer, table>
local function strip_and_offset_scan(data)
  local stripped = {}

  for _, block in ipairs(data) do
    table.insert(stripped, {
      x = block.x + aid.position.x,
      y = block.y + aid.position.y,
      z = block.z + aid.position.z,
      name = block.name
    })
  end

  return stripped
end

local function save_state()
  file_helper.serialize(STATE_FILE, state, true)
end

local function load_state()
  local loaded_state = file_helper.unserialize(STATE_FILE ,{
    state = "digdown",
    state_info = {}
  })
  if loaded_state then
    state = loaded_state
  end
end

local dig_context = logging.create_context("Dig Down")
local function dig_down()
  dig_context.debug("Digging down.")

  local success, block_data = turtle.inspectDown()
  if success and block_data.name == "minecraft:bedrock" then
    dig_context.warn("Hit bedrock, returning home.")
    state.state = "returning_home"
    return
  end

  local scanned = scan()
  if type(scanned) == "table" then
    -- Scan was a success, sort through it for the first ore (if there is one).
    state.state_info.last_scan = strip_and_offset_scan(scanned)
  end

  ---@TODO This is a temporary solution, we need to actually calculate the closest ore.
  local ore
  for i, block in ipairs(state.state_info.last_scan) do
    if ORE_DICT[block.name] then
      ore = i
      break
    end
  end

  -- if we found an ore, we want to seek it.
  if ore then
    state.state_info.ore = ore
    state.state = "seeking"
    return
  end

  -- if not, go down.
  turtle.digDown()
  aid.go_down()
  state.state_info.depth = aid.position.y
end

local seek_context = logging.create_context("Seek")
local function seek()
  seek_context.debug("Seeking to ore.")

  local ore = state.state_info.last_scan[state.state_info.ore]
  local x, y, z = ore.x, ore.y, ore.z
  local direction, distance = aid.get_direction_to(vector.new(x, y, z))

  if distance == 1 then
    seek_context.info("Ore is adjacent, mining.")
    if direction == "up" then
      turtle.digUp()
    elseif direction == "down" then
      turtle.digDown()
    else
      aid.face(direction --[[@as cardinal_direction]])
      turtle.dig()
    end

    seek_context.info("Ore mined, rescanning for more ores.")
    -- rescan for ores
    local scanned = scan()
    if type(scanned) == "table" then
      -- Scan was a success, sort through it for the first ore (if there is one).
      state.state_info.last_scan = strip_and_offset_scan(scanned)
    end

    ---@TODO This is a temporary solution, we need to actually calculate the closest ore.
    local new_ore
    for i, block in ipairs(state.state_info.last_scan) do
      if ORE_DICT[block.name] then
        new_ore = i
        break
      end
    end

    if new_ore then
      seek_context.info("Found another ore, seeking to it.")
      state.state_info.ore = new_ore
      state.state = "seeking"
    else
      seek_context.info("No more ores found, returning from seek.")
      state.state = "returning_from_seek"
    end
    return
  end

  if direction == "up" then
    aid.gravel_protected_dig_up()
    aid.go_up()
  elseif direction == "down" then
    turtle.digDown()
    aid.go_down()
  else
    aid.face(direction --[[@as cardinal_direction]])

    local success, block = turtle.inspect()
    if success and block.name == "minecraft:bedrock" then
      seek_context.warn("Hit bedrock, returning home.")
      state.state = "returning_home"
      return
    end

    aid.gravel_protected_dig()
    aid.go_forward()
  end
end

local function return_home()
  local direction, distance = aid.get_direction_to(vector.new(0, 0, 0), false, true)

  if distance == 0 then
    return true
  end

  if direction == "up" then
    aid.gravel_protected_dig_up()
    aid.go_up() -- we can use the aid functions here as we no longer need to worry about scanning.
  elseif direction == "down" then -- if this happens then the world is ending
    turtle.digDown()
    aid.go_down()
  else
    aid.face(direction --[[@as cardinal_direction]])
    aid.gravel_protected_dig()
    aid.go_forward()
  end

  return false
end

local function return_seek()
  local direction, distance = aid.get_direction_to(vector.new(0, state.state_info.depth, 0), false, true)

  if distance == 0 then
    state.state = "digdown"
  end

  if direction == "up" then
    aid.gravel_protected_dig_up()
    aid.go_up() -- we can use the aid functions here as we no longer need to worry about scanning.
  elseif direction == "down" then -- if this happens then the world is ending
    turtle.digDown()
    aid.go_down()
  else
    aid.face(direction --[[@as cardinal_direction]])
    aid.gravel_protected_dig()
    aid.go_forward()
  end
end

-- The turtle cannot know what direction it is facing initially, ask for that.
print("What direction is the turtle facing (north, south, east, west)? You can use the F3 menu to determine this.")
local _direction
repeat
  _direction = read()
until _direction == "north" or _direction == "south" or _direction == "east" or _direction == "west"
aid.facing = _direction == "north" and 0 or _direction == "east" and 1 or _direction == "south" and 2 or 3

load_state() -- initial load

-- Main loop
local function main()
  local tick_context = logging.create_context("Tick")
  while true do
    tick_context.debug("Tick. State is:", state.state)

    if state.state == "digdown" then
      dig_down()
    elseif state.state == "seeking" then
      seek()
    elseif state.state == "returning_home" then
      if return_home() then
        break
      end
    elseif state.state == "returning_from_seek" then
      return_seek()
    else
      error("Invalid state: " .. tostring(state.state), 0)
    end

    save_state() -- save the state at the end of each tick, so we don't need to spam it everywhere
  end
end

local main_context = logging.create_context("Main")
local ok, err = xpcall(main, debug.traceback)

if not ok then
  main_context.fatal(err)
  logging.dump_log(LOG_FILE)
end

-- Cleanup
main_context.debug("Cleaning up...")
aid.clear_save()
file_helper.delete(STATE_FILE)