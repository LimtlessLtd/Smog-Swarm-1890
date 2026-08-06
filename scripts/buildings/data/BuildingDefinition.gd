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

## Fog of War (Phase 2.6): hex-disk radius this building projects VISIBLE
## coverage over, centered on its own hex — 0 (the default) still means "at
## least its own hex is visible", not "no vision at all". Independent of
## zoc_roles: Military/Civilian ZoC coverage is a separate vision source
## (see FogOfWarManager), this is for buildings like Gas Streetlamps and the
## Church Steeple Watchtower that light up an area beyond just themselves.
@export var vision_radius: int = 0

## Design doc 2.6.4/Phase 5.1: true for buildings that actively cast light
## (Gas Streetlamp, Church Steeple Watchtower, Searchlight Tower) rather than
## just being tall/staffed. At night, FogOfWarManager shrinks vision_radius
## for every OTHER building but holds/extends it for these — "cities as
## beacons in a dead world" needs their light to matter more after dark, not
## less. False (the default) for everything else, including buildings whose
## vision_radius is already >0 for a non-light reason.
@export var lit_at_night: bool = false

func _init(p_type: GameEnums.BuildingType = GameEnums.BuildingType.TERRACED_TENEMENT, p_display_name: String = "") -> void:
	building_type = p_type
	display_name = p_display_name
