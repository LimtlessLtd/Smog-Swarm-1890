class_name RealTerrainSampler
extends RefCounted

## Real-world land-cover + elevation lookup, sampled from two baked
## whole-map-aligned PNGs (tools/geo_bake/bake_landcover.py's output,
## res://assets/terrain_data/landcover.png + elevation.png). Same lazy-
## load/cache convention as TerrainVisuals/BuildingVisuals/PropVisuals.
##
## Does NOT recompute BritishGeographyData's existing coastline/named-
## feature data — that bake's own lon/lat<->hex transform was never
## committed (see tools/geo_bake/geo_projection.py's own doc comment) and
## re-deriving it exactly is neither possible nor necessary. This class
## instead answers "what does real open geographic data say about the
## biome/elevation at THIS EXISTING hex position," using a freshly-fit
## affine (also in geo_projection.py, ported here) calibrated against the
## 17 named anchors' real-world coordinates. A few hex-radii of calibration
## slack is fine — it only needs to land on roughly the right real region,
## since real land-cover data varies smoothly at a much broader scale than that.
##
## Wire format (landcover.png), decoupled from GameEnums.BiomeType's raw
## enum ordinals — those have been reordered before and must never silently
## corrupt baked data if reordered again:
##   R = biome code (0=MOORLAND,1=FARMLAND,2=URBAN,3=INDUSTRIAL,
##                    4=WETLAND,5=WATERWAY,6=HIGHLAND)
##   G = terrain_feature code (0=NONE,1=RIVER,2=CANAL,3=MARSH,
##                              4=PEAT_BOG,5=ESCARPMENT)
##   B = reserved, always 0
## elevation.png: Terrarium RGB encoding of real elevation in metres
##   (elevation_m = R*256 + G + B/256 - 32768), same scheme the source
##   AWS/Mapzen Terrain Tiles ship in.
##
## Image.load_from_file() (NOT load()/ResourceLoader) is used deliberately
## — it bypasses Godot's texture-import/compression pipeline, which cannot
## be verified from this dev environment and must not be allowed to lossily
## mangle classification data that depends on exact byte values.

## Must match tools/geo_bake/bake_landcover.py's WORLD_UNITS_PER_PIXEL
## exactly — a plain literal, not derived from HEX_SIZE, since it's an
## independent bake-resolution choice, not a geometric identity.
const WORLD_UNITS_PER_PIXEL: float = 90.0

## Real elevation (metres) mapped to HexCell.elevation's documented
## 0.0..1.0 "sea level .. highest peaks" scale. 1000m comfortably covers
## real English/Welsh terrain (Cross Fell ~893m) with room for Scottish
## Highlands data; clamped above that rather than rescaling the whole
## game's elevation scale for a few outlier summits most play won't reach
## (Scotland/Wales are hard-gated content).
const ELEVATION_METRES_AT_SCALE_TOP: float = 1000.0

const _LANDCOVER_PATH: String = "res://assets/terrain_data/landcover.png"
const _ELEVATION_PATH: String = "res://assets/terrain_data/elevation.png"

## The baked rasters cover only the actually-playable core corridor
## (Manchester/Midlands/London), NOT the full BritishGeographyData.MAP_BOUNDS,
## most of which is Wales/Scotland/Ireland (hard-gated, unreachable in the
## current build). Must match tools/geo_bake/bake_landcover.py's
## CORRIDOR_Q/CORRIDOR_R exactly. A hex outside this range has no baked
## data at all — sample_at()/majority_biome() return {} for it (NOT
## clamped to the nearest edge pixel, which would silently substitute
## wrong data); HexMapGenerator/SubHexGroundView both treat an empty result
## as "fall back to the flat default."
const _CORRIDOR_Q: Vector2i = Vector2i(55, 105)
const _CORRIDOR_R: Vector2i = Vector2i(85, 160)

