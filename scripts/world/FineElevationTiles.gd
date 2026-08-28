class_name FineElevationTiles
extends RefCounted

## Real elevation in metres at 30 m resolution, from the per-hex tiles
## tools/geo_bake/bake_fine_relief.py writes with --metres.
##
## Owns exactly one thing: turning a world position into a metres value out of
## those tiles. It does not classify terrain, does not fall back to the coarse
## raster, and does not decide what a caller should do with a missing tile —
## RealTerrainSampler and SubHexTerrainQuery own those questions and this is the
## narrow collaborator they read through.
##
## ## Why not just widen RealTerrainSampler
##
## That class already answers biome, terrain feature, coarse elevation and fine
## land-cover, and CLAUDE.md section 1 asks for a narrower collaborator rather
## than another responsibility on a wide class. The tile cache here also needs a
## bound that its fine land-cover cache does not have (see below), so sharing one
## cache would mean either leaking or evicting land-cover tiles for no reason.
##
## ## Wire format
##
## The same Terrarium RGB packing sample_at() already decodes for the coarse
## raster (metres = r * 256 + g + b / 256 - 32768), so there is no second decoder
## anywhere. The bake writes b as zero: nothing here wants Terrarium's 1/256 m
## fractional channel, and it is high-entropy noise that no compressor shrinks.
## Values are therefore quantised to whole metres, rounded rather than truncated.
##
## ## Values go NEGATIVE over water
##
## Terrarium tiles carry bathymetry, so a sea pixel returns real depth rather than
## zero or "no data" — measured against the source at z12: Liverpool Bay -11.9 m,
## mid Irish Sea -50.1 m, and -122 m at the deepest point of the baked corridor.
## The coarse elevation.png behaves identically, being the same source;
## RealTerrainSampler hides it only in its normalised "elevation" field, which
## clamps to 0..1, and its "elevation_m" is raw exactly like this.
##
## Anything comparing elevations across a coastline has to expect it. A canal
## gradient rule that assumed sea was 0 m would read the shoreline as a legal
## step, and a line-of-sight ray would pass under the water rather than over it.
##
## ## Origin snapping is load-bearing
##
## Tiles span TILE_WORLD_SIZE while hex centres sit closer together, so tiles
## overlap. The bake snaps every tile origin DOWN to a multiple of the pixel
## step, making all tiles subsets of one global sample lattice — two tiles
## covering the same ground then hold the identical value there. Reading them
## back with an unsnapped origin would undo that and return a value up to one
## pixel away from the one the bake wrote.
##
## RealTerrainSampler._sample_fine() deliberately does NOT snap, and is not
## wrong to: the land-cover tiles it reads come from bake_fine_tiles.py, which
## does not snap either. Two bakes, two lattices. Match the one you are reading.

const TILE_DIR: String = "res://assets/terrain_data/elevation_fine"

## 333 = HexCoord.SUB_HEX_GRID_N, one tile pixel per 30 m mechanical sub-cell
## exactly; must match bake_fine_relief.py's FINE_TILE_PIXELS.
const TILE_PIXELS: int = 333
const TILE_WORLD_SIZE: float = 1024.0  ## HexCoord.SUB_HEX_GRID_SPAN.
const WORLD_UNITS_PER_PIXEL: float = TILE_WORLD_SIZE / float(TILE_PIXELS)

## Each decoded tile is 333x333 RGB8 = ~325 KB, so an unbounded cache across the
## 3,876-hex corridor would strand ~1.3 GB. RealTerrainSampler._fine_tile_cache
## has exactly that shape and no bound; this does not copy the bug.
##
## 32 is sized to the access pattern rather than to a memory target: reads follow
## the camera and the live-hex set (camera hex + 6 neighbours, plus hexes holding
## player units or buildings), so a working set of a dozen or so tiles is normal
## and 32 absorbs a fast pan without thrashing. ~10 MB resident at the cap.
const MAX_CACHED_TILES: int = 32

## Vector2i -> Image, or null once confirmed absent. Misses are cached too, so a
## hex outside the baked corridor is stat-ed once rather than every query.
## Insertion-ordered, which is what makes the eviction below least-recently-used.
static var _cache: Dictionary = {}


## Top-left world position of a tile's first pixel, snapped to the global sample
## lattice. Must stay identical to bake_fine_relief.tile_origin_world() and to
## ReliefTileView.tile_origin(), which read the same lattice.
static func tile_origin(coord: Vector2i) -> Vector2:
	var centre := HexCoord.axial_to_world(coord)
	var step := TILE_WORLD_SIZE / float(TILE_PIXELS)
	return Vector2(
		floor((centre.x - TILE_WORLD_SIZE * 0.5) / step) * step,
		floor((centre.y - TILE_WORLD_SIZE * 0.5) / step) * step)


static func has_tile(coord: Vector2i) -> bool:
	return _tile_for(coord) != null


## Elevation in metres at `world_pos`, read from `coord`'s tile.
##
## Returns null — not 0.0 — when there is no tile for `coord`, or when
## `world_pos` falls outside the tile's own pixel bounds. Zero is a real
## elevation (every coastal hex is full of it), so a sentinel that a caller
## could mistake for data would be worse than a branch.
static func metres_at(coord: Vector2i, world_pos: Vector2) -> Variant:
	var image := _tile_for(coord)
	if image == null:
		return null
	var local := world_pos - tile_origin(coord)
	var px := int(local.x / WORLD_UNITS_PER_PIXEL)
	var py := int(local.y / WORLD_UNITS_PER_PIXEL)
	if px < 0 or py < 0 or px >= image.get_width() or py >= image.get_height():
		return null
	var color := image.get_pixelv(Vector2i(px, py))
	var r := int(round(color.r * 255.0))
	var g := int(round(color.g * 255.0))
	var b := int(round(color.b * 255.0))
	return float(r * 256 + g + b / 256.0) - 32768.0


static func clear_cache() -> void:
	_cache.clear()


static func cached_tile_count() -> int:
	return _cache.size()


static func _tile_for(coord: Vector2i) -> Image:
	if _cache.has(coord):
		var hit: Image = _cache[coord]
		## Re-inserting moves the key to the back of the insertion order, which is
		## what makes the eviction below LRU rather than first-loaded-first-out.
		_cache.erase(coord)
		_cache[coord] = hit
		return hit

	var path := "%s/%d_%d.png" % [TILE_DIR, coord.x, coord.y]
	var image: Image = null
	if FileAccess.file_exists(path):
		var loaded := Image.new()
		## Image.load() rather than ResourceLoader, matching RealTerrainSampler and
		## ReliefTileView: it bypasses the texture-import pipeline, which must not
		## be allowed to re-encode elevation bytes whose exact values are the data.
		##
		## This shares those two classes' export defect — Godot warns that loading a
		## res:// path as an image file will not work in an exported build, since
		## only the imported .ctex ships. Tracked as its own backlog item; fixing it
		## here for one of three readers would leave the other two broken and hide
		## the shared cause.
		if loaded.load(path) == OK:
			image = loaded

	if _cache.size() >= MAX_CACHED_TILES:
		_cache.erase(_cache.keys()[0])
	_cache[coord] = image
	return image
