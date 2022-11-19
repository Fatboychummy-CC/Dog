local tArgs = table.pack(...)
local expect = require("cc.expect").expect

--[[ Windows ]]
local maxX, maxY = term.getSize()
local printWindow = window.create(term.current(), 1, maxY - 5, maxX, 7)
local fuelWindow  = window.create(term.current(), 1, maxY - 9, maxX, 3)
local posWindow   = window.create(term.current(), 1, maxY - 11, maxX, 1)
term.setBackgroundColor(colors.gray)
term.clear()
printWindow.clear()
fuelWindow.clear()
posWindow.clear()

-- printwindow stuffs
local oprint, oprintError = print, printError
local function print(box, ...)
  local oldwindow = term.redirect(printWindow)
  term.setBackgroundColor(colors.black)
  if box then
    oprint(string.format("[%s]", box), ...)
  else
    oprint()
  end
  term.redirect(oldwindow)
end
local function printError(box, ...)
  local oldwindow = term.redirect(printWindow)
  term.setBackgroundColor(colors.black)
  if box then
    oprintError(string.format("[%s]", box), ...)
  else
    oprintError()
  end
  term.redirect(oldwindow)
end

local repClear = string.rep(' ', maxX)
-- fuelwindow
local startFuel = turtle.getFuelLevel()
local function updateFuel(Needed, Have)
  local oldwindow = term.redirect(fuelWindow)

  local repHave  = string.rep(' ', math.floor((Have / startFuel) * maxX + 0.5))
  local repNeed  = string.rep('\127', math.floor((Needed / startFuel) * maxX + 0.5))
  -- length is maxX
  local function draw(x, fg, bg)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    for i = 1, 3 do
      term.setCursorPos(1, i)
      term.write(x)
    end
  end
  draw(repClear, colors.white,  colors.black)
  draw(repHave,  colors.white,  colors.green)
  draw(repNeed,  colors.orange, colors.green)

  term.setTextColor(colors.white)
  term.setBackgroundColor(colors.black)
  term.redirect(oldwindow)
end

local function updatePos(x, y, z, facing)
  local oldwindow = term.redirect(posWindow)

  term.setCursorPos(1, 1)
  term.setBackgroundColor(colors.black)
  term.write(repClear)
  term.setCursorPos(1, 1)
  term.write(string.format("x:%d | y:%d | z:%d | f: %s", x, y, z, facing))

  term.redirect(oldwindow)
end

--[[ Le main programme ]]
local function PrintUsage(i)
  local sOwnName = shell.getRunningProgram()
  printError("ARG", string.format("Bad command line argument #%d.", i))
  printError("ARG", "Usage:")
  printError("ARG", string.format("  %s [number maxOffset] [number maxDepth]", sOwnName))
  error("Requires pickaxe and block scanner.", 0)
end

local function CheckArgs()
  if type(tonumber(tArgs[1])) ~= "number" and type(tArgs[1]) ~= "nil" then
    PrintUsage(1)
    return false
  elseif type(tonumber(tArgs[2])) ~= "number" and type(tArgs[2]) ~= "nil" then
    PrintUsage(2)
    return false
  end
  return true
end

local function CheckSide(sSide, sType, sMethod)
  expect(1, sSide,   "string")
  expect(2, sType,   "string")
  expect(3, sMethod, "string")

  if peripheral.getType(sSide) == sType then
    local tMethods = peripheral.getMethods(sSide)
    for i = 1, #tMethods do
      if sMethod == tMethods[i] then
        return function(...) return peripheral.call(sSide, sMethod, ...) end
      end
    end
  else
    print("CheckSide", string.format("No peripheral of type '%s' on side %s.", sType, sSide))
    return
  end
  print("CheckSide", string.format("No method '%s' in peripheral on side %s.", sMethod, sSide))
end

local function CheckPresence(sType, sMethod)
  expect(1, sType,   "string")
  expect(2, sMethod, "string")

  local Left = CheckSide("left", sType, sMethod)
  if Left then return Left end
  local Right = CheckSide("right", sType, sMethod)
  if Right then return Right end
  error(string.format("Missing peripheral of type '%s' (or peripheral is missing method '%s').", sType, sMethod))
