--- A* Pathfinding algorithm for Dog.

local expect = require "cc.expect".expect
local utilities = require "doggo.pathfinding.utilities"

---@class Doggo.Pathfinding.AStar.Node
---@field position ccTweaked.Vector The position of the node.
---@field facing Doggo.Movement.Orientation The orientation the turtle is in when at this node.
---@field f number The total cost (g + h).
---@field g number The actual cost from the start node to this node.
---@field h number The heuristic cost from this node to the goal node.
---@field visited boolean Whether this node has been visited.
---@field parent Doggo.Pathfinding.AStar.Node? The parent node, or nil if this is the start node.
---@field neighbours Doggo.Pathfinding.AStar.Node[] The neighboring nodes.
---@field origin Doggo.Mapping.Chunk.BlockData The original map node this pathfinding node was created from.

---@class Doggo.Pathfinding.AStar.Heuristics
---@field heuristic_multiplier number A multiplier applied to the heuristic cost (h).
---@field actual_multiplier number A multiplier applied to the actual cost (g).
---@field max_cost integer The maximum actual cost allowable for a node (helps limit search space).
---@field unknown_passable boolean Whether unknown blocks are considered passable.
---@field unknown_cost number The *additional* actual cost of moving through an unknown block, if unknown_passable is true.
---@field turn_cost number The *additional* actual cost if the turtle must turn to reach a position.
---@field turn_penalty number The *additional* heuristic cost when turtle is facing away from target. Can apply twice if facing the complete opposite direction.



--- Calculates the Manhattan distance between two positions.
---@param a ccTweaked.Vector
---@param b ccTweaked.Vector
---@return number distance The Manhattan distance between the two positions.
local function manhattan(a, b)
  return math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z)
end



--- Creates a pathfinding node from a map node.
---@param map_node Doggo.Mapping.Chunk.BlockData The map node to create the pathfinding node from.
---@return Doggo.Pathfinding.AStar.Node node The created pathfinding node.
local function _create_node(map_node)
  return {
    position = map_node.position,
    facing = nil, -- Uninitialized by default!
    f = 0,
    g = 0,
    h = 0,
    parent = nil,
    visited = false,
    neighbours = {},
    origin = map_node
  }
end



local string_format = string.format
--- Generates a unique key for a node based on its position.
---@param pos ccTweaked.Vector The node to generate the key for.
---@return string key The unique key for the node, in the format "x_y_z".
local function node_key(pos)
  return string_format("%d_%d_%d", pos.x, pos.y, pos.z)
end



--- Creates a pathfinding node from a map node.
---@param map Doggo.Mapping.Map The map the node is part of.
---@param map_node Doggo.Mapping.Chunk.BlockData The map node to create the pathfinding
---@param all_nodes table<string, Doggo.Pathfinding.AStar.Node> A table of all created nodes, indexed by "x_y_z".
---@return Doggo.Pathfinding.AStar.Node node The created pathfinding node.
local function create_node(map, map_node, all_nodes)
  local key = node_key(map_node.position)
  if all_nodes[key] then
    return all_nodes[key]
  end

  local node = _create_node(map_node)
  all_nodes[key] = node

  if not map_node.name or not map_node.walkable then
    return node -- Don't traverse neighbours of walls or unknown blocks.
  end

  -- Get the neighbours.
  for _, neighbour in ipairs(map_node:neighbours(map)) do
    table.insert(node.neighbours, create_node(map, neighbour, all_nodes))
  end

  return node
end



---@class Doggo.Pathfinding.AStar
---@field heuristics Doggo.Pathfinding.AStar.Heuristics The available heuristic parameters.
---@field all_nodes table<string, Doggo.Pathfinding.AStar.Node> A reference to the table of all built pathfinding nodes, indexed by "x_y_z".
local AStar = {}



--- Creates a new pathfinder instance.
---@return Doggo.Pathfinding.AStar pathfinder The new pathfinder instance.
function AStar.new()
  local pathfinder = setmetatable({
    heuristics = {
      unknown_passable = false,
      unknown_cost = 5,
      heuristic_multiplier = 1,
      actual_multiplier = 1,
      turn_cost = 2,
      turn_penalty = 1,
      max_cost = 1000,
    },

    all_nodes = {}
  }, { __index = AStar })

  return pathfinder
end



--- Builds the node map from the given map and start position.
---
--- This needs to be done before pathfinding can occur.
--- Node maps can be reused if the map itself has not changed.
---@param map Doggo.Mapping.Map The map to build the node map from.
---@param start ccTweaked.Vector The starting position.
function AStar:buildNodeMap(map, start)
  expect(1, map, "table")
  expect(2, start, "table")

  create_node(map, map:getBlock(start), self.all_nodes)
end



--- Attempts to create a path to a specified position.
---
--- Uses manhattan heuristic, without checking turn costs.
---
--- Uses the following heuristic parameters:
--- - unknown_passable
--- - unknown_cost
--- - heuristic_multiplier
--- - actual_multiplier
---@param map Doggo.Mapping.Map The map to use for pathfinding.
---@param start ccTweaked.Vector The starting position.
---@param goal ccTweaked.Vector The goal position.
function AStar:manhattanPath(map, start, goal)
  local open_set = utilities.FIFO()
  local closed_set = {}
  local all_nodes = {}

  open_set:enqueue(map:getBlock(start))


end