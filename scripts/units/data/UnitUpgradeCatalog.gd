class_name UnitUpgradeCatalog
extends RefCounted

## Static seed data for design_doc.md §4's one-line "Upgrades: 2 research
## upgrades per unit type (auto-applies to active & future units)" — the
## "individual per-unit upgrade nodes" TechCatalog's own class comment has
## been deferring ("explicitly a *smaller, separate* node per the design
## doc, layered on once the unit-tier system grows"). This is that layer.
##
## Generated from the roster, not hand-authored: 18 unit types x 2 = 36
## nodes, and UnitCatalog already establishes the precedent of deriving a
## unit's stats from its tier and role rather than transcribing each one
## (see UnitCatalog._unit()'s own tier/role stat block). Hand-writing 36
## entries would be 36 chances to drift from the roster it describes.
##
## **The doc specifies the COUNT and that upgrades auto-apply, nothing
## else** — no stat, no magnitude, no cost. Everything below is therefore a
## disclosed interpretive choice, not a doc transcription. **User-decided
## split, role-flavoured rather than uniform:**
##
## - MELEE   -> ATTACK_DAMAGE, then MAX_HP. The archetype that has to close
##             to contact, so it gets hit more; both halves of "fight
##             better" are the ones that matter to it.
## - RANGED  -> ATTACK_DAMAGE, then GUNPOWDER_RELIEF. Its second upgrade
##             targets the penalty that hits this role hardest and only
##             this role — UnitDefinition.requires_gunpowder's forced
##             "fragile, unarmored melee mode" (UnitCatalog already docks
##             RANGED units 10% HP for exactly that exposure).
## - SPECIAL -> MOVE_SPEED, then VISION_RADIUS. The scouting/mobility
##             archetype (Outrider, Chasseur, Dragoon, Searchlight Tender);
##             upgrading its damage would blur it into the other two roles.
##
## Toxophilite is worth calling out: it's RANGED but
## `requires_gunpowder = false` (bows aren't a tracked resource), so its
## GUNPOWDER_RELIEF upgrade would be a no-op. It gets MAX_HP instead — see
## _second_stat_for() below.
##
## Costs are Research Points only and deliberately CHEAPER than the unit-tier
## node of the same tier (TechCatalog._unit_tier() charges 30/50/80/130/200):
## these are the doc's own "smaller, separate" nodes, refinements to a
## roster you already unlocked, not the unlock itself.

## Magnitudes. Balancing numbers, not architecture — same framing every
## other placeholder constant table in this project carries.
const DAMAGE_MULTIPLIER: float = 1.25
const MAX_HP_MULTIPLIER: float = 1.25
const MOVE_SPEED_MULTIPLIER: float = 1.20
const VISION_RADIUS_BONUS: float = 1.0
## Halves the forced-melee penalty rather than removing it — 1.0 would make
## a Gunpowder-dependent unit entirely indifferent to running dry, which
## would defeat the depletion mechanic instead of softening it.
const GUNPOWDER_RELIEF: float = 0.5

const _BASE_RESEARCH_POINTS: float = 10.0
const _RESEARCH_POINTS_PER_TIER: float = 10.0

static var _by_tech_id: Dictionary = {}      # StringName -> UnitUpgradeDefinition
static var _by_unit_type: Dictionary = {}    # GameEnums.UnitType -> Array[UnitUpgradeDefinition], index-ordered

## The upgrade a given tech_id grants, or null if that id isn't a unit
## upgrade at all — how UnitUpgrades resolves a researched tech back to its
## effect without TechManager needing to know unit upgrades exist.
static func get_definition(tech_id: StringName) -> UnitUpgradeDefinition:
	_ensure_built()
	return _by_tech_id.get(tech_id)

## Both upgrades for `unit_type`, in index order (0 then 1). Always exactly
## two — every unit type in the roster gets a full pair.
static func get_upgrades_for(unit_type: GameEnums.UnitType) -> Array[UnitUpgradeDefinition]:
	_ensure_built()
	var result: Array[UnitUpgradeDefinition] = []
	result.assign(_by_unit_type.get(unit_type, []))
	return result

static func get_all_definitions() -> Array[UnitUpgradeDefinition]:
	_ensure_built()
	var result: Array[UnitUpgradeDefinition] = []
	result.assign(_by_tech_id.values())
	return result

## The TechDefinitions TechCatalog merges into the one tech tree, so these
## research through exactly the same path as every other node.
static func get_tech_definitions() -> Array[TechDefinition]:
	var result: Array[TechDefinition] = []
	for upgrade in get_all_definitions():
		result.append(upgrade.to_tech_definition())
	return result

static func tech_id_for(unit_type: GameEnums.UnitType, upgrade_index: int) -> StringName:
	return StringName("unit_upgrade_%d_%d" % [int(unit_type), upgrade_index])

static func _ensure_built() -> void:
	if not _by_tech_id.is_empty():
		return
	for definition in UnitCatalog.get_all_definitions():
		var pair: Array[UnitUpgradeDefinition] = [
			_build(definition, 0, _first_stat_for(definition)),
			_build(definition, 1, _second_stat_for(definition)),
		]
		for upgrade in pair:
			_by_tech_id[upgrade.tech_id] = upgrade
		_by_unit_type[definition.unit_type] = pair