const _BIOME_BY_CODE: Array[GameEnums.BiomeType] = [
	GameEnums.BiomeType.MOORLAND,
	GameEnums.BiomeType.FARMLAND,
	GameEnums.BiomeType.URBAN,
	GameEnums.BiomeType.INDUSTRIAL,
	GameEnums.BiomeType.WETLAND,
	GameEnums.BiomeType.WATERWAY,
	GameEnums.BiomeType.HIGHLAND,
	# Appended at indices 7/8 to match bake_landcover.py's own append-only
	# _BIOME_CODE dict exactly — a raster baked before this addition
	# doesn't contain these codes (falls back to MOORLAND/FARMLAND). This
	# array must stay index-aligned with the Python dict, not with
	# GameEnums.BiomeType's own ordinals.
	GameEnums.BiomeType.WOODLAND,
	GameEnums.BiomeType.HEATHLAND,
]
const _FEATURE_BY_CODE: Array[GameEnums.TerrainFeature] = [
	GameEnums.TerrainFeature.NONE,
	GameEnums.TerrainFeature.RIVER,
	GameEnums.TerrainFeature.CANAL,
	GameEnums.TerrainFeature.MARSH,
	GameEnums.TerrainFeature.PEAT_BOG,
	GameEnums.TerrainFeature.ESCARPMENT,
]

static var _landcover_image: Image = null
static var _elevation_image: Image = null
static var _images_loaded: bool = false
static var _raster_origin_world: Vector2 = Vector2.ZERO
static var _origin_computed: bool = false

## True once both baked images have loaded successfully — callers (e.g.
## HexMapGenerator) use this to fall back to a flat default rather than
## sampling garbage if the bake hasn't been run/committed yet.
static func is_available() -> bool:
	_ensure_loaded()
	return _landcover_image != null and _elevation_image != null

static func _ensure_loaded() -> void:
	if _images_loaded:
		return
	_images_loaded = true
	if ResourceLoader.exists(_LANDCOVER_PATH) or FileAccess.file_exists(_LANDCOVER_PATH):
		var img := Image.new()
		if img.load(_LANDCOVER_PATH) == OK:
			_landcover_image = img
	if FileAccess.file_exists(_ELEVATION_PATH):
		var img2 := Image.new()
		if img2.load(_ELEVATION_PATH) == OK:
			_elevation_image = img2

## Same corner-based extent calculation as bake_landcover.py's own
## world_extent_corners(_CORRIDOR_Q, _CORRIDOR_R) — the min corner of the
## baked corridor (NOT the full MAP_BOUNDS) under HexCoord.axial_to_world().
## Computed once, cached; derived rather than a hand-copied literal, so it
## can't drift out of sync if the corridor range ever changes.
static func _ensure_origin() -> void:
	if _origin_computed:
		return
	_origin_computed = true
	var min_x := INF
	var min_y := INF
	for q in [_CORRIDOR_Q.x, _CORRIDOR_Q.y]:
		for r in [_CORRIDOR_R.x, _CORRIDOR_R.y]:
			var world := HexCoord.axial_to_world(Vector2i(q, r))
			min_x = minf(min_x, world.x)
			min_y = minf(min_y, world.y)
	_raster_origin_world = Vector2(min_x, min_y)

## Returns null (not a clamped-to-edge Vector2i) if world_pos falls outside
## the baked raster's actual coverage — the caller must treat that as "no
## data," never silently sample the nearest edge pixel as if it were real
## data for a distant, differently-classified real-world location.
static func _pixel_for_world(world_pos: Vector2, image: Image) -> Variant:
	_ensure_origin()
	var px := int((world_pos.x - _raster_origin_world.x) / WORLD_UNITS_PER_PIXEL)
	var py := int((world_pos.y - _raster_origin_world.y) / WORLD_UNITS_PER_PIXEL)
	if px < 0 or py < 0 or px >= image.get_width() or py >= image.get_height():
		return null
	return Vector2i(px, py)

## Single-point sample. Returns {} if baked data isn't available or
## world_pos falls outside the baked corridor's coverage.
static func sample_at(world_pos: Vector2) -> Dictionary:
	_ensure_loaded()
	if _landcover_image == null or _elevation_image == null:
		return {}
	var lc_px_v: Variant = _pixel_for_world(world_pos, _landcover_image)
	if lc_px_v == null:
		return {}
	var lc_px: Vector2i = lc_px_v
	var lc_color := _landcover_image.get_pixelv(lc_px)
	var biome_code := int(round(lc_color.r * 255.0))
	var feature_code := int(round(lc_color.g * 255.0))

	var el_px_v: Variant = _pixel_for_world(world_pos, _elevation_image)
	if el_px_v == null:
		return {}
	var el_px: Vector2i = el_px_v
	var el_color := _elevation_image.get_pixelv(el_px)
	var r := int(round(el_color.r * 255.0))
	var g := int(round(el_color.g * 255.0))
	var b := int(round(el_color.b * 255.0))
	var elevation_m := float(r * 256 + g + b / 256.0) - 32768.0

	return {
		"biome_type": _BIOME_BY_CODE[biome_code] if biome_code < _BIOME_BY_CODE.size() else GameEnums.BiomeType.MOORLAND,
		"terrain_feature": _FEATURE_BY_CODE[feature_code] if feature_code < _FEATURE_BY_CODE.size() else GameEnums.TerrainFeature.NONE,
		"elevation_m": elevation_m,
		"elevation": clampf(elevation_m / ELEVATION_METRES_AT_SCALE_TOP, 0.0, 1.0),
	}