end

local function GetBlockAt(x, y, z, tScanData)
  expect(1, x,         "number")
  expect(2, y,         "number")
  expect(3, z,         "number")
  expect(4, tScanData, "table")

  for i = 1, #tScanData do
    if tScanData[i].x == x and tScanData[i].y == y and tScanData[i].z == z then
      return tScanData[i]
    end
  end
end

local function GetDirection(tScanData)
  expect(1, tScanData, "table")

  local tBlock = GetBlockAt(0, 0, 0, tScanData)
  if not tBlock or not tBlock.state or not tBlock.state.facing then
    error("Cannot get direction")
  end
  return tBlock and tBlock.state and tBlock.state.facing or "unknown"
end

local function ensure(func, ...)
  expect(1, func, "function")
  local tFailCalls = table.pack(...)
  for i = 1, tFailCalls.n do
    expect(i + 1, tFailCalls[i], "function")
  end

  local count = 0
  while not func() do
    for i = 1, tFailCalls.n do
      tFailCalls[i]()
    end
    count = count + 1
    if count > 100 then
      error("We've failed to move after 100 tries.")
    end
    os.sleep()
  end
end

local function BlockEQ(tBlock, sName, sDamage)
  expect(1, tBlock,  "table")
  expect(2, sName,   "string")
  expect(3, sDamage, "number")

  return tBlock.name == sName and tBlock.metadata == sDamage
end

