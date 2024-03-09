--- Dog is a program run on mining turtles which is used to find ores and mine
--- them. Unlike quarry programs, this program digs in a straight line down and
--- uses either plethora's block scanner or advanced peripheral's geoscanner to
--- detect where ores are along its path and mine to them.

local expect = require "cc.expect".expect

-- Import libraries
local aid = require("lib.turtle_aid")
local file_helper = require("lib.file_helper"):instanced("")
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
local horizontal = false
local version = "V0.13.0"
local latest_changes = [[Added 'exclude', 'include', 'only' options; and 'level' flag. Run dog with the help flag to read more.]]

local parser = simple_argparse.new_parser("dog", "Dog is a program run on mining turtles which is used to find ores and mine them. Unlike quarry programs, this program digs in a straight line down and uses either plethora's block scanner or advanced peripheral's geoscanner to detect where ores are along its path and mine to them.")
parser.add_option("depth", "The maximum depth to dig to.", max_depth)
parser.add_option("loglevel", "The log level to use.", "INFO")
parser.add_option("georange", "The range to use for the geoscanner, if using Advanced Peripherals.", geoscanner_range)
parser.add_option("exclude", "A file (lua table) containing ores to exclude from mining.")
parser.add_option("include", "A file (lua table) containing blocks to include in mining.")
parser.add_option("only", "A file (lua table) containing blocks that should be the only ones mined.")
parser.add_flag("h", "help", "Show this help message and exit.")
parser.add_flag("f", "fuel", "Attempt to refuel as needed from ores mined.")
parser.add_flag("v", "version", "Show version information and exit.")
parser.add_flag("l", "level", "Travel in a horizontal line at the current level. Useful for mining sand and other surface ores when used in tandem with include or only.")
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
  print()
  print("Latest update notes:", latest_changes)
  return
end
if parsed.flags.fuel then
  do_fuel = true
end
if parsed.flags.level then
  horizontal = true
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
-- Ore exclusion, inclusion, only options are parsed after ORE_DICT is defined.

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
if parsed.options.exclude then
  if file_helper:exists(parsed.options.exclude) then
    local exclude = file_helper:unserialize(parsed.options.exclude)
    if type(exclude) == "table" then
      -- it's possible to do both `{["minecraft:ore"] = true}` and `{"minecraft:ore"}`, so we need to check for both.
      for key, value in pairs(exclude) do
        if type(key) == "string" then
          ORE_DICT[key] = nil
        end
        if type(value) == "string" then
          ORE_DICT[value] = nil
        end
      end
    else
      error("Failed to parse exclude file.", 0)
    end
  else
    error("Exclude file does not exist.", 0)
  end
end
if parsed.options.include then
  if file_helper:exists(parsed.options.include) then
    local include = file_helper:unserialize(parsed.options.include)
    if type(include) == "table" then
      -- it's possible to do both `{["minecraft:ore"] = true}` and `{"minecraft:ore"}`, so we need to check for both.
      for key, value in pairs(include) do
        if type(key) == "string" then
          ORE_DICT[key] = true
        end
        if type(value) == "string" then
          ORE_DICT[value] = true
        end
      end
    else
      error("Failed to parse include file.", 0)
    end
  else
    error("Include file does not exist.", 0)
  end
end
if parsed.options.only then
  if file_helper:exists(parsed.options.only) then
    local only = file_helper:unserialize(parsed.options.only)
    if type(only) == "table" then
      ORE_DICT = {} -- reset the ore dictionary, we're only mining what's in the only file.
      -- it's possible to do both `{["minecraft:ore"] = true}` and `{"minecraft:ore"}`, so we need to check for both.
      for key, value in pairs(only) do
        if type(key) == "string" then
          ORE_DICT[key] = true
        end
        if type(value) == "string" then
          ORE_DICT[value] = true
        end
      end
    else
      error("Failed to parse only file.", 0)
    end
  else
    error("Only file does not exist.", 0)
  end
end

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

--- Scan for ores, strip and offset the scan, then set the last scan in state_info to the result.
local function scan_ores()
  local scanned = scan()
  if type(scanned) == "table" then
    -- Scan was a success, sort through it for the first ore (if there is one).
    state.state_info.last_scan = strip_and_offset_scan(scanned)
  end
end

local function save_state()
  file_helper:serialize(STATE_FILE, state, true)
end

