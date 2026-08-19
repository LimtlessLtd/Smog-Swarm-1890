class_name WallCatalog
extends RefCounted

## Static per-tier data for wall segments — the same "single source of
## truth" role BuildingCatalog/TechCatalog play for their own trees. Tier
## numbering (0=Wooden, 1=Brick, 2=Concrete) matches TechCatalog's own
## WALL_TIER unlock_value convention exactly (see
## TechManager.is_wall_tier_unlocked()), so the two systems never need a
## translation layer between them.

const WOODEN: int = 0
const BRICK: int = 1
const CONCRETE: int = 2
const MAX_TIER: int = CONCRETE

## A Gate segment (WallSegment.is_gate) is the traditional weak point of a
## fortification — same tier, same build cost per unit length, same siege/
## repair/upgrade path as a solid wall, just a fraction of the HP the wall it
## replaces would have had. Applied by WallSegment.get_max_hp(), not here —
## this class stays the single "what does tier N cost/hold" source of truth,
## a segment layers its own gate modifier on top rather than this table
## needing to know about individual segment state. Balancing number, not an
## architecture decision.
const GATE_HP_FRACTION: float = 0.4

## "It needs to be 3 wall segments long... it shouldnt be repeatable/stretch
## like walls, you place 1 gate at a time" (user spec). A gate is therefore
## ONE WallSegment of a fixed length, not a chain of pieces: it is a single
## structure with a single door, and chopping it would give a player three
## independently-breachable thirds of a gate.
##
## It is the one exception to MAX_SEGMENT_LENGTH_WORLD_UNITS above, which
## exists so a breach costs the player a short piece rather than a whole
## drawn run. A gate is already the short, deliberately weak piece.
const GATE_LENGTH_SEGMENTS: int = 3
const GATE_LENGTH_WORLD_UNITS: float = MAX_SEGMENT_LENGTH_WORLD_UNITS * float(GATE_LENGTH_SEGMENTS)

static func get_gate_display_name(tier: int) -> String:
	match tier:
		WOODEN:
			return "Wooden Gate"
		BRICK:
			return "Brick Gate"
		CONCRETE:
			return "Concrete Gate"
		_:
			return "Unknown Gate"

## "Each wall segment should be no longer than 100 meters MAXIMUM, if it
## goes beyond 100 meters it should be split up into multiple segments...
## when a zombie comes into contact with the wall and destroys it, the
## ENTIRE 5 mile full length of wall is destroyed. That's pretty
## ridiculous" (user feedback) — matches *They Are Billions*' own model: a
## wall is a chain of small discrete pieces, each with independent HP,
## destroyed one piece at a time with zero cascade to neighboring pieces,
## not one continuous structure per placement action.
## WallManager.place_wall_line() is what actually enforces this — chopping
## any placed line (freehand drag or the free starting perimeter alike)
## into pieces no longer than this. See HexCoord.WORLD_UNITS_PER_REAL_METER's
## own doc comment for the real-world/world-unit conversion this is built from.
const MAX_SEGMENT_LENGTH_WORLD_UNITS: float = 100.0 * HexCoord.WORLD_UNITS_PER_REAL_METER

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

## HP scaling and cost are a balancing pass, not an architecture decision.
## Concrete's Concrete cost is a deliberate forward reference: no building
## produces that resource yet (see GameEnums.ResourceType.CONCRETE's own
## doc comment), so Concrete Walls stay legitimately unbuildable in
## practice until a future Concrete Plant exists (Building tree rework, todo.md).
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
			return {GameEnums.ResourceType.BRICKS: 70, GameEnums.ResourceType.IRON: 10}
		CONCRETE:
			return {GameEnums.ResourceType.CONCRETE: 60, GameEnums.ResourceType.IRON: 20}
		_:
			return {}

## "Each wall segment must be upgraded individually and costs resources to
## upgrade, but 50% less than building the wall from scratch."
static func get_upgrade_cost(tier: int) -> Dictionary:
	var cost := get_build_cost(tier)
	var result: Dictionary = {}
	for resource_type in cost:
		result[resource_type] = float(cost[resource_type]) * 0.5
	return result

## Repairing a breached segment back to its current tier — "cheaper than
## building it from scratch" is the same framing WallManager.upgrade_segment()'s
## own 50% uses, reused here rather than inventing a separate fraction.
static func get_repair_cost(tier: int) -> Dictionary:
	return get_upgrade_cost(tier)
