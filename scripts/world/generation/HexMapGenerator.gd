class_name HexMapGenerator
extends RefCounted

## Builds the full HexCell grid in four passes:
##   1. Base layer   — every hex in bounds defaults to open moorland.
##   2. Feature stamp — named geography (settlements, ranges, waterways,
##                      wetlands, farmland) from BritishGeographyData
##                      overrides the base layer.
##   3. Soil noise    — layered noise varies fertility within open
##                      countryside for the "granular soil fertility"
##                      requirement, independent of named regions.
##   4. Partitioning  — DistrictPartitioner splits each hex into its
##                      civic/industrial/wilderness sub-districts.
## Kept separate from HexGridMap so the *algorithm* that populates the grid
## is swappable/testable independently of the *runtime container* that owns it.

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

var _elevation_noise: FastNoiseLite
var _soil_noise: FastNoiseLite

func _init() -> void:
	_elevation_noise = FastNoiseLite.new()
	_elevation_noise.seed = 1890
	_elevation_noise.frequency = 0.15
	_elevation_noise.noise_type = FastNoiseLite.TYPE_PERLIN

	_soil_noise = FastNoiseLite.new()
	_soil_noise.seed = 1891
	_soil_noise.frequency = 0.35
	_soil_noise.noise_type = FastNoiseLite.TYPE_PERLIN

func generate() -> Dictionary:
	var cells: Dictionary = {}  # Vector2i -> HexCell
	var bounds := BritishGeographyData.MAP_BOUNDS

	for q in range(bounds.position.x, bounds.position.x + bounds.size.x):
		for r in range(bounds.position.y, bounds.position.y + bounds.size.y):
			var coord := Vector2i(q, r)
			var cell := HexCell.new(coord)
			cell.biome_type = GameEnums.BiomeType.MOORLAND
			cell.soil_fertility = GameEnums.SoilFertility.POOR
			cell.elevation = _base_elevation(coord)
			cells[coord] = cell

	var features := BritishGeographyData.get_features()
	for feature_type in _FEATURE_STAMP_ORDER:
		for feature in features:
			if feature.feature_type == feature_type:
				_apply_feature(cells, feature)

	_apply_soil_noise(cells)

	var partitioner := DistrictPartitioner.new()
	for cell: HexCell in cells.values():
		partitioner.partition_cell(cell)

	return cells

func _base_elevation(coord: Vector2i) -> float:
	var n := _elevation_noise.get_noise_2d(coord.x, coord.y)
	return clampf((n + 1.0) * 0.5, 0.0, 1.0)

func _apply_feature(cells: Dictionary, feature: GeographyFeature) -> void:
	for coord in feature.hex_coords:
		if not cells.has(coord):
			continue
		var cell: HexCell = cells[coord]
		cell.region_name = feature.feature_name
		match feature.feature_type:
			GeographyFeature.FeatureType.SETTLEMENT:
				cell.is_settlement = true
				cell.biome_type = GameEnums.BiomeType.URBAN
				cell.soil_fertility = GameEnums.SoilFertility.NOT_ARABLE
			GeographyFeature.FeatureType.MOUNTAIN_RANGE:
				cell.biome_type = GameEnums.BiomeType.HIGHLAND
				cell.terrain_feature = GameEnums.TerrainFeature.ESCARPMENT
				cell.elevation = maxf(cell.elevation, 0.75)
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
		if n > 0.35:
			cell.soil_fertility = GameEnums.SoilFertility.LUSH
		elif n < -0.35:
			cell.soil_fertility = GameEnums.SoilFertility.DESOLATE
		else:
			cell.soil_fertility = GameEnums.SoilFertility.POOR