local function load_state()
  local loaded_state = file_helper:unserialize(STATE_FILE ,{
    state = "digdown",
    state_info = {}
  })
  if loaded_state then
    state = loaded_state
  end
end

local ore_context = logging.create_context("Ore")

--- Get the closest ore to the turtle.
---@return integer? closest_ore_index The index of the closest ore in the last scan, or nil if no ores were found in the scan.
---@param initial_facing turtle_facing? The direction the turtle was facing when it started digging.
local function get_closest_ore(initial_facing)
  -- Since we now offset the last scan, we will need to calculate based on the
  -- position of the turtle as well.
  local closest_ore

  local closest_distance = math.huge
  for i, block in ipairs(state.state_info.last_scan) do
    local distance = math.abs(block.x - aid.position.x) + math.abs(block.y - aid.position.y) + math.abs(block.z - aid.position.z)
    local out_of_range = false
    if initial_facing then
      -- ore_context.debug("Testing ore with name", block.name, "at", block.x, block.y, block.z, "with distance", distance)
      local initial_axis = (initial_facing == 0 or initial_facing == 2) and "z" or "x"
      local opposite_axis = initial_axis == "z" and "x" or "z"
      out_of_range = block.y < -max_offset or block.y > max_offset or block[opposite_axis] > max_offset or block[opposite_axis] < -max_offset
        or block[initial_axis] < -max_depth or block[initial_axis] > max_depth

      --[[
      ore_context.debug("  Initial axis is", initial_axis, "and opposite axis is", opposite_axis)
      ore_context.debug("  Initial facing is", initial_facing)
      ore_context.debug("  Out of range is", out_of_range)
      ore_context.debug(" ", block.y < -max_offset , block.y > max_offset , block[opposite_axis] > max_offset , block[opposite_axis] < -max_offset
      , block[initial_axis] < -max_depth , block[initial_axis] > max_depth)
      ]]
    else
      out_of_range = block.y < -max_depth or block.x < -max_offset or block.x > max_offset or block.z < -max_offset or block.z > max_offset
    end

    -- ore_context.debug("Exists in ore dict?", ORE_DICT[block.name] and "yes" or "no")
    if not out_of_range and ORE_DICT[block.name] and distance < closest_distance then
      closest_ore = i
      closest_distance = distance
    end
  end

  return closest_ore
end

local dig_context = logging.create_context("Dig")

--- Dig forward, scanning for ores as we go. Used in place of dig_down when level flag is set.
---@param initial_facing turtle_facing The direction the turtle was facing when it started digging.
local function dig_forward(initial_facing)
  dig_context.debug("Digging forward.")

  -- max_depth will now be the maximum distance forward we can go, so we need to determine
  -- which way is "forward" and how far we are along that axis.
  local forward_axis
  if initial_facing == 0 or initial_facing == 2 then
    forward_axis = "z"
  else
    forward_axis = "x"
  end

  dig_context.debug("Current depth is", math.abs(aid.position[forward_axis]))
  dig_context.debug("Max depth is", max_depth)

  if math.abs(aid.position[forward_axis]) >= max_depth then
    dig_context.info("Reached max depth, returning home.")
    state.state = "returning_home"
    return
  end

  scan_ores()

  local ore = get_closest_ore(initial_facing)

  -- if we found an ore, we want to seek it.
  if ore then
    state.state_info.ore = ore
    state.state = "seeking"
    return
  end

  -- if not, go forward.
  -- Also, ensure we are facing the correct direction.
  aid.face(initial_facing)
  turtle.dig()
  aid.go_forward()
  state.state_info.depth = aid.position[forward_axis] -- """depth""" is now the distance we've gone forward.
end

--- Dig down, scanning for ores as we go.
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

  scan_ores()

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
local function seek(initial_facing)
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
    scan_ores()

    local new_ore = get_closest_ore(initial_facing)

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

