class_name ZombiePopulationData
extends RefCounted

## Read side of tools/geo_bake/bake_population.py: `total_zombie_pop` per
## macro-hex, baked from real 1890s settlement population.
##
## design_doc.md §2.1 makes this the static half of the infestation model —
## `zombie_count` is the one mutable number per hex, and this is the capacity
## it is a ratio of. Because capacity **is** the difficulty curve (decisions.md
## D3), a London hex holding order 5e5 and a Highland hex holding the 1,000
## floor is what gates where the player can go and when, with no hand-authored
## region locks.
##
## **Per macro-hex on purpose, not a coarse read that should have been sub-hex.**
## CLAUDE.md §3 exists to stop a gameplay decision being answered off a single
## value for 25 square miles when `SubHexTerrainQuery` could answer it at 30 m.
## This is the documented exception: design_doc.md §2.1 defines capacity as
## "*(int, static per hex)*" and infestation as a whole-hex ratio, so one value
## per hex IS the model, not a flattening of a finer one. Do not "fix" it into
## a sub-hex read.
##
## Wire format, repeated verbatim from bake_population.encode(). Both sides
## state it and must change in lockstep — the same contract
## TerrainMeshChunkData/vector_mesh_format.py already keep, for the same reason:
## a silent disagreement decodes as plausible garbage rather than an error.
##
##   off  size  type     field
##     0     4  bytes    magic "ZPOP"
##     4     2  uint16   format version (= 1)
##     6     2  uint16   reserved (= 0)
##     8     4  int32    q0  -- MAP_BOUNDS.position.x
##    12     4  int32    r0  -- MAP_BOUNDS.position.y
##    16     4  uint32   width  -- MAP_BOUNDS.size.x
##    20     4  uint32   height -- MAP_BOUNDS.size.y
##    24     4  uint32   floor  -- design_doc.md §2.1's 1,000
##    28     4  uint32   reserved (= 0)
##    32        width*height*4  uint32 capacity, r-major then q
##
## Little-endian throughout, matching PackedByteArray's decode_* helpers.
##
## **0 and the floor are different answers and both are real.** 0 means the hex
## is open sea and can hold no zombies at all; 1,000 is the emptiest inhabited
## hex in Britain. capacity_for() returns 0 for a hex outside the baked
## rectangle as well, so callers that care must ask is_available() first — the
## same "never substitute a plausible value for missing data" rule
## RealTerrainSampler.sample_at() follows by returning {}.
##
## Read once into a PackedInt32Array at first use — 154x179 hexes is 110 KB, so
## there is no tile cache to bound here the way FineElevationTiles needs one.
##
## FileAccess, not ResourceLoader: this is raw binary, not a Godot resource.
## It inherits TerrainMeshChunkData's own export caveat — an exported build only
## ships it if the export preset's non-resource include filter covers *.zpop.

## "ZPOP". A plain int Array, not a PackedByteArray — GDScript rejects
## `PackedByteArray([...])` in a const as "not a constant expression", the same
## constraint TerrainMeshChunkData.MAGIC documents.
const MAGIC: Array[int] = [0x5A, 0x50, 0x4F, 0x50]
const SUPPORTED_VERSION: int = 1
const HEADER_SIZE: int = 32
const DATA_PATH: String = "res://assets/terrain_data/zombie_population.zpop"

## design_doc.md §2.1's floor of 1,000, used ONLY when the bake is missing.
## Every baked hex already carries at least this much, so the live value comes
## out of the file's own header (see population_floor()); this constant exists
## so a fresh clone with no baked asset still has one number to fall back to
## rather than treating the whole island as empty.
const FALLBACK_FLOOR: int = 1000

static var _loaded: bool = false
static var _capacity: PackedInt32Array = PackedInt32Array()
static var _origin: Vector2i = Vector2i.ZERO
static var _size: Vector2i = Vector2i.ZERO
static var _floor: int = 0


## True once the bake has been read successfully. Callers that must not
## substitute a wrong number for a missing one check this first;
## HexMapGenerator falls back to the floor for the whole map when it is false,
## so a fresh clone without the baked asset still boots into a playable map.
static func is_available() -> bool:
	_ensure_loaded()
	return not _capacity.is_empty()


