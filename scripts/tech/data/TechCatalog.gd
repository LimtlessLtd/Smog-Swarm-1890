class_name TechCatalog
extends RefCounted

## Static seed data for the Tech Tree — the same
## "single source of truth, built lazily and cached" role BuildingCatalog
## plays for the building tree, kept separate from TechManager (the runtime
## system that tracks what a given campaign has actually researched).
##
## **Decided scope:** a simple prerequisite chain, not a
## wide branching web. Three chains exist right now, each gating content this
## doc already promises elsewhere but has no unlock mechanism for yet:
## - Wall tiers: Wooden is the baseline (no tech needed), then
##   Brick -> Concrete, one node each.
## - Unit tiers: Tier 0 is the baseline (no tech needed — it's
##   the "Free Ammo" starting tier), then Tiers 1-5 each gate all 3 roles of
##   that tier at once, one node per tier, strictly linear.
## - Building tiers: Tier 0 is the baseline (no tech needed), then Tiers 1-5
##   each gate that whole tier's BuildingCatalog entries at once, one node
##   per tier, strictly linear — cost is design_doc.md §2's own "Tech Unlock
##   Thresholds" numbers, Research Points only (no material, unlike unit tiers).
## Seafaring stands alone (no tech prerequisite) but carries its own
## campaign-state gate — see TechDefinition.requires_wales_and_scotland_retaken.
##
## "Advanced building variant" and "individual per-unit upgrade nodes"
## are deliberately not represented here yet: no such
## variant building or trained unit exists anywhere in the project to
## actually unlock. GameEnums.TechUnlockType.BUILDING_VARIANT exists as a
## documented hook for the former; the latter is explicitly a *smaller,
## separate* node per the design doc, layered on once the unit-tier system
## grows, not something to invent placeholder entries for now.

static var _definitions_by_id: Dictionary = {}  # StringName -> TechDefinition

static func get_definition(tech_id: StringName) -> TechDefinition:
	_ensure_built()
	return _definitions_by_id.get(tech_id)

static func get_all_definitions() -> Array[TechDefinition]:
	_ensure_built()
	var result: Array[TechDefinition] = []
	result.assign(_definitions_by_id.values())
	return result

static func _ensure_built() -> void:
	if not _definitions_by_id.is_empty():
		return
	for definition in _build_definitions():
		_definitions_by_id[definition.tech_id] = definition

static func _build_definitions() -> Array[TechDefinition]:
	return [
		_brick_walls(), _concrete_walls(),
		_unit_tier(1, "Militia Regimental Drill", 30, 2),
		_unit_tier(2, "Colonial Line Infantry", 50, 3),
		_unit_tier(3, "Highland Regiments Act", 80, 4),
		_unit_tier(4, "Steam Traction Warfare", 130, 5),
		_unit_tier(5, "Armoured Rail Doctrine", 200, 6),
		_building_tier(1, "Borough Charter", 50, 2),
		_building_tier(2, "Industrial District Act", 200, 3),
		_building_tier(3, "Rail Network Act", 500, 4),
		_building_tier(4, "Automation Era Doctrine", 1200, 5),
		_building_tier(5, "Super-Complex Era Doctrine", 2500, 6),
		_seafaring(),
	]

# --- Wall tiers -------------------------------------------------------------

static func _brick_walls() -> TechDefinition:
	var d := TechDefinition.new(&"brick_walls", "Brick Walls")
	d.description = "Upgrades the wall tier available for chokepoint construction from Wooden to Brick."
	d.cost = {GameEnums.ResourceType.RESEARCH_POINTS: 40, GameEnums.ResourceType.BRICKS: 60}
	d.research_days = 2
	d.unlock_type = GameEnums.TechUnlockType.WALL_TIER
	d.unlock_value = 1
	return d

static func _concrete_walls() -> TechDefinition:
	var d := TechDefinition.new(&"concrete_walls", "Concrete Walls")
	d.description = "Upgrades the wall tier available for chokepoint construction from Brick to Concrete."
	d.cost = {GameEnums.ResourceType.RESEARCH_POINTS: 90, GameEnums.ResourceType.IRON: 50}
	d.research_days = 3
	d.prerequisites = [&"brick_walls"]
	d.unlock_type = GameEnums.TechUnlockType.WALL_TIER
	d.unlock_value = 2
	return d

# --- Unit tiers ---------------------------------------------------------------

## Builds one linear-chain unit-tier node (`unit_tier_<n>`), prerequisite on
## the previous tier's node (tier 1 has no tech prerequisite — Tier 0 is the
## free starting roster). `research_points_cost` scales per tier by the
## caller; `research_days` likewise, both a balancing pass rather than an
## architecture decision.
static func _unit_tier(tier: int, tier_display_name: String, research_points_cost: int, research_days: int) -> TechDefinition:
	var d := TechDefinition.new(StringName("unit_tier_%d" % tier), tier_display_name)
	d.description = "Unlocks Tier %d's melee, ranged and special units, all 3 roles at once." % tier
	d.cost = {GameEnums.ResourceType.RESEARCH_POINTS: research_points_cost, GameEnums.ResourceType.IRON: research_points_cost * 0.6}
	d.research_days = research_days
	if tier > 1:
		d.prerequisites = [StringName("unit_tier_%d" % (tier - 1))]
	d.unlock_type = GameEnums.TechUnlockType.UNIT_TIER
	d.unlock_value = tier
	return d

# --- Building tiers -----------------------------------------------------------

## Builds one linear-chain building-tier node (`building_tier_<n>`),
## prerequisite on the previous tier's node (tier 1 has no tech prerequisite
## — Tier 0 is the free/always-buildable baseline). `research_points_cost`
## reuses design_doc.md §2's own "Tech Unlock Thresholds" numbers directly
## (50/200/500/1200/2500) rather than inventing new ones — the doc gives no
## separate material cost for these, so unlike _unit_tier() this is
## Research-Points-only.
static func _building_tier(tier: int, tier_display_name: String, research_points_cost: int, research_days: int) -> TechDefinition:
	var d := TechDefinition.new(StringName("building_tier_%d" % tier), tier_display_name)
	d.description = "Unlocks Tier %d's buildings." % tier
	d.cost = {GameEnums.ResourceType.RESEARCH_POINTS: research_points_cost}
	d.research_days = research_days
	if tier > 1:
		d.prerequisites = [StringName("building_tier_%d" % (tier - 1))]
	d.unlock_type = GameEnums.TechUnlockType.BUILDING_TIER
	d.unlock_value = tier
	return d

# --- Seafaring (gates the Ireland unlock) -----------------------------------

static func _seafaring() -> TechDefinition:
	var d := TechDefinition.new(&"seafaring", "Seafaring")
	d.description = "Unlocks the Port building and sea supply lines. Cannot be researched until Wales and Scotland are both fully retaken."
	d.cost = {GameEnums.ResourceType.RESEARCH_POINTS: 150, GameEnums.ResourceType.BRICKS: 80}
	d.research_days = 4
	d.unlock_type = GameEnums.TechUnlockType.SEAFARING
	d.requires_wales_and_scotland_retaken = true
	return d