--- Go to specific coordinates, checking if bedrock is in the way.
--- This method is expected to be used for returning from mining, not for
--- locating ores. It will trigger a path retrace if bedrock is in the way.
---@param x integer
---@param y integer
---@param z integer
---@return boolean reached True if the turtle has reached the coordinates, false otherwise.
---@return boolean retraced True if the turtle had to retrace its path, false otherwise.
local function goto_safe(x, y, z)
  local direction, distance = aid.get_direction_to(vector.new(x, y, z), false, true)

  if distance == 0 then
    return true, false
  end

  if direction == "up" then
    if inspect_for_bedrock("up") then
      bedrock_watch.warn("Bedrock hit in return path, triggering path retrace. Ticking will stop momentarily.")
      aid.retrace(true)
      return false, true
    end
    aid.gravel_protected_dig_up()
    aid.go_up()
  elseif direction == "down" then
    if inspect_for_bedrock("down") then
      bedrock_watch.warn("Bedrock hit in return path, triggering path retrace. Ticking will stop momentarily.")
      aid.retrace(true)
      return false, true
    end
    turtle.digDown()
    aid.go_down()
  else
    aid.face(direction --[[@as cardinal_direction]])
    if inspect_for_bedrock("forward") then
      bedrock_watch.warn("Bedrock hit in return path, triggering path retrace. Ticking will stop momentarily.")
      aid.retrace(true)
      return false, true
    end
    aid.gravel_protected_dig()
    aid.go_forward()
  end

  return false, false
end

--- Return to the surface.
---@return boolean finished True if the turtle has reached the surface, false otherwise.
local function return_home()
  local finished, bedrock = goto_safe(0, 0, 0)
  if finished then
    return true
  end

  if bedrock then
    bedrock_watch.info("Path retrace complete.")
  end
  return false
end

local r_seek_context = logging.create_context("Return from seek")
local function return_seek(initial_facing)
  local finished, bedrock
  if horizontal then
    local initial_axis = (initial_facing == 0 or initial_facing == 2) and "z" or "x"
    if initial_axis == "z" then
      finished, bedrock = goto_safe(0, 0, state.state_info.depth)
    else
      finished, bedrock = goto_safe(state.state_info.depth, 0, 0)
    end
  else
    finished, bedrock = goto_safe(0, state.state_info.depth, 0)
  end
  if finished then
    state.state = "digdown"
    return true
  end

  if bedrock then
    bedrock_watch.info("Path retrace complete.")
  end
  return false
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

local main_context = logging.create_context("Main")
-- The turtle cannot know what direction it is facing initially, ask for that.
if horizontal and not parsed.options.depth then
  main_context.warn(("Turtle is set to move horizontally, but no max depth was specified. The turtle will go %d blocks forward! If this is okay, enter the direction as normal, otherwise terminate now!"):format(max_depth))
end
print("What direction is the turtle facing (north, south, east, west)? You can use the F3 menu to determine this.")
local _direction
repeat
  _direction = read()
until _direction == "north" or _direction == "south" or _direction == "east" or _direction == "west"
aid.facing = _direction == "north" and 0 or _direction == "east" and 1 or _direction == "south" and 2 or 3

--load_state() -- initial load
-- We will reimplement this later, once it's actually ready.

-- Main loop
local function main()
  local tick_context = logging.create_context("Tick")
  aid.set_retrace_distance(math.min(16, max_offset * 4))

  main_context.info("Digging down or forward a block so we don't end up destroying the chest.")
  if horizontal then
    turtle.dig()
    aid.go_forward()
  else
    turtle.digDown()
    aid.go_down()
  end
  main_context.info("Start main loop.")

  turtle.select(1) -- ensure the first slot is selected always.

  local initial_facing = aid.facing

  while true do
    tick_context.debug("Tick. State is:", state.state)

    if state.state == "digdown" then
      if horizontal then
        dig_forward(initial_facing)
      else
        dig_down()
      end
    elseif state.state == "seeking" then
      seek(initial_facing)
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
      return_seek(initial_facing)
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

    --save_state() -- save the state at the end of each tick, so we don't need to spam it everywhere
    -- we will reimplement this later, once it's actually ready.
  end

  main_context.info("Reached home. Done.")
end

local ok, err = xpcall(main, debug.traceback)

-- Cleanup before dumping the log, in case the log is large (state file can be upwards of 500kb)
main_context.debug("Cleaning up...")
aid.clear_save()
file_helper:delete(STATE_FILE)

if not ok then
  sleep() -- in case this was an infinite loop related error.
  main_context.fatal(err)
  logging.dump_log(LOG_FILE)

  -- Attempt to return home to protect the turtle from becoming lost underground.
  pcall(function()
    main_context.warn("Attempting to return home!")

    local x = 0
    repeat
      x = x + 1
      if x > 300 then -- 300 chosen arbitrarily. This may or may not be a good value.
        main_context.fatal("Unable to return home, aborting.")
        break
      end
    until return_home()
  end)
end