## `total_zombie_pop` for one hex: how many zombies it can hold at 100%
## infestation. 0 for open sea, for a hex outside MAP_BOUNDS, and when the bake
## is missing entirely.
static func capacity_for(coord: Vector2i) -> int:
	_ensure_loaded()
	if _capacity.is_empty():
		return 0
	var local := coord - _origin
	if local.x < 0 or local.y < 0 or local.x >= _size.x or local.y >= _size.y:
		return 0
	return _capacity[local.y * _size.x + local.x]


## design_doc.md §2.1's floor, as the bake actually wrote it. Read from the file
## rather than restated as a GDScript const, so the two cannot disagree about
## what "the emptiest hex in Britain" holds — FALLBACK_FLOOR only when there is
## no file to read it from.
static func population_floor() -> int:
	_ensure_loaded()
	return _floor if not _capacity.is_empty() else FALLBACK_FLOOR


## The axial rectangle the bake covers, for tooling that has to walk exactly
## the hexes real data exists for rather than re-deriving MAP_BOUNDS.
static func baked_bounds() -> Rect2i:
	_ensure_loaded()
	return Rect2i(_origin, _size)


## `_loaded` is set before the load is attempted, so a missing or malformed
## file is reported once and not re-parsed on every query — same lazy-load
## shape as FineElevationTiles/RealTerrainSampler.
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("ZombiePopulationData: %s is missing — every hex falls back to the floor. Bake it with: python tools/geo_bake/bake_population.py" % DATA_PATH)
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("ZombiePopulationData: cannot open %s (error %d)" % [DATA_PATH, FileAccess.get_open_error()])
		return
	var bytes := file.get_buffer(file.get_length())
	file.close()
	_decode(bytes)


static func _decode(bytes: PackedByteArray) -> void:
	if bytes.size() < HEADER_SIZE:
		push_error("ZombiePopulationData: %s is %d bytes, shorter than the %d-byte header" % [DATA_PATH, bytes.size(), HEADER_SIZE])
		return
	for i in 4:
		if bytes[i] != MAGIC[i]:
			push_error("ZombiePopulationData: %s has bad magic, expected \"ZPOP\"" % DATA_PATH)
			return
	var version := bytes.decode_u16(4)
	if version != SUPPORTED_VERSION:
		push_error("ZombiePopulationData: %s is format version %d, this build reads %d" % [DATA_PATH, version, SUPPORTED_VERSION])
		return

	var origin := Vector2i(bytes.decode_s32(8), bytes.decode_s32(12))
	var size := Vector2i(bytes.decode_u32(16), bytes.decode_u32(20))
	var floor_value := int(bytes.decode_u32(24))

	# Validate the declared size against the real file BEFORE indexing, so a
	# truncated bake is one error rather than a read running off the end.
	var expected := HEADER_SIZE + size.x * size.y * 4
	if bytes.size() != expected:
		push_error("ZombiePopulationData: %s is %d bytes but its header implies %d (%dx%d hexes)" % [DATA_PATH, bytes.size(), expected, size.x, size.y])
		return
	# The bake covers MAP_BOUNDS exactly. A mismatch means the coastline was
	# re-baked at a different extent and the population bake was not re-run —
	# loud, because silently reading a stale rectangle offsets every city.
	if Rect2i(origin, size) != BritishGeographyData.MAP_BOUNDS:
		push_error("ZombiePopulationData: %s covers %s but BritishGeographyData.MAP_BOUNDS is %s — re-run tools/geo_bake/bake_population.py" % [DATA_PATH, Rect2i(origin, size), BritishGeographyData.MAP_BOUNDS])
		return

	var values := PackedInt32Array()
	values.resize(size.x * size.y)
	var offset := HEADER_SIZE
	for i in values.size():
		values[i] = int(bytes.decode_u32(offset))
		offset += 4

	_origin = origin
	_size = size
	_floor = floor_value
	_capacity = values


## Drops the cached read so a test can re-load. Nothing in the game calls this —
## the bake is static data and does not change at runtime.
static func reset_cache_for_test() -> void:
	_loaded = false
	_capacity = PackedInt32Array()
	_origin = Vector2i.ZERO
	_size = Vector2i.ZERO
	_floor = 0
