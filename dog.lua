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
local max_offset = 8
local scan = nil ---@type fun():table<integer, table> Set during initialization.
local do_fuel = false
local version = "V0.10.3"
local latest_changes = [[Added more checks for bedrock. There are still a few cases I need to check for, but this should fix most of the issues.]]

local parser = simple_argparse.new_parser("dog", "Dog is a program run on mining turtles which is used to find ores and mine them. Unlike quarry programs, this program digs in a straight line down and uses either plethora's block scanner or advanced peripheral's geoscanner to detect where ores are along its path and mine to them.")
parser.add_option("depth", "The maximum depth to dig to.", max_depth)
parser.add_option("loglevel", "The log level to use.", "INFO")
parser.add_option("georange", "The range to use for the geoscanner, if using Advanced Peripherals.", geoscanner_range)
parser.add_flag("h", "help", "Show this help message and exit.")
parser.add_flag("f", "fuel", "Attempt to refuel as needed from ores mined.")
parser.add_flag("v", "version", "Show version information and exit.")
parser.add_argument("max_offset", "The maximum offset from the centerpoint to mine to.", false,  max_offset)

local parsed = parser.parse(table.pack(...))

-- FLAGS
if parsed.flags.help then
  local _, h = term.getSize()
  textutils.pagedPrint(parser.usage())
  return
end
if parsed.flags.version then
  print(version)
  print("Latest update notes:", latest_changes)
  return
end
if parsed.flags.fuel then
  do_fuel = true
end

-- OPTIONS
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

-- ARGUMENTS
if parsed.arguments.max_offset then
  ---@diagnostic disable-next-line max_offset is tested right after this
  max_offset = tonumber(parsed.arguments.max_offset)
  if not max_offset then
    error("Max offset must be a number.", 0)
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
  -- ## BASE ORES ##
  ["minecraft:iron_ore"] = true,
  ["minecraft:deepslate_iron_ore"] = true,
  ["minecraft:copper_ore"] = true,
  ["minecraft:deepslate_copper_ore"] = true,
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

  -- ##  MODDED ORES  ##
  -- Create
  ["create:zinc_ore"] = true,
  ["create_deepslate_zinc_ore"] = true,

  -- Mekanism
  ["mekanism:tin_ore"] = true,
  ["mekanism:deepslate_tin_ore"] = true,
  ["mekanism:osmium_ore"] = true,
  ["mekanism:deepslate_osmium_ore"] = true,
  ["mekanism:uranium_ore"] = true,
  ["mekanism:deepslate_uranium_ore"] = true,
  ["mekanism:fluorite_ore"] = true,
  ["mekanism:deepslate_fluorite_ore"] = true,
  ["mekanism:lead_ore"] = true,
  ["mekanism:deepslate_lead_ore"] = true,
  
  -- Thermal
  ["thermal:apatite_ore"] = true,
  ["thermal:deepslate_apatite_ore"] = true,
  ["thermal:cinnabar_ore"] = true,
  ["thermal:deepslate_cinnabar_ore"] = true,
  ["thermal:niter_ore"] = true,
  ["thermal:deepslate_niter_ore"] = true,
  ["thermal:sulfur_ore"] = true,
  ["thermal:deepslate_sulfur_ore"] = true,
  ["thermal:tin_ore"] = true,
  ["thermal:deepslate_tin_ore"] = true,
  ["thermal:lead_ore"] = true,
  ["thermal:deepslate_lead_ore"] = true,
  ["thermal:silver_ore"] = true,
  ["thermal:deepslate_silver_ore"] = true,
  ["thermal:nickel_ore"] = true,
  ["thermal:deepslate_nickel_ore"] = true,
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

--- Get the closest ore to the turtle.
---@return integer? closest_ore_index The index of the closest ore in the last scan, or nil if no ores were found in the scan.
local function get_closest_ore()
  -- Since we now offset the last scan, we will need to calculate based on the
  -- position of the turtle as well.
  local closest_ore

  local closest_distance = math.huge
  for i, block in ipairs(state.state_info.last_scan) do
    local distance = math.abs(block.x - aid.position.x) + math.abs(block.y - aid.position.y) + math.abs(block.z - aid.position.z)
    local out_of_range = false
    if block.x < -max_offset or block.x > max_offset
      or block.y < -max_depth
      or block.z < -max_offset or block.z > max_offset then
      out_of_range = true
    end

    if not out_of_range and ORE_DICT[block.name] and distance < closest_distance then
      closest_ore = i
      closest_distance = distance
    end
  end

  return closest_ore
end

local dig_context = logging.create_context("Dig Down")
local function dig_down()
  dig_context.debug("Digging down.")

  dig_context.debug("Current depth is", aid.position.y)
  dig_context.debug("Max depth is", max_depth)

  if aid.position.y < -max_depth then
    dig_context.info("Reached max depth, returning home.")
    state.state = "returning_home"
    return
  end

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

  local ore = get_closest_ore()

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

local bedrock_watch = logging.create_context("Bedrock Watch")
local function inspect_for_bedrock(direction)
  if direction == "forward" then
    local success, block = turtle.inspect()
    if success and block.name == "minecraft:bedrock" then
      bedrock_watch.warn("Hit bedrock, returning home.")
      state.state = "returning_home"
      return true
    end
  elseif direction == "up" then
    local success, block = turtle.inspectUp()
    if success and block.name == "minecraft:bedrock" then
      bedrock_watch.warn("Hit bedrock, returning home.")
      state.state = "returning_home"
      return true
    end
  elseif direction == "down" then
    local success, block = turtle.inspectDown()
    if success and block.name == "minecraft:bedrock" then
      bedrock_watch.warn("Hit bedrock, returning home.")
      state.state = "returning_home"
      return true
    end
  end
  return false
