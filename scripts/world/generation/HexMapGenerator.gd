class_name HexMapGenerator
extends RefCounted

## Builds the full HexCell grid in these passes:
##   1. Landmass     — every hex in bounds defaults to OCEAN; hexes inside
##                      BritishGeographyData's landmass silhouette get a
##                      REAL biome/elevation instead, sampled from open
##                      geographic data (RealTerrainSampler — OpenStreetMap
##                      land-cover + AWS/Mapzen elevation, baked offline by
##                      tools/geo_bake/bake_landcover.py) via
##                      _apply_real_terrain(), not a flat default. Falls
##                      back to the old flat MOORLAND/Perlin-noise default
##                      if the bake hasn't been run/committed
##                      (RealTerrainSampler.is_available() == false) so a
##                      fresh clone without the baked assets still boots.
##   2. Feature stamp — named geography (settlements, ranges, waterways,
##                      wetlands, farmland) from BritishGeographyData
##                      overrides the land layer. Ocean hexes are never
##                      targeted by a feature (every GeographyFeature's own
##                      hex_coords sit on land by construction).
##   3. Soil noise    — layered noise varies fertility within open
##                      countryside for the "granular soil fertility"
##                      requirement, independent of named regions.
##   4. Mountain passes — MountainPassCarver lowers the lowest saddle of any
##                      ridge that would otherwise seal walkable ground off
##                      entirely, now that Level 4 MOUNTAIN is impassable.
##   5. Partitioning  — DistrictPartitioner splits each hex into its
##                      civic/industrial/wilderness sub-districts.
## Kept separate from HexGridMap so the *algorithm* that populates the grid
## is swappable/testable independently of the *runtime container* that owns it.
##
## Real-data note: a hex's own biome_type does NOT flip to WATERWAY from a
## minority of real river/canal pixels sampled within it — deliberate,
## disclosed limitation (see _apply_real_terrain()'s own doc comment).
## That would re-introduce hex-tile-locking one layer down; real sub-hex
## river geometry is TerrainMeshView's job — the baked vector mesh carries
## the real OSM waterway polygons, unquantized and not cut at a hex edge.

## Stamping order, low to high priority — later entries win where features
## overlap a hex. Settlements are stamped last on purpose: real cities are
## built over/across rivers, canals and farmland (Manchester on its Ship
## Canal, London straddling the Thames), so a settlement's identity should
## always win its own footprint regardless of what geography sits under it.
const _FEATURE_STAMP_ORDER: Array[GeographyFeature.FeatureType] = [
	GeographyFeature.FeatureType.MOUNTAIN_RANGE,
	GeographyFeature.FeatureType.WETLAND,
	GeographyFeature.FeatureType.FARMLAND,
	GeographyFeature.FeatureType.INDUSTRIAL_BLIGHT,
	GeographyFeature.FeatureType.WATERWAY,
	GeographyFeature.FeatureType.SETTLEMENT,
]

## Public — SubHexSoilQuery (Sub-Hex Mechanical Layer Phase 3) reruns this
## exact same noise field at sub-hex granularity instead of redeclaring its
## own copy of these numbers, so macro and sub-hex soil derivation can never
## drift apart.
const SOIL_NOISE_SEED: int = 1891
const SOIL_NOISE_FREQUENCY: float = 0.35
const SOIL_NOISE_LUSH_THRESHOLD: float = 0.35
const SOIL_NOISE_DESOLATE_THRESHOLD: float = -0.35

var _elevation_noise: FastNoiseLite
var _soil_noise: FastNoiseLite

func _init() -> void:
	_elevation_noise = FastNoiseLite.new()
	_elevation_noise.seed = 1890
	_elevation_noise.frequency = 0.15
	_elevation_noise.noise_type = FastNoiseLite.TYPE_PERLIN

	_soil_noise = FastNoiseLite.new()
	_soil_noise.seed = SOIL_NOISE_SEED
	_soil_noise.frequency = SOIL_NOISE_FREQUENCY
	_soil_noise.noise_type = FastNoiseLite.TYPE_PERLIN

