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
