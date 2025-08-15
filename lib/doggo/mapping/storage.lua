--- Storage module for Doggo mapping.
--- Handles saving and loading maps.

---@TODO "Large" and "Small" maps, containing block names and no block names, respectively.

---@class Doggo.Mapping.Storage
local Storage = {}

local const = "DOGMAP"
local version_major = 1
local version_minor = 0
local version_patch = 0
local version_build = 0
local base_header = string.pack("<c6I4I4I4I16>", const, version_major, version_minor, version_patch, version_build)



--- Binary file definition for maps:
--[[
  MAIN HEADER
  1. CONST - "DOGMAP"
    * Used to identify the file as a Doggo map.
  2. UINT8 - Major version number
    * The major version number of the Doggo mapping format. Higher versions cannot load lower versions, and vice versa.
  3. UINT8 - Minor version number
    * The minor version number of the Doggo mapping format. Higher versions can most likely load lower versions, but not vice versa.
  4. UINT8 - Patch version number
    * The patch version number of the Doggo mapping format. Higher versions can most likely load lower versions, but not vice versa.
  5. UINT16 - Build number
    * The specific build number of the Doggo mapping format. Mostly for logging purposes.
  6. UINT8 - Flags
    * Flags for the Doggo format.
    * Bit 0: Detailed map (contains block names). If off, contains no block names.
    * Bit 1: Unknown blocks should be considered walkable.
  7. PAD32 - Reserved
    * Reserved for future use.

  MAP DATA HEADER
  1. UINT8 - Map name length
  2. STRING - Map name
  3. UINT8 - Map width (X)
  4. UINT8 - Map height (Y)
  5. UINT8 - Map depth (Z)
  6. UINT16 - Run Count
    * Map data is stored as run-length encoded (RLE) data.
  7. UINT8 - Waypoint count
  8. INT8 - Walkable cost
    * The cost of walking on the map. Lower values are easier to walk on.
  9. INT8 - Unknown cost
    * The cost of walking on unknown blocks. Lower values are easier to walk on. Only relevant if Bit 1 of the flags is set.
  10. PAD32 - Reserved
    * Reserved for future use.

  BODY
  1. WAYPOINT[] - Waypoints (See WAYPOINT definition)
  2. RUN[] - Run-length encoded map data (See RUN definition)

  WAYPOINT
  1. UINT8 - Waypoint ID length
  2. STRING - Waypoint ID
  3. UINT8 - Waypoint display name length
  4. STRING - Waypoint display name
  5. UINT8 - Waypoint X position
  6. UINT8 - Waypoint Y position
  7. UINT8 - Waypoint Z position
  8. PAD32 - Reserved
    * Reserved for future use.
    * In theory, there shouldn't be many waypoints, so it should be fine to store 32 bytes of empty data per waypoint.

  RUN - BASIC
  1. UINT8 - X position
  2. UINT8 - Y position
  3. UINT8 - Z position
  4. UINT8 - Run length
  5. UINT8 - Flags
    * Bit 0: Walkable
    * Rest of the bits are reserved for future use
    * We do this so we don't have to do any manipulation of the data later on to align it.
  RUN - DETAILED
  5. UINT8 - Block ID length
  6. STRING - Block ID



  MAXIMUM file length: basic, no waypoints
    MAIN HEADER
      1. CONST - "DOGMAP"
      2. UINT8 - Major version number
      3. UINT8 - Minor version number
      4. UINT8 - Patch version number
      5. UINT16 - Build number
      6. UINT8 - Flags
      7. PAD32 - Reserved
    total 6 + 1 + 1 + 1 + 2 + 1 + 4 bytes
    total 16 bytes

    MAP DATA HEADER
      1. UINT8 - Map name length
      2. STRING - Map name
      3. UINT8 - Map width (X)
      4. UINT8 - Map height (Y)
      5. UINT8 - Map depth (Z)
      6. UINT16 - Run Count
      7. UINT8 - Waypoint count
      8. INT8 - Walkable cost
      9. INT8 - Unknown cost
      10. PAD32 - Reserved
    total 1 + 256 + 1 + 1 + 1 + 2 + 1 + 1 + 1 + 4
    total 269 bytes

    WAYPOINTS
    -

    RUNS
      1. UINT8 - X position
      2. UINT8 - Y position
      3. UINT8 - Z position
      4. UINT8 - Run length
      5. UINT8 - Flags
    total 1 + 1 + 1 + 1 + 1
    total 5 bytes
    use 256x256x256
    total 16,777,216 * 5 bytes
    total 83,886,080 bytes
  grand total 83,886,365 bytes
  or 83.89 MB

  Adding in waypoints...
    WAYPOINT
      1. UINT8 - Waypoint ID length
      2. STRING - Waypoint ID
      3. UINT8 - Waypoint display name length
      4. STRING - Waypoint display name
      5. UINT8 - Waypoint X position
      6. UINT8 - Waypoint Y position
      7. UINT8 - Waypoint Z position
      8. PAD32 - Reserved
    total 1 + 256 + 1 + 256 + 1 + 1 + 1 + 4
    total 521 bytes
    use 256
    total 256 * 521 bytes
    total 133,376 bytes
  new grand total is 83,886,365 + 133,376 = 84,019,741 bytes
  or 84.02 MB

  Adding in detailed data...
    RUN - DETAILED
      5. UINT8 - Block ID length
      6. STRING - Block ID
    total 1 + 256
    total 257 bytes
    use 256x256x256
    total 16,777,216 * 257 bytes
    total 4,311,744,512 bytes
  new grand total is 84,019,741 + 4,311,744,512 = 4,395,764,253 bytes
  or 4.40 GB

  Size expected to be much smaller.
  This is if we use a map which is a checkerboard pattern of
  walkable/unwalkable, so is not very efficient for our RLE encoding.
]]