func generate() -> Dictionary:
	var cells: Dictionary = {}  # Vector2i -> HexCell
	var bounds := BritishGeographyData.MAP_BOUNDS
	var land := BritishGeographyData.get_landmass_hexes()

	for q in range(bounds.position.x, bounds.position.x + bounds.size.x):
		for r in range(bounds.position.y, bounds.position.y + bounds.size.y):
			var coord := Vector2i(q, r)
			var cell := HexCell.new(coord)
			if land.has(coord):
				_apply_real_terrain(cell, coord)
			else:
				cell.biome_type = GameEnums.BiomeType.OCEAN
				cell.soil_fertility = GameEnums.SoilFertility.NOT_ARABLE
				cell.elevation = 0.0
			cells[coord] = cell

	var features := BritishGeographyData.get_features()
	for feature_type in _FEATURE_STAMP_ORDER:
		for feature in features:
			if feature.feature_type == feature_type:
				_apply_feature(cells, feature)

	_apply_soil_noise(cells)
	# After every elevation-setting pass (real terrain + the MOUNTAIN_RANGE
	# feature stamp's own elevation floor) and before anything reads
	# passability: design_doc.md §5 makes Level 4 impassable, and this lowers
	# the ridge saddles that would otherwise seal walkable ground behind it.
	# See MountainPassCarver's own doc comment.
	MountainPassCarver.carve(cells)

	var partitioner := DistrictPartitioner.new()
	for cell: HexCell in cells.values():
		partitioner.partition_cell(cell)

	return cells

func _base_elevation(coord: Vector2i) -> float:
	var n := _elevation_noise.get_noise_2d(coord.x, coord.y)
	return clampf((n + 1.0) * 0.5, 0.0, 1.0)

## Real-data-driven default for every land hex, replacing the old flat
## MOORLAND/POOR + Perlin-noise elevation default. Samples a 5x5 real-
## world grid across the hex's own footprint (RealTerrainSampler,
## OpenStreetMap land-cover + AWS/Mapzen elevation, baked offline by
## tools/geo_bake/bake_landcover.py) and takes the plurality biome + mean
## elevation. HIGHLAND classification (and its ESCARPMENT terrain_feature)
## already comes baked into the source data itself — the Python bake
## applies a real-elevation threshold directly when producing
## landcover.png, so no separate elevation-threshold pass is needed here
## (a simpler, single-source-of-truth design than originally sketched,
## which imagined doing that check in GDScript instead).
##
## Falls back to the old flat MOORLAND/Perlin-noise default if the bake
## hasn't been run/committed (RealTerrainSampler.is_available() == false)
## — a fresh clone without the (large, binary) baked assets still boots
## into a playable, if data-poor, map rather than erroring.
##
## Deliberate, disclosed limitation: does NOT let a minority of real
## river/canal samples flip this hex's own biome_type to WATERWAY — see
## this file's own class doc comment above for why.
func _apply_real_terrain(cell: HexCell, coord: Vector2i) -> void:
	var sample := RealTerrainSampler.majority_biome(coord) if RealTerrainSampler.is_available() else {}
	if sample.is_empty():
		cell.biome_type = GameEnums.BiomeType.MOORLAND
		cell.soil_fertility = GameEnums.SoilFertility.POOR
		cell.elevation = _base_elevation(coord)
		return

	cell.biome_type = sample["biome_type"]
	cell.elevation = sample["elevation"]
	match cell.biome_type:
		GameEnums.BiomeType.URBAN:
			cell.soil_fertility = GameEnums.SoilFertility.NOT_ARABLE
		GameEnums.BiomeType.INDUSTRIAL:
			cell.soil_fertility = GameEnums.SoilFertility.DESOLATE
		GameEnums.BiomeType.HIGHLAND:
			cell.terrain_feature = GameEnums.TerrainFeature.ESCARPMENT
			cell.soil_fertility = GameEnums.SoilFertility.POOR
		GameEnums.BiomeType.WETLAND:
			cell.terrain_feature = GameEnums.TerrainFeature.MARSH
			cell.soil_fertility = GameEnums.SoilFertility.DESOLATE
		GameEnums.BiomeType.WATERWAY:
			var water_feature: GameEnums.TerrainFeature = sample.get("water_feature_type", GameEnums.TerrainFeature.RIVER)
			cell.terrain_feature = water_feature if water_feature != GameEnums.TerrainFeature.NONE else GameEnums.TerrainFeature.RIVER
			cell.soil_fertility = GameEnums.SoilFertility.POOR
		GameEnums.BiomeType.FARMLAND:
			cell.soil_fertility = GameEnums.SoilFertility.LUSH  ## overwritten by _apply_soil_noise() below, matches its own existing convention
		GameEnums.BiomeType.WOODLAND, GameEnums.BiomeType.HEATHLAND:
			cell.soil_fertility = GameEnums.SoilFertility.NOT_ARABLE  ## Granularity pass: neither is tilled ground — same "not applicable" bucket as URBAN, not a low-quality farmland rating.
		_:  # MOORLAND
			cell.soil_fertility = GameEnums.SoilFertility.POOR  ## overwritten by _apply_soil_noise() below

