# Dog
Dog fetches ore, and like a good boy he brings it back.

# Requirements
1. Block Scanner mounted on one of the turtle's sides.
2. Pickaxe mounted on the other side

# Usage
1. Run `wget run https://raw.githubusercontent.com/Fatboychummy-CC/Dog/refresh/installer.lua`
2. Confirm the installer's prompts.
3. Run `dog.lua`

# Command-line arguments
```
dog [max_offset=8] [flags/options]
```
## Positional arguments

### `max_offset`
The maximum distance the turtle will travel horizontally from its starting position. Defaults to 8.

## Flags

### `-h`, `--help`
Prints help message and exits.

### `-v`, `--version`
Prints version information and exits.

### `-f`, `--fuel`
The turtle will attempt to refuel itself with any fuel items it has in its 
inventory while dumping items at the end of its run.

## Options

### `--depth=<number>`
The maximum depth the turtle is allowed to dig to. Defaults to 512.

### `--loglevel=<debug|info|warn|error|fatal>`
The level of logging to use. Defaults to `info`.

### `--georange=<number>`
The range to use for the geoscanner, if using a geoscanner. Defaults to 8.

### `-l`, `--level`
Travel in a horizontal line at the current level. Useful for mining things like
clay and other surface ores when used in tandem with `include` or `only`.

It is recommended to use this option with a low `max_offset` value, so the 
turtle doesn't run off into the distance.

### Include/Exclude/Only
These options can be used together. The order they are parsed are as follows:

1. exclude
2. include
3. only

This way, if `only` is specified, it overrides both `exclude` and `include`.

Similarly, if `include` is specified, it will override exclusions.

Sample files can be found in the `test_files` directory. They are simply a lua
table containing either a list of block names, or block name->true pairs.

```lua
{
  "minecraft:stone"
}
```
```lua
{
  ["minecraft:stone"] = true,
}
```
Both of these styles are valid.

#### `--exclude=<file>`
A file containing blocks to exclude from mining. Do note that this will not make
the turtle fully avoid the blocks. If the turtle is mining towards something,
it will still mine through the excluded blocks if they are in the way.

In future, I may add a `--avoid` option that will make the turtle avoid blocks,
but that will require a simple pathfinding algorithm to be implemented, which
seems out of scope for something as simple as Dog. If enough people want it
though, I'll add it.

#### `--include=<file>`
A file containing blocks to include in mining.

#### `--only=<file>`
A file containing blocks that should be the only ones mined.