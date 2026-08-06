class_name HexCell
extends Resource

## Pure data container for a single macro-hex (~25 sq. miles). Populated by
## HexMapGenerator, queried by HexGridMap, rendered by HexCellView. Holds no
## logic beyond simple derived queries over its own fields.

@export var coord: Vector2i = Vector2i.ZERO
@export var region_name: String = ""  ## e.g. "Manchester", "Chat Moss", "River Trent".
@export var biome_type: GameEnums.BiomeType = GameEnums.BiomeType.MOORLAND
@export var soil_fertility: GameEnums.SoilFertility = GameEnums.SoilFertility.POOR
@export var terrain_feature: GameEnums.TerrainFeature = GameEnums.TerrainFeature.NONE
@export var elevation: float = 0.0  ## 0.0 sea level .. 1.0 highest Pennine peaks.
@export var is_settlement: bool = false
@export var waterway_name: String = ""  ## e.g. "River Thames" — only set when terrain_feature is RIVER/CANAL.
@export var districts: Array[District] = []

func _init(p_coord: Vector2i = Vector2i.ZERO) -> void:
	coord = p_coord

## Marshes, peat bogs and steep escarpments are natural barriers/chokepoints
## until reclaimed (drained or bridged — Phase 4.2).
func is_passable() -> bool:
	return terrain_feature != GameEnums.TerrainFeature.MARSH and terrain_feature != GameEnums.TerrainFeature.PEAT_BOG

func is_frontier() -> bool:
	for district in districts:
		if district.type == GameEnums.DistrictType.UNCLEARED_WILDERNESS and district.is_contested:
			return true
	return false

func get_safe_districts() -> Array[District]:
	var result: Array[District] = []
	for district in districts:
		if not district.is_contested:
			result.append(district)
	return result
