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

## design_doc.md §2.1's `total_zombie_pop`: how many zombies this hex holds at
## 100% infestation, baked from real 1890s settlement population
## (ZombiePopulationData, written by tools/geo_bake/bake_population.py).
## 0 for open OCEAN — nothing walks there. Static per hex and set once by
## HexMapGenerator, which is why it belongs on this pure data container while
## the mutable `zombie_count` it is a ratio of does not: the map is rebuilt from
## fixed seeds on every boot and no HexCell is ever serialised, so an @export
## here persists nothing and is not meant to.
@export var total_zombie_pop: int = 0

func _init(p_coord: Vector2i = Vector2i.ZERO) -> void:
	coord = p_coord

## design_doc.md §5's discrete height band for this hex's own elevation.
## Derived on demand, never stored — see ElevationLevels' own doc comment.
func height_level() -> int:
	return ElevationLevels.level_for(elevation, biome_type == GameEnums.BiomeType.OCEAN)

## Marshes, peat bogs and steep escarpments are natural barriers/chokepoints
## until reclaimed (drained or bridged). Open OCEAN — the map represents the
## whole UK+Ireland — is impassable too, on the same "not walkable, needs a
## future system to cross" footing; unlike a marsh, nothing reclaims it,
## only a future Naval Logistics/ships system will let a unit or horde
## cross it.
##
## Level 4 MOUNTAIN joins them (design_doc.md §5: "IMPASSABLE for all ground
## units, vehicles, and zombies"), which had never been implemented — real
## summit elevation was sampled, stored, and then ignored by every rule.
## Adding it here rather than in each caller means the one check pathfinding,
## the horde flow field, wall placement and building placement already share
## picks it up at once. Measured before committing to it
## (scripts/test/verify_elevation.gd): it must not sever the landmass, and
## the numbers that decide how much of the map it claims live in
## ElevationLevels._METRE_THRESHOLDS.
func is_passable() -> bool:
	if ElevationLevels.is_impassable(height_level()):
		return false
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

## "Reduces, does not block" — dense local vegetation shrinks how far a
## vision source sitting on this hex can see; no hard occlusion/stealth.
## Scoped to the biomes that carry dense tree/bush/reed cover in
## LocalDetailGenerator's own per-biome prop table — Moorland's tree/bush
## mix and Wetland's reed beds, not Highland (its props are rocks, not
## vegetation) or the sparser, tilled Farmland. Returns hex-rings to
## subtract from a vision_radius, not a hard cap — see
## FogOfWarManager._compute_visible_set()'s own caller.
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
