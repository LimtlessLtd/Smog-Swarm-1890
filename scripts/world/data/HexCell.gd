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
## until reclaimed (drained or bridged — Phase 4.2). Open OCEAN (design doc,
## user request: map now represents the whole UK+Ireland) is impassable too,
## on the same "not walkable, needs a future system to cross" footing —
## unlike a marsh, nothing reclaims it; Phase 7.5's Naval Logistics/ships
## are the only thing that will ever let a unit or horde reach across it.
func is_passable() -> bool:
	return terrain_feature != GameEnums.TerrainFeature.MARSH and terrain_feature != GameEnums.TerrainFeature.PEAT_BOG and biome_type != GameEnums.BiomeType.OCEAN

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

## Design doc Phase 2.12.2, decided: "reduces, does not block" — dense local
## vegetation shrinks how far a vision source SITTING on this hex can see,
## explicitly no hard occlusion/stealth. Scoped to the biomes that actually
## carry dense tree/bush/reed cover in LocalDetailGenerator's own per-biome
## prop table (Phase 2.5.2) — Moorland's tree/bush mix and Wetland's reed
## beds, not Highland (its props are rocks, not vegetation) or the sparser,
## tilled Farmland. Returns hex-rings to subtract from a vision_radius, not
## a hard cap — see FogOfWarManager._compute_visible_set()'s own caller.
func get_vision_penalty() -> int:
	match biome_type:
		GameEnums.BiomeType.MOORLAND, GameEnums.BiomeType.WETLAND:
			return 1
		GameEnums.BiomeType.WOODLAND:
			return 2  ## Granularity pass — the tree-heaviest of LocalDetailGenerator's own biomes (110 props/hex, real forest canopy) should occlude more than Moorland's own lighter scatter, not the same flat 1.
		GameEnums.BiomeType.HEATHLAND:
			return 1  ## Low shrub cover — same order as Moorland, not the denser Woodland penalty.
		_:
			return 0