static func _first_stat_for(definition: UnitDefinition) -> GameEnums.UnitUpgradeStat:
	if definition.role == GameEnums.UnitRole.SPECIAL:
		return GameEnums.UnitUpgradeStat.MOVE_SPEED
	return GameEnums.UnitUpgradeStat.ATTACK_DAMAGE

static func _second_stat_for(definition: UnitDefinition) -> GameEnums.UnitUpgradeStat:
	match definition.role:
		GameEnums.UnitRole.SPECIAL:
			return GameEnums.UnitUpgradeStat.VISION_RADIUS
		GameEnums.UnitRole.RANGED:
			# Toxophilite: RANGED, but exempt from the Gunpowder-depletion
			# penalty by design, so GUNPOWDER_RELIEF would grant it nothing
			# at all. Falls back to the MELEE second stat rather than
			# shipping a knowingly dead upgrade node.
			if not definition.requires_gunpowder:
				return GameEnums.UnitUpgradeStat.MAX_HP
			return GameEnums.UnitUpgradeStat.GUNPOWDER_RELIEF
		_:
			return GameEnums.UnitUpgradeStat.MAX_HP

static func _build(definition: UnitDefinition, index: int, stat: GameEnums.UnitUpgradeStat) -> UnitUpgradeDefinition:
	var u := UnitUpgradeDefinition.new()
	u.unit_type = definition.unit_type
	u.upgrade_index = index
	u.tech_id = tech_id_for(definition.unit_type, index)
	u.stat = stat
	u.magnitude = _magnitude_for(stat)
	u.display_name = "%s: %s" % [definition.display_name, _stat_title(stat, definition.tier)]
	u.description = _stat_description(stat, definition.display_name)
	u.cost = {GameEnums.ResourceType.RESEARCH_POINTS: _BASE_RESEARCH_POINTS + _RESEARCH_POINTS_PER_TIER * float(definition.tier) + _RESEARCH_POINTS_PER_TIER * float(index)}
	u.research_days = 1 + int(definition.tier / 2)
	u.prerequisites = _prerequisites_for(definition, index)
	return u

## A strict chain, matching TechCatalog's decided "simple prerequisite chain,
## not a wide branching web" scope: the second upgrade needs the first, and
## the first needs the unit's own tier node — you can't refine a Tier 3 unit
## you haven't unlocked. Tier 0 is the baseline roster with no tech node of
## its own (TechManager.is_unit_tier_unlocked()'s tier-0 rule), so its first
## upgrade has no prerequisite at all.
static func _prerequisites_for(definition: UnitDefinition, index: int) -> Array[StringName]:
	if index > 0:
		return [tech_id_for(definition.unit_type, index - 1)]
	if definition.tier <= 0:
		return []
	return [StringName("unit_tier_%d" % definition.tier)]

static func _magnitude_for(stat: GameEnums.UnitUpgradeStat) -> float:
	match stat:
		GameEnums.UnitUpgradeStat.ATTACK_DAMAGE:
			return DAMAGE_MULTIPLIER
		GameEnums.UnitUpgradeStat.MAX_HP:
			return MAX_HP_MULTIPLIER
		GameEnums.UnitUpgradeStat.MOVE_SPEED:
			return MOVE_SPEED_MULTIPLIER
		GameEnums.UnitUpgradeStat.VISION_RADIUS:
			return VISION_RADIUS_BONUS
		_:  # GUNPOWDER_RELIEF
			return GUNPOWDER_RELIEF

## Period-appropriate node names. Tier 4-5 units are vehicles (design_doc.md
## §4 labels every one of them "... Vehicle"), so they take a mechanical
## variant — "Sabre Drill" reads wrong on a Holt Breaker.
static func _stat_title(stat: GameEnums.UnitUpgradeStat, tier: int) -> String:
	var is_vehicle := tier >= 4
	match stat:
		GameEnums.UnitUpgradeStat.ATTACK_DAMAGE:
			return "Ordnance Refit" if is_vehicle else "Weapons Drill"
		GameEnums.UnitUpgradeStat.MAX_HP:
			return "Armour Plating" if is_vehicle else "Field Kit & Padding"
		GameEnums.UnitUpgradeStat.GUNPOWDER_RELIEF:
			return "Munitions Discipline"
		GameEnums.UnitUpgradeStat.MOVE_SPEED:
			return "Uprated Boiler" if is_vehicle else "Remount Programme"
		_:  # VISION_RADIUS
			return "Signals & Field Glasses"

static func _stat_description(stat: GameEnums.UnitUpgradeStat, unit_name: String) -> String:
	match stat:
		GameEnums.UnitUpgradeStat.ATTACK_DAMAGE:
			return "Every %s deals %d%% more damage." % [unit_name, int(round((DAMAGE_MULTIPLIER - 1.0) * 100.0))]
		GameEnums.UnitUpgradeStat.MAX_HP:
			return "Every %s has %d%% more health, granted immediately to those already in the field." % [unit_name, int(round((MAX_HP_MULTIPLIER - 1.0) * 100.0))]
		GameEnums.UnitUpgradeStat.GUNPOWDER_RELIEF:
			return "Halves the penalty a %s suffers when the Gunpowder stockpile runs dry." % unit_name
		GameEnums.UnitUpgradeStat.MOVE_SPEED:
			return "Every %s moves %d%% faster." % [unit_name, int(round((MOVE_SPEED_MULTIPLIER - 1.0) * 100.0))]
		_:  # VISION_RADIUS
			return "Every %s sees %d hex further." % [unit_name, int(VISION_RADIUS_BONUS)]