## Samples an n x n grid centred on a hex's world position, spanning its
## own real-world footprint (HexCoord.HEX_SIZE radius). Returns an Array of
## n*n Dictionaries (sample_at()'s own shape), row-major. Prefers a fine
## per-hex tile when one has been baked for `coord` (see "Fine per-hex
## tiles" below) — this is SubHexGroundView's own call site, gated to only
## exist for Tactical-hydrated/nearby hexes (LocalDetailManager's existing
## proximity system), so fine detail streams in "only when you're nearby"
## for free, riding on that existing mechanism.
static func sample_grid(coord: Vector2i, n: int) -> Array:
	var center := HexCoord.axial_to_world(coord)
	var result: Array = []
	if n <= 1:
		result.append(sample_at_hex(coord, center))
		return result
	var span := HexCoord.SUB_HEX_GRID_SPAN  # Shared with SubHexGroundView's own render grid — see that constant's own doc comment (HexCoord.gd).
	var step := span / float(n - 1)
	var start := -span * 0.5
	for row in range(n):
		for col in range(n):
			var offset := Vector2(start + col * step, start + row * step)
			var world_pos := center + offset
			result.append(sample_at_hex(coord, world_pos))
	return result

## Single-point version of the fine-tile-preferring choice sample_grid()
## already makes per hex — for callers that need one exact position rather
## than a whole grid (SubHexTerrainQuery, Sub-Hex Mechanical Layer Phase
## 1a) without losing fine-tile fidelity by calling the coarse sample_at()
## alone. `world_pos` need not be `coord`'s own center — any position is
## resolved against whichever hex's fine tile (if any) `coord` names.
static func sample_at_hex(coord: Vector2i, world_pos: Vector2) -> Dictionary:
	if _fine_tile_for(coord) != null:
		return _sample_fine(coord, world_pos)
	return sample_at(world_pos)

## --- Fine per-hex tiles -----------------------------------------------
##
## One small PNG per hex coordinate (res://assets/terrain_data/fine/
## <q>_<r>.png), baked at a much finer WORLD_UNITS_PER_PIXEL_FINE than the
## single whole-corridor landcover.png — resolves individual street
## blocks/field boundaries instead of an 877m/pixel blur. Keyed directly by
## hex coordinate (not an arbitrary world-space tile grid) because the
## thing that already decides "which hexes are worth this extra detail
## right now" is LocalDetailManager's existing Tactical-hydration radius
## (_current_detail_radius(), viewport-derived, not a fixed constant) —
## this rides on that existing system instead of a second proximity
## tracker. Every fine tile covers the same
## HexCoord.SUB_HEX_GRID_SPAN square sample_grid() already samples across,
## so swapping which raster answers a given sample is transparent to every caller.
##
## Sub-Hex Mechanical Layer Phase 1b: baked for the full 3,876-hex playable
## corridor (tools/geo_bake/bake_fine_tiles.py --corridor), not just a demo
## radius — every hex inside RealTerrainSampler._CORRIDOR_Q/_CORRIDOR_R now
## has a fine tile. A hex outside that corridor (Wales/Scotland/Ireland,
## hard-gated) still has none and falls back to the coarse landcover.png —
## nothing regresses, same graceful-fallback contract as before. Does NOT
## bake/read a fine elevation tile — elevation varies smoothly enough at
## this scale that the coarse elevation.png is unaffected; only biome/
## terrain_feature get the fine treatment.
const WORLD_UNITS_PER_PIXEL_FINE: float = 1024.0 / 333.0  ## Sub-Hex Mechanical Layer Phase 1b: 333 = HexCoord.SUB_HEX_GRID_N, one fine-tile pixel per 30m mechanical sub-hex cell exactly — must match tools/geo_bake/bake_fine_tiles.py's own FINE_TILE_PIXELS constant.
const _FINE_TILE_DIR: String = "res://assets/terrain_data/fine"