local function main()
  print("Main", "Init")
  -- if the arguments were bad, stop
  if not CheckArgs() then return end

  local scan = CheckPresence("plethora:scanner", "scan")
  local pos = {
    x = 0,
    y = 0,
    z = 0,
    facing=GetDirection(scan())
  }
  local tOffsets = {
    north = {x = 0,  y = 0, z = -1, right = "east",  left = "west"},
    east  = {x = 1,  y = 0, z = 0,  right = "south", left = "north"},
    south = {x = 0,  y = 0, z = 1,  right = "west",  left = "east"},
    west  = {x = -1, y = 0, z = 0,  right = "north", left = "south"}
  }
  local tSteps = {n = 0}
  function tSteps.Push(x, y, z)
    expect(1, x, "number")
    expect(2, y, "number")
    expect(3, z, "number")

    tSteps.n = tSteps.n + 1
    print("Retracer", "Push", tSteps.n, string.format("x:%d y:%d z:%d", x, y, z))
    tSteps[tSteps.n] = {x = x, y = y, z = z}
    while tSteps.n > 10 do
      print("Retracer", "Remove 1")
      table.remove(tSteps, 1)
      tSteps.n = tSteps.n - 1
    end
  end
  function tSteps.Pop()
    if tSteps.n == 0 then return end
    print("Retracer", "Pop", tSteps.n)
    local Vector3 = tSteps[tSteps.n]
    tSteps[tSteps.n] = nil
    tSteps.n = tSteps.n - 1
    return Vector3.x, Vector3.y, Vector3.z
  end

  local nMaxOffset = tonumber(tArgs[1]) or math.huge
  local nMaxDepth = tonumber(tArgs[2]) or 256
  print("Main", string.format("Offset:%d, depth:%d", nMaxOffset, nMaxDepth))

  local GoHome
  local debounce = true
  local function CheckFuel()
    local FuelNeededForReturn = math.abs(pos.x) + math.abs(pos.y) + math.abs(pos.z) + 1
    updateFuel(FuelNeededForReturn, turtle.getFuelLevel())
    if FuelNeededForReturn >= turtle.getFuelLevel() and debounce then
      debounce = false
      print("Fueler", "Our next move will cause us to run out of fuel!")
      GoHome(true, "Out of fuel.")
    end
    updatePos(pos.x, pos.y, pos.z, pos.facing)
  end

  local function GetOffset(sDir)
    return tOffsets[sDir].x, tOffsets[sDir].y, tOffsets[sDir].z
  end
  -- adds a movement offset to the turtle's position
  local function AddOffset(sDir)
    expect(1, sDir, "string")
    expect(1000, tOffsets[sDir], "table")

    pos.x = pos.x + tOffsets[sDir].x
    pos.y = pos.y + tOffsets[sDir].y
    pos.z = pos.z + tOffsets[sDir].z
  end
  -- move down, checks if bedrock is below.
  -- returns true if bedrock is below
  local function Down(tScanData)
    tScanData = tScanData or scan()

    if BlockEQ(GetBlockAt(0, -1, 0, tScanData), "minecraft:bedrock", 0) then
      return true
    end
    ensure(turtle.down, turtle.digDown, turtle.attackDown)
    pos.y = pos.y - 1
    CheckFuel()
  end
  -- move up
  local function Up(tScanData)
    tScanData = tScanData or scan()

    if BlockEQ(GetBlockAt(0, 1, 0, tScanData), "minecraft:bedrock", 0) then
      return true
    end

    ensure(turtle.up, turtle.digUp, turtle.attackUp)
    pos.y = pos.y + 1
    CheckFuel()
  end
  -- go forward, checks if bedrock is in front
  -- returns true if bedrock is in front
  local function Forward(tScanData)
    tScanData = tScanData or scan()
    local ox, oy, oz = GetOffset(pos.facing)
    if BlockEQ(GetBlockAt(ox, oy, oz, tScanData), "minecraft:bedrock", 0) then
      return true
    end

    ensure(turtle.forward, turtle.dig, turtle.attack)
    AddOffset(pos.facing)
    CheckFuel()
  end
  local function Right()
    turtle.turnRight()
    pos.facing = tOffsets[pos.facing].right
    updatePos(pos.x, pos.y, pos.z, pos.facing)
  end
  local function Left()
    turtle.turnLeft()
    pos.facing = tOffsets[pos.facing].left
    updatePos(pos.x, pos.y, pos.z, pos.facing)
  end
  -- determine the fastest direction for turning
  local function GetFastestTurn(sDir)
    expect(1, sDir, "string")
    expect(1000, tOffsets[sDir], "table")

    if tOffsets[sDir].right == pos.facing then
      return Left
    else
      return Right
    end
  end
  -- face a direction using the GetFastestTurn function
  local function Face(sDir)
    expect(1, sDir, "string")
    expect(1000, tOffsets[sDir], "table")
    if pos.facing == sDir then
      return
    end
    local Turn = GetFastestTurn(sDir)
    while pos.facing ~= sDir do
      Turn()
    end
  end
  -- go to position x,y,z, with direction sDir (if provided) by simply moving along each axis (no pathfinding).
  -- without bYLast: YXZ
  -- with    bYLast: XZY
  local lastGoTo = {x=0, y=0, z=0}
  local duplicateCount = 0
  local function compare(x, y, z)
    if lastGoTo.x == x and lastGoTo.y == y and lastGoTo.z == z then
      return true
    end
  end
  local function GoTo(x, y, z, sDir, bYLast, bNoRecord)
    expect(1, x, "number")
    expect(2, y, "number")
    expect(3, z, "number")
    expect(4, sDir, "string", "nil")
    expect(5, bYLast, "boolean", "nil")
    if not bNoRecord then
      tSteps.Push(x, y, z)
    end

    if sDir then
      expect(1000, tOffsets[sDir], "table")
    end
    if compare(x, y, z) then
      duplicateCount = duplicateCount + 1
      if duplicateCount >= 5 then
        printError("GOTO", "We've issued the same movement command five times or more.  Are we stuck?")
      end
    end
    print("GOTO", string.format("x:%d, y:%d, z:%d", x, y, z))

    local function X()
      -- equalize X axis
      while pos.x < x do
        Face("east")
        if Forward() then return true end
      end
      while pos.x > x do
        Face("west")
        if Forward() then return true end
      end
    end
    local function Y()
      -- equalize Y axis
      while pos.y < y do
        if Up() then return true end
      end
      while pos.y > y do
        if Down() then return true end
      end
    end
    local function Z()
      -- equalize Z axis
      while pos.z < z do
        Face("south")
        if Forward() then return true end
      end
      while pos.z > z do
        Face("north")
        if Forward() then return true end
      end
    end

    if bYLast then
      if X() then return true end
      if Z() then return true end
      if Y() then return true end
    else
      if Y() then return true end
      if X() then return true end
      if Z() then return true end
    end
    if sDir then Face(sDir) end
  end
  local function ComputeAbsoluteFromRelative(x, y, z)
    expect(1, x, "number")
    expect(2, y, "number")
    expect(3, z, "number")

    return pos.x + x, pos.y + y, pos.z + z
  end
  -- check if the inventory is full.
  local function CheckInventory()
    local slotsFilled = 0
    for i = 1, 16 do
      if turtle.getItemCount(i) > 0 then
        slotsFilled = slotsFilled + 1
      end
      if slotsFilled > 15 then
        return true
      end
    end
    return false
  end
  local function DropItems()
    for i = 1, 16 do
      turtle.select(i)
      turtle.drop(64)
    end
  end
  local function GetOres(tOreDict, CurrentScan)
    expect(1, tOreDict, "table")
    expect(2, CurrentScan, "table")

    local tOres = {n = 0}
    for i = 1, #CurrentScan do
      for name, tDamage in pairs(tOreDict) do
        for j = 1, #tDamage do
          if CurrentScan[i] and CurrentScan[i].name == name and CurrentScan[i].metadata == tDamage[j] then
            tOres.n = tOres.n + 1
            tOres[tOres.n] = CurrentScan[i]
          end
        end
      end
    end
    return tOres
  end
  -- get the closest ore in range, obeying max offset.
  local function GetClosestInRange(tOres)
    expect(1, tOres, "table")

    local ClosestOre, ClosestDistance = nil, math.huge
    -- for each ore scanned
    for i = 1, tOres.n do
      local cOre = tOres[i]
      -- get it's absolute position from 0,0,0
      local nx, ny, nz = ComputeAbsoluteFromRelative(cOre.x, cOre.y, cOre.z)

      -- if it's inside the maximum offset...
      if not (math.abs(nx) > nMaxOffset or math.abs(nz) > nMaxOffset or math.abs(ny) > nMaxDepth) then
        -- and it's closer than other ores
        local Distance = vector.new(cOre.x, cOre.y, cOre.z):length()
        if Distance < ClosestDistance then
          -- set it as the new minimum
          ClosestOre = cOre
          ClosestDistance = Distance
        end
      end
    end
    if ClosestOre then
      print("Ores", string.format("rx:%d, ry:%d, rz:%d", ClosestOre.x, ClosestOre.y, ClosestOre.z))
    else
      print("Ores", "Nothing visible.")
    end
    return ClosestOre, ClosestDistance
  end

  -- check if there's a chest to drop items to (otherwise once we are full we will just return to surface and stop mining).
  local bCanDrop = false
  local sDropDir
  local function _check()
    -- check front for chest
    local function check()
      local front = peripheral.getType("front")
      if type(front) == "string" and (front:find("chest") or front:find("shulker")) then
        bCanDrop = true
        sDropDir = pos.facing
        return true
      end
    end
    -- check all sides
    if check() then bCanDrop = true return end
    for i = 1, 3 do
      Right()
      if check() then bCanDrop = true return end
    end
  end
  _check()
  local function CopyPos()
    return {x = pos.x, y = pos.y, z = pos.z, facing = pos.facing}
  end

  local function retrace()
    repeat
      local x, y, z = tSteps.Pop()
      if x then
        GoTo(x, y, z, nil, false, true)
        GoTo(x, y, z, nil, true, true)
      end
    until not x
  end

  GoHome = function(halt, err)
    -- if we are able to drop the items
    if bCanDrop and not halt then
      -- go home, drop items, return to where we were
      local currentPos = CopyPos()
      if GoTo(0, 0, 0, sDropDir, true) then
        if GoTo(0, -3, 0, sDropDir) then
          printError("GoHome", "Warning: Stuck! Attempting to fix.")
          retrace()
        end
        GoTo(0, 0, 0, sDropDir, true)
      end
      DropItems()
      GoTo(currentPos.x, currentPos.y, currentPos.z, currentPos.facing)
    else
      -- go home, stop.
      if GoTo(0, 0, 0, nil, true) then
        if GoTo(0, -3, 0) then
          printError("GoHome", "Warning: Stuck! Attempting to fix.")
          retrace()
        end
        GoTo(0, 0, 0, nil, true)
      end
      error(err and err or "Stop.", 0)
    end
  end

  -- recursively mine ores going after the closest ones.
  local function MineOres(tOreDict)
    if CheckInventory() then
      if GoHome() then return true end
    end
    -- scan
    local CurrentScan = scan()

    -- check for ores.
    local Ore, Distance = GetClosestInRange(GetOres(tOreDict, CurrentScan))
    if Ore then
      local px, py, pz = ComputeAbsoluteFromRelative(Ore.x, Ore.y, Ore.z)
      if GoTo(px, py, pz) then
        GoHome(true, "LEEEEEERRRRRROOOOOOOOOYYYYYYY JENNNKIIINNNSSS")
      end
    else
      return
    end
    return MineOres(tOreDict)
  end

  local tIgnoreList = {}
  local tOreDict = {
    ["actuallyadditions:block_misc"] = {3},
    ["minecraft:iron_ore"] = {0},
    ["minecraft:gold_ore"] = {0},
    ["minecraft:diamond_ore"] = {0},
    ["minecraft:coal_ore"] = {0},
    ["minecraft:lapis_ore"] = {0},
    ["minecraft:emerald_ore"] = {0},
    ["minecraft:quartz_ore"] = {0},
    ["minecraft:redstone_ore"] = {0},
    ["thermalfoundation:ore"] = {0,1,2,3,4,5,6,7,8},
    ["thermalfoundation:ore_fluid"] = {0,1,2,3,4,5},
    ["railcraft:ore_metal"] = {0,1,2,3,4,5},
    ["railcraft:ore_metal_poor"] = {0,1,2,3,4,5,6,7},
    ["bno:ore_netherdiamond"] = {0},
    ["bno:ore_netheremerald"] = {0},
    ["bno:ore_netherredstone"] = {0},
    ["bno:ore_netheriron"] = {0},
    ["bno:ore_nethergold"] = {0},
    ["bno:ore_nethercoal"] = {0},
    ["bno:ore_nethertin"] = {0},
    ["bno:ore_nethercopper"] = {0},
    ["bno:ore_netherlapis"] = {0},
    ["dungeontactics:nethergold_ore"] = {0},
    ["ic2:blockmetal"] = {0,1,2,3},
    ["appliedenergistics2:quartz_ore"] = {0},
    ["appliedenergistics2:charged_quartz_ore"] = {0},
    ["dungeontactics:silver_ore"] = {0},
    ["dungeontactics:mithril_ore"] = {0},
    ["dungeontactics:stonequartz_ore"] = {0},
    ["dungeontactics:enddiamond_ore"] = {0},
    ["dungeontactics:endlapis_ore"] = {0},
    ["galacticraftcore:basic_block_core"] = {5,6,7,8},
    ["galacticraftcore:basic_block_moon"] = {0,1,2,6},
    ["galacticraftplanets:mars"] = {0,1,2,3},
    ["galacticraftplanets:asteroids_block"] = {3,5},
    ["galacticraftplanets:venus"] = {6,7,8,9,10,11,13},
    ["rftools:dimensional_shard_ore"] = {0,1,2},
    ["quark:biotite_ore"] = {0},
    ["railcraft:ore"] = {0,1,2,3,4},
    ["railcraft:ore_magic"] = {0},
    ["tconstruct:ore"] = {0,1},
    ["forestry:resources"] = {0,1,2},
    ["dimensionalpocketsii:block_dimensional_ore"] = {0},
    ["mekanism:oreblock"] {0,1,2},
  }
  local lastY = 0

  -- dig down
  print("Main", "Dig start")
  while math.abs(pos.y) <= nMaxDepth do
    print("Main", "Y depth:", pos.y)
    -- if the inventory is full
    if CheckInventory() then
      if GoHome() then print("Main", "Out of space.") break end
    end

    -- go down
    -- if bedrock below, we need to stop and return.
    if Down() then
      break
    end
    lastY = lastY - 1

    if MineOres(tOreDict) then break end
    GoTo(0, lastY, 0)
  end
  -- go home
  GoHome(true, "Done mining.")
end

local bOK, sErr = pcall(main)
if not bOK then
  printError("System", sErr)
end
print()
term.setCursorPos(1, maxY)
