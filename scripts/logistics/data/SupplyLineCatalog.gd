class_name SupplyLineCatalog
extends RefCounted

## Static per-(line_type, tier) data for supply-line segments — the same
## "single source of truth" role WallCatalog plays for wall segments.
## design_doc.md §3 interleaves each Infrastructure entry within its own
## Tier's building list (Dirt Road sits in the Tier 0 list alongside Town
## Hall, Cobblestone Road in Tier 1, etc.) rather than giving Infrastructure
## its own separate unlock track — tier numbering here matches
## TechManager.is_building_tier_unlocked() exactly for the same reason
## WallCatalog's own tier numbers match TechManager.is_wall_tier_unlocked().
##
## ROAD has 3 tiers (Dirt/Cobblestone/Concrete). RAILWAY and CANAL have
## exactly ONE tier each (design_doc.md §3 lists a single Railway and a
## single Canal entry, both Tier 3) — get_max_tier() returns 0 for both,
## so LogisticsNetwork.upgrade_segment() naturally rejects "already at
## highest tier" for them with no special-casing needed. BRIDGE has 4
## tiers (Wooden/Brick Arch/Iron Girder/Steel Truss) — the only
## SupplyLineType legal to place across a WATERWAY hex edge; ROAD/RAILWAY/
## CANAL are illegal there (LogisticsNetwork.get_placement_error() enforces
## both directions).
##
## No build-TIME here, unlike design_doc.md's own "Time: 0.5 days"/"Time: 1
## day" figures for Dirt Road/Wooden Bridge (every other tier gives no time
## at all) — mirrors this project's existing WallCatalog precedent, where
## wall segments are placed instantly once affordable, cost-gated only, no
## construction queue. Infrastructure follows the same simplification
## rather than inventing a queue mechanic walls themselves don't have.

const ROAD_MAX_TIER: int = 2
const BRIDGE_MAX_TIER: int = 3

## RAILWAY/CANAL are single-tier — 0 is correct for both, not a placeholder.
static func get_max_tier(line_type: GameEnums.SupplyLineType) -> int:
	match line_type:
		GameEnums.SupplyLineType.ROAD:
			return ROAD_MAX_TIER
		GameEnums.SupplyLineType.BRIDGE:
			return BRIDGE_MAX_TIER
		_:
			return 0

static func get_display_name(line_type: GameEnums.SupplyLineType, tier: int) -> String:
	match line_type:
		GameEnums.SupplyLineType.ROAD:
			match tier:
				0: return "Dirt Road"
				1: return "Cobblestone Road"
				2: return "Concrete Road"
		GameEnums.SupplyLineType.RAILWAY:
			return "Railway"
		GameEnums.SupplyLineType.CANAL:
			return "Canal"
		GameEnums.SupplyLineType.BRIDGE:
			match tier:
				0: return "Wooden Bridge"
				1: return "Brick Arch Bridge"
				2: return "Iron Girder Bridge"
				3: return "Steel Truss Bridge"
	return "Unknown Infrastructure"

## design_doc.md §3's real per-segment costs. Every entry is "per seg" in
## the doc's own words, and unlike WallCatalog (whose freehand pieces get
## chopped to <=100m and cost-scaled by length — see that class's own doc
## comment) a SupplyLineSegment already represents exactly one hex-to-hex
## edge by construction, so these costs apply directly with no length
## scaling needed.
static func get_build_cost(line_type: GameEnums.SupplyLineType, tier: int) -> Dictionary:
	match line_type:
		GameEnums.SupplyLineType.ROAD:
			match tier:
				0: return {GameEnums.ResourceType.WOOD: 10}
				1: return {GameEnums.ResourceType.WOOD: 5, GameEnums.ResourceType.BRICKS: 10}
				2: return {GameEnums.ResourceType.WOOD: 5, GameEnums.ResourceType.BRICKS: 10, GameEnums.ResourceType.IRON: 10}
		GameEnums.SupplyLineType.RAILWAY:
			return {GameEnums.ResourceType.WOOD: 15, GameEnums.ResourceType.BRICKS: 15, GameEnums.ResourceType.CONCRETE: 15, GameEnums.ResourceType.STEEL: 15}
		GameEnums.SupplyLineType.CANAL:
			return {GameEnums.ResourceType.WOOD: 20, GameEnums.ResourceType.BRICKS: 20, GameEnums.ResourceType.CONCRETE: 20, GameEnums.ResourceType.STEEL: 10}
		GameEnums.SupplyLineType.BRIDGE:
			match tier:
				0: return {GameEnums.ResourceType.WOOD: 30}
				1: return {GameEnums.ResourceType.WOOD: 15, GameEnums.ResourceType.BRICKS: 30}
				2: return {GameEnums.ResourceType.WOOD: 10, GameEnums.ResourceType.BRICKS: 20, GameEnums.ResourceType.IRON: 20}
				3: return {GameEnums.ResourceType.WOOD: 10, GameEnums.ResourceType.BRICKS: 10, GameEnums.ResourceType.CONCRETE: 20, GameEnums.ResourceType.STEEL: 20}
	return {}

## Same "50% of building from scratch" fraction WallCatalog.get_upgrade_cost()
## uses.
static func get_upgrade_cost(line_type: GameEnums.SupplyLineType, tier: int) -> Dictionary:
	var cost := get_build_cost(line_type, tier)
	var result: Dictionary = {}
	for resource_type in cost:
		result[resource_type] = float(cost[resource_type]) * 0.5
	return result

## design_doc.md §2 "Infrastructure Velocity Modifiers" (+25%/+50%/+100%/
## +300%/+200% for Dirt/Cobblestone/Concrete Road, Railway, Canal — returned
## here as a straight multiplier, i.e. 1.25/1.50/2.00/4.00/3.00) plus
## "completely ignoring underlying biome movement speed reductions" —
## HexPathfinder.get_step_cost()/get_movement_speed_multiplier() both apply
## this as an OVERRIDE of the terrain multiplier on a segment's edge, not a
## multiplicative stack with it.
##
## Bridge tiers aren't individually given a speed number in the doc (only
## Cost is listed per Bridge tier) — chosen to match each Bridge's SAME-TIER
## Road counterpart for tiers 0-2 (the doc lists Wooden Bridge alongside
## Dirt Road under the same Tier 0 heading, Brick Arch alongside Cobblestone
## under Tier 1, Iron Girder alongside Concrete under Tier 2). Tier 3's
## Steel Truss Bridge sits alongside BOTH Railway (+300%) and Canal (+200%)
## under the Tier 3 heading with no way to tell which it should match from
## the doc alone — chose Canal's +200% (multiplier 3.00) as the "major
## civil-engineering water-crossing structure" analogue over the rail-
## specific figure. An interpretive choice, disclosed here rather than
## silently assumed.
static func get_speed_multiplier(line_type: GameEnums.SupplyLineType, tier: int) -> float:
	match line_type:
		GameEnums.SupplyLineType.ROAD, GameEnums.SupplyLineType.BRIDGE:
			match tier:
				0: return 1.25
				1: return 1.50
				2: return 2.00
				3: return 3.00  ## BRIDGE only — ROAD's own get_max_tier() is 2, this arm is never reached for ROAD.
		GameEnums.SupplyLineType.RAILWAY:
			return 4.00  ## +300%
		GameEnums.SupplyLineType.CANAL:
			return 3.00  ## +200%
	return 1.0