static var _fine_tile_cache: Dictionary = {}  ## Vector2i (hex coord) -> Image, or null once confirmed no tile exists — caching the miss too means a hex with no fine tile is only checked on disk once.

static func _fine_tile_for(coord: Vector2i) -> Image:
	if _fine_tile_cache.has(coord):
		return _fine_tile_cache[coord]
	var path := "%s/%d_%d.png" % [_FINE_TILE_DIR, coord.x, coord.y]
	var image: Image = null
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			image = img
	_fine_tile_cache[coord] = image
	return image

## Same {} "no data here" contract as sample_at() — the caller
## (sample_grid()) only calls this once it's confirmed a tile exists for
## `coord`, but a specific world_pos can still fall just outside this
## tile's own pixel bounds and correctly reports empty rather than reading
## garbage from an adjacent, differently-classified hex's data.
static func _sample_fine(coord: Vector2i, world_pos: Vector2) -> Dictionary:
	var image := _fine_tile_for(coord)
	if image == null:
		return {}
	var half_span := HexCoord.SUB_HEX_GRID_SPAN * 0.5
	var tile_origin := HexCoord.axial_to_world(coord) - Vector2(half_span, half_span)
	var local := world_pos - tile_origin
	var px := int(local.x / WORLD_UNITS_PER_PIXEL_FINE)
	var py := int(local.y / WORLD_UNITS_PER_PIXEL_FINE)
	if px < 0 or py < 0 or px >= image.get_width() or py >= image.get_height():
		return {}
	var color := image.get_pixelv(Vector2i(px, py))
	var biome_code := int(round(color.r * 255.0))
	var feature_code := int(round(color.g * 255.0))
	var elevation_sample := sample_at(world_pos)  ## Elevation always comes from the coarse raster — see this section's own doc comment.
	return {
		"biome_type": _BIOME_BY_CODE[biome_code] if biome_code < _BIOME_BY_CODE.size() else GameEnums.BiomeType.MOORLAND,
		"terrain_feature": _FEATURE_BY_CODE[feature_code] if feature_code < _FEATURE_BY_CODE.size() else GameEnums.TerrainFeature.NONE,
		"elevation_m": elevation_sample.get("elevation_m", 0.0),
		"elevation": elevation_sample.get("elevation", 0.0),
	}

## Majority-vote biome + mean elevation across a 5x5 sample grid for one
## hex — HexMapGenerator's per-hex real-data derivation. A coarser grid
## than sample_grid()'s Tactical-rendering use (SubHexGroundView) since
## this only needs to feed ONE scalar biome_type per hex, not visible
## sub-hex variation.
static func majority_biome(coord: Vector2i) -> Dictionary:
	var samples := sample_grid(coord, 5)
	var counts: Dictionary = {}
	var elevation_sum := 0.0
	var elevation_count := 0
	var water_feature_present := false
	var best_water_feature := GameEnums.TerrainFeature.NONE
	for sample in samples:
		if sample.is_empty():
			continue
		var biome: GameEnums.BiomeType = sample["biome_type"]
		counts[biome] = counts.get(biome, 0) + 1
		elevation_sum += sample["elevation"]
		elevation_count += 1
		# Real river/canal geometry does NOT get to flip this hex's own
		# biome_type to WATERWAY from a plurality vote (see
		# HexMapGenerator's own doc comment) — but sub-hex rendering still
		# needs to know a river crosses here, so track it separately
		# rather than discarding it.
		var feature: GameEnums.TerrainFeature = sample["terrain_feature"]
		if feature == GameEnums.TerrainFeature.RIVER or feature == GameEnums.TerrainFeature.CANAL:
			water_feature_present = true
			best_water_feature = feature

	if counts.is_empty():
		return {}

	var best_biome: GameEnums.BiomeType = GameEnums.BiomeType.MOORLAND
	var best_count := -1
	for biome in counts:
		if counts[biome] > best_count:
			best_count = counts[biome]
			best_biome = biome

	return {
		"biome_type": best_biome,
		"elevation": elevation_sum / maxf(1.0, float(elevation_count)),
		"has_water_feature": water_feature_present,
		"water_feature_type": best_water_feature,
	}
