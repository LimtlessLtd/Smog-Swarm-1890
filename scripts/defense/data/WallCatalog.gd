class_name WallCatalog
extends RefCounted

## Static per-tier data for wall segments (design doc Phase 4.1) — the same
## "single source of truth" role BuildingCatalog/TechCatalog play for their
## own trees. Tier numbering (0=Wooden, 1=Brick, 2=Concrete) matches
## TechCatalog's own WALL_TIER unlock_value convention exactly (see
## TechManager.is_wall_tier_unlocked()), so the two systems never need a
## translation layer between them.

const WOODEN: int = 0
const BRICK: int = 1
const CONCRETE: int = 2
const MAX_TIER: int = CONCRETE

static func get_display_name(tier: int) -> String:
	match tier:
		WOODEN:
			return "Wooden Wall"
		BRICK:
			return "Brick Wall"
		CONCRETE:
			return "Concrete Wall"
		_:
			return "Unknown Wall"

## HP scaling and cost are a balancing pass, not an architecture decision —
## same framing as every constant table in Phase 2.10/2.11. Concrete's
## Reinforced Concrete cost is a deliberate forward reference: no Phase 2
## building produces that resource yet either (see
## GameEnums.ResourceType.REINFORCED_CONCRETE's own doc comment), so
## Concrete Walls stay legitimately unbuildable in practice until a future
## production building exists — same pre-existing gap the resource itself
## already had, not a new one introduced here.
static func get_max_hp(tier: int) -> float:
	match tier:
		WOODEN:
			return 100.0
		BRICK:
			return 220.0
		CONCRETE:
			return 400.0
		_:
			return 0.0

static func get_build_cost(tier: int) -> Dictionary:
	match tier:
		WOODEN:
			return {GameEnums.ResourceType.WOOD: 40}
		BRICK:
			return {GameEnums.ResourceType.BRICKS: 70, GameEnums.ResourceType.CAST_IRON: 10}
		CONCRETE:
			return {GameEnums.ResourceType.REINFORCED_CONCRETE: 60, GameEnums.ResourceType.CAST_IRON: 20}
		_:
			return {}

## Design doc 4.1, decided: "each wall segment must be upgraded individually
## and costs resources to upgrade, but 50% less than building the wall from
## scratch."
static func get_upgrade_cost(tier: int) -> Dictionary:
	var cost := get_build_cost(tier)
	var result: Dictionary = {}
	for resource_type in cost:
		result[resource_type] = float(cost[resource_type]) * 0.5
	return result

## Design doc Phase 4.1/4.2: repairing a breached segment back to its
## current tier — "cheaper than building it from scratch" is the same
## framing WallManager.upgrade_segment()'s own 50% already uses, reused
## here rather than inventing a separate fraction.
static func get_repair_cost(tier: int) -> Dictionary:
	return get_upgrade_cost(tier)
