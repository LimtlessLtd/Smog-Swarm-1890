class_name BuildingDefinition
extends Resource

## Pure data template for one entry in the building tree — "what a Coal
## Pithead is", not "the Coal Pithead sitting on hex (7,6)" (that's
## BuildingInstance). Populated once by BuildingCatalog, queried by
## BuildingManager for placement validation and daily upkeep/output
## aggregation. Holds no logic beyond simple derived queries over its own
## fields, matching HexCell/District's role in the world system.

@export var building_type: GameEnums.BuildingType = GameEnums.BuildingType.TOWN_HALL
@export var display_name: String = ""
@export var category: GameEnums.BuildingCategory = GameEnums.BuildingCategory.HOUSING_CIVIL
@export var tier: int = 0  ## 0-5, matches TechManager.is_building_tier_unlocked()'s tier numbering exactly. Town Hall is the one exception: tier 3 here gates player-driven construction (design_doc.md §3's "locked until Tier 3"), but the free starting instance is placed via BuildingManager.seed_starting_buildings()'s direct-registration path, which never calls get_placement_error() and so never consults this field.

@export var construction_cost: Dictionary = {}  ## GameEnums.ResourceType -> int, paid once on placement.
## GameEnums.ResourceType -> float, drained every day_completed — EXCEPT
## ResourceType.ENERGY/POPULATION: both are design_doc.md §2 capacity pools,
## not a recurring drain — a one-time grid/labor allocation taken once at
## construction/repair and refunded the instant the building ruins. Reuses
## this same field (rather than a dedicated one) since it's still "what this
## building needs to operate," just settled once instead of every day — see
## BuildingCapacityAllocator.apply()'s own doc comment for the full
## mechanism. Every OTHER resource type here still means exactly what the
## field name says.
@export var daily_upkeep: Dictionary = {}
## GameEnums.ResourceType -> float, produced every day_completed — same
## ENERGY/POPULATION exception as daily_upkeep above, mirrored: an entry
## here for either type is a one-time grant made at construction/repair and
## withdrawn on ruin, not a daily income.
@export var daily_output: Dictionary = {}
@export var storage_bonus: Dictionary = {}      ## GameEnums.ResourceType -> float, added to ResourceManager's cap once on placement.

## Housing only. Drives two separate things that both read this one field:
## BuildingInstance.current_population (occupancy — fixed at this value once
## built, feeds colony-wide Food upkeep via BuildingSustenanceController.
## FOOD_PER_POPULATION, and HordeManager's ruin-to-casualties conversion) and
## a mirrored daily_output[ResourceType.POPULATION] entry (the
## BuildingCapacityAllocator capacity grant, design_doc.md §2) that
## BuildingCatalog's housing builders set explicitly alongside this field —
## see e.g. _terraced_tenement().
@export var population_provided: int = 0

## Placement restrictions — an empty array means "no restriction of this kind".
@export var allowed_biomes: Array[GameEnums.BiomeType] = []
@export var allowed_soil_fertility: Array[GameEnums.SoilFertility] = []
@export var requires_settlement: bool = false  ## True for civic/industrial buildings that must sit inside a settlement's urban footprint.

## When true, daily_output is treated as the POOR-soil baseline and scaled
## by the target hex's actual soil fertility (see
## BuildingInstance.get_effective_output) — this is what granular soil
## fertility is for: determining specific farm placement and crop yields.
@export var soil_fertility_scales_output: bool = false

@export var zoc_roles: Array[GameEnums.ZoneOfControlType] = []  ## Which Zone(s) of Control this building projects, if any.

## Whether UnitCommandController should open UnitPanelView's training panel
## on a click. Its own flag, not "does this project Military ZoC" — Church
## Steeple Watchtower, Forward Ammo Dump, and Searchlight Tower all
## project Military ZoC too (lookout/logistics/illumination roles, not
## training), so a shared check would pop the training panel up for all
## four when only the Garrison actually trains anyone. True only on
## Garrison today; a future dedicated Barracks-style building would set it too.
@export var can_train_units: bool = false

## Hex-disk radius this building projects VISIBLE coverage over, centered
## on its own hex — 0 (the default) still means "at least its own hex is
## visible", not "no vision at all". Independent of zoc_roles: Military/
## Civilian ZoC coverage is a separate vision source (see FogOfWarManager),
## this is for buildings like Gas Streetlamps and the Church Steeple
## Watchtower that light up an area beyond just themselves.
@export var vision_radius: int = 0

## True for buildings that actively cast light (Gas Streetlamp, Church
## Steeple Watchtower, Searchlight Tower) rather than just being
## tall/staffed. At night, FogOfWarManager shrinks vision_radius for every
## OTHER building but holds/extends it for these — "cities as beacons in a
## dead world" needs their light to matter more after dark, not less.
## False (the default) for everything else, including buildings whose
## vision_radius is already >0 for a non-light reason.
@export var lit_at_night: bool = false

## A flat per-building noise level (NoiseManager), 0 (the default) for
## anything that isn't running loud machinery. Only INDUSTRY_EXTRACTION
## category buildings set this today, per-building rather than a flat
## category-wide value (a Foundry's hammering is louder than a Brickworks'
## kiln) — placeholder balancing numbers, not an architecture decision.
@export var noise_output: int = 0

func _init(p_type: GameEnums.BuildingType = GameEnums.BuildingType.TOWN_HALL, p_display_name: String = "") -> void:
	building_type = p_type
	display_name = p_display_name

## "Same spirit as walls' own toughness, scaling with construction
## tier/cost" — BuildingDefinition has no explicit tier field the way
## WallCatalog's per-tier table does, so construction_cost (already
## authored per building, already a reasonable proxy for "how substantial
## is this") stands in for it directly: a flat baseline plus the sum of
## what it cost to build. Lands in roughly the same 100-400 range
## WallCatalog.get_max_hp() spans across its own three tiers. Placeholder
## balancing numbers, not an architecture decision.
const _BASE_HP: float = 80.0
const _HP_PER_COST_UNIT: float = 1.0

func get_max_hp() -> float:
	var total_cost := 0.0
	for resource_type in construction_cost:
		total_cost += float(construction_cost[resource_type])
	return _BASE_HP + total_cost * _HP_PER_COST_UNIT
