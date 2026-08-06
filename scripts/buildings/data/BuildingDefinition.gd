class_name BuildingDefinition
extends Resource

## Pure data template for one entry in the building tree (design doc Phase
## 2.1) — "what a Coal Pithead is", not "the Coal Pithead sitting on hex
## (7,6)" (that's BuildingInstance). Populated once by BuildingCatalog,
## queried by BuildingManager for placement validation and daily
## upkeep/output aggregation. Holds no logic beyond simple derived queries
## over its own fields, matching HexCell/District's role in the world system.

@export var building_type: GameEnums.BuildingType = GameEnums.BuildingType.TERRACED_TENEMENT
@export var display_name: String = ""
@export var category: GameEnums.BuildingCategory = GameEnums.BuildingCategory.HOUSING_CIVIL

@export var construction_cost: Dictionary = {}  ## GameEnums.ResourceType -> int, paid once on placement.
@export var daily_upkeep: Dictionary = {}       ## GameEnums.ResourceType -> float, drained every day_completed.
@export var daily_output: Dictionary = {}       ## GameEnums.ResourceType -> float, produced every day_completed.
@export var storage_bonus: Dictionary = {}      ## GameEnums.ResourceType -> float, added to ResourceManager's cap once on placement.

@export var population_provided: int = 0  ## Housing only; drives colony-wide Food upkeep (see BuildingManager.FOOD_PER_POPULATION).

## Placement restrictions — an empty array means "no restriction of this kind".
@export var allowed_biomes: Array[GameEnums.BiomeType] = []
@export var allowed_soil_fertility: Array[GameEnums.SoilFertility] = []
@export var requires_settlement: bool = false  ## True for civic/industrial buildings that must sit inside a settlement's urban footprint.

## When true, `daily_output` is treated as the POOR-soil baseline and scaled
## by the target hex's actual soil fertility (see BuildingInstance.get_effective_output) —
## this is what Phase 1.3's "granular soil fertility ... to determine specific
## farm placement and crop yields" is for.
@export var soil_fertility_scales_output: bool = false

@export var zoc_roles: Array[GameEnums.ZoneOfControlType] = []  ## Which Zone(s) of Control (Phase 2.3) this building projects, if any.

func _init(p_type: GameEnums.BuildingType = GameEnums.BuildingType.TERRACED_TENEMENT, p_display_name: String = "") -> void:
	building_type = p_type
	display_name = p_display_name