func _apply_feature(cells: Dictionary, feature: GeographyFeature) -> void:
	for coord in feature.hex_coords:
		if not cells.has(coord):
			continue
		var cell: HexCell = cells[coord]
		# Real coastline data (BritishGeographyData, re-baked from Natural
		# Earth) means a hand-placed feature anchor/line/disk can legitimately
		# clip a hex or two of open sea at this resolution (e.g. a marsh disk
		# centered right at a real estuary's edge) — unlike the map's own
		# settlements, which the baking pipeline already snaps onto real land
		# before they ever get here, non-settlement features aren't guaranteed
		# to stay off the water. Skip rather than let a farmland/wetland/
		# mountain stamp silently paint over an OCEAN cell.
		if cell.biome_type == GameEnums.BiomeType.OCEAN and feature.feature_type != GeographyFeature.FeatureType.SETTLEMENT:
			continue
		cell.region_name = feature.feature_name
		match feature.feature_type:
			GeographyFeature.FeatureType.SETTLEMENT:
				cell.is_settlement = true
				cell.biome_type = GameEnums.BiomeType.URBAN
				cell.soil_fertility = GameEnums.SoilFertility.NOT_ARABLE
			GeographyFeature.FeatureType.MOUNTAIN_RANGE:
				# Elevation is NOT overridden here. This used to do
				# `cell.elevation = maxf(cell.elevation, 0.75)` — a flat 750 m
				# stamped along each range's hand-drawn hex line, which clears
				# ElevationLevels' 600 m MOUNTAIN threshold and so made every
				# hex on the line impassable to units, vehicles and hordes
				# alike (design_doc.md §5).
				#
				# Measured against the baked z12 elevation, taking the PEAK of a
				# 9x9 sample per hex (the most generous reading):
				#   Pennines   25 hexes,  8 genuinely >= 600 m, median peak 577 m
				#   Chilterns   8 hexes,  0 genuinely >= 600 m, median peak 240 m
				#   Cotswolds  11 hexes,  0 genuinely >= 600 m, median peak 225 m
				# The Chilterns and Cotswolds are chalk and limestone
				# escarpments a few hundred metres high; the override was
				# putting impassable walls across southern England, while the
				# genuinely mountainous Lake District, Snowdonia and Highlands
				# carried no such stamp at all because no hand-drawn line
				# reaches them. Real sampled elevation now decides the height
				# band everywhere, so the high Pennine hexes stay Level 4 and
				# the rest read as the high, slow ground they actually are.
				#
				# The rest of the stamp stays: these ARE upland, and biome/
				# terrain_feature/soil are not what the elevation data answers.
				cell.biome_type = GameEnums.BiomeType.HIGHLAND
				cell.terrain_feature = GameEnums.TerrainFeature.ESCARPMENT
				cell.soil_fertility = GameEnums.SoilFertility.POOR
			GeographyFeature.FeatureType.WATERWAY:
				cell.biome_type = GameEnums.BiomeType.WATERWAY
				cell.terrain_feature = GameEnums.TerrainFeature.CANAL if feature.waterway_is_canal else GameEnums.TerrainFeature.RIVER
				cell.waterway_name = feature.feature_name
			GeographyFeature.FeatureType.WETLAND:
				cell.biome_type = GameEnums.BiomeType.WETLAND
				cell.terrain_feature = GameEnums.TerrainFeature.PEAT_BOG if feature.feature_name == "Chat Moss" else GameEnums.TerrainFeature.MARSH
				cell.soil_fertility = GameEnums.SoilFertility.DESOLATE
			GeographyFeature.FeatureType.FARMLAND:
				cell.biome_type = GameEnums.BiomeType.FARMLAND
				cell.soil_fertility = GameEnums.SoilFertility.LUSH
			GeographyFeature.FeatureType.INDUSTRIAL_BLIGHT:
				cell.biome_type = GameEnums.BiomeType.INDUSTRIAL
				cell.soil_fertility = GameEnums.SoilFertility.DESOLATE

## Varies fertility within open countryside only — cities, water, mountains
## and wetlands keep the fixed soil rating their feature stamp gave them.
func _apply_soil_noise(cells: Dictionary) -> void:
	for cell: HexCell in cells.values():
		if cell.biome_type != GameEnums.BiomeType.MOORLAND and cell.biome_type != GameEnums.BiomeType.FARMLAND:
			continue
		var n := _soil_noise.get_noise_2d(cell.coord.x, cell.coord.y)
		if n > SOIL_NOISE_LUSH_THRESHOLD:
			cell.soil_fertility = GameEnums.SoilFertility.LUSH
		elif n < SOIL_NOISE_DESOLATE_THRESHOLD:
			cell.soil_fertility = GameEnums.SoilFertility.DESOLATE
		else:
			cell.soil_fertility = GameEnums.SoilFertility.POOR