end

local seek_context = logging.create_context("Seek")
local function seek()
  local ore = state.state_info.last_scan[state.state_info.ore]
  local x, y, z = ore.x, ore.y, ore.z
  local direction, distance = aid.get_direction_to(vector.new(x, y, z), true)
  seek_context.debug("Seeking to ore.")
  seek_context.debug("Ore is", distance, "blocks away, positioned at", x, y, z)
  seek_context.debug("Turtle is positioned at", aid.position.x, aid.position.y, aid.position.z)

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
    table.remove(state.state_info.last_scan, state.state_info.ore) -- remove the ore from the scan

    seek_context.info("Ore mined, rescanning for more ores.")
    -- rescan for ores
    local scanned = scan()
    if type(scanned) == "table" then
      -- Scan was a success, sort through it for the first ore (if there is one).
      state.state_info.last_scan = strip_and_offset_scan(scanned)
    end

    local new_ore = get_closest_ore()

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
    ---@TODO: If bedrock is above, currently the turtle will be stuck. We will need to add a path retracer for this.
    if inspect_for_bedrock("up") then return end

    aid.gravel_protected_dig_up()
    aid.go_up()
  elseif direction == "down" then
    if inspect_for_bedrock("down") then return end

    turtle.digDown()
    aid.go_down()
  elseif not direction then
    error("Direction is nil, we're already on top of the detected ore!", 0)
  else
    aid.face(direction --[[@as cardinal_direction]])

    if inspect_for_bedrock("forward") then return end

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

local r_seek_context = logging.create_context("Return from seek")
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
  elseif not direction then
    r_seek_context.warn("Turtle aid is reporting we have already returned to the correct depth, but we are not.")
  else
    aid.face(direction --[[@as cardinal_direction]])
    aid.gravel_protected_dig()
    aid.go_forward()
  end
end

local dump_context = logging.create_context("Dump Inventory")
local function dump_inventory()
  -- First, find and face the chest.
  while not aid.find_chest() do
    dump_context.warn("Unable to find chest, waiting 5 seconds.")
    sleep(5)
  end

  -- Then, dump the inventory.
  for i = 1, 16 do
    if turtle.getItemCount(i) > 0 then
      turtle.select(i)
      if do_fuel and turtle.refuel() then
        dump_context.info("Refueled. Now have", turtle.getFuelLevel(), "fuel.")
      end
      turtle.drop()
    end
  end

  turtle.select(1) -- ensure the first slot is selected always.
end

--- Check that the turtle's inventory isn't too full.
---@return boolean full True if the inventory is full, false otherwise.
local function check_inventory()
  return turtle.getItemCount(15) > 0 -- we leave a single slot open in case the turtle comes across a new item while returning home.
end

--- Check that the turtle's fuel level isn't too low. Fuel is considered "too low"
--- if distance to the surface + 50 is greater than the fuel level.
---@return boolean low True if the fuel level is low, false otherwise.
local function check_fuel()
  return turtle.getFuelLevel() < (math.abs(aid.position.y) + math.abs(aid.position.z) + math.abs(aid.position.x) + 50)
end

-- The turtle cannot know what direction it is facing initially, ask for that.
print("What direction is the turtle facing (north, south, east, west)? You can use the F3 menu to determine this.")
local _direction
repeat
  _direction = read()
until _direction == "north" or _direction == "south" or _direction == "east" or _direction == "west"
aid.facing = _direction == "north" and 0 or _direction == "east" and 1 or _direction == "south" and 2 or 3

load_state() -- initial load

local main_context = logging.create_context("Main")
-- Main loop
local function main()
  local tick_context = logging.create_context("Tick")

  main_context.info("Digging down a block so we don't end up destroying the chest.")
  turtle.digDown()
  aid.go_down()
  main_context.info("Start main loop.")

  turtle.select(1) -- ensure the first slot is selected always.

  while true do
    tick_context.debug("Tick. State is:", state.state)

    if state.state == "digdown" then
      dig_down()
    elseif state.state == "seeking" then
      seek()
    elseif state.state == "fuel_low" then
      if return_home() then
        dump_inventory()
        tick_context.fatal("Low on fuel.")
        break
      end
    elseif state.state == "inventory_full" then
      if return_home() then
        dump_inventory()
        state.state = "returning_from_seek"
      end
    elseif state.state == "returning_home" then
      if return_home() then
        dump_inventory()
        break
      end
    elseif state.state == "returning_from_seek" then
      return_seek()
    else
      error("Invalid state: " .. tostring(state.state), 0)
    end

    if check_inventory() then
      state.state = "inventory_full"
    end

    if check_fuel() then
      tick_context.warn("Low on fuel! Returning to the surface.")
      state.state = "fuel_low"
    end

    save_state() -- save the state at the end of each tick, so we don't need to spam it everywhere
  end

  main_context.info("Reached home. Done.")
end

local ok, err = xpcall(main, debug.traceback)

-- Cleanup before dumping the log, in case the log is large (state file can be upwards of 500kb)
main_context.debug("Cleaning up...")
aid.clear_save()
file_helper.delete(STATE_FILE)

if not ok then
  main_context.fatal(err)
  logging.dump_log(LOG_FILE)
end

