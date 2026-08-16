class_name UnitUpgrades
extends RefCounted

## Resolves a unit's EFFECTIVE stats — its UnitDefinition baseline plus
## whatever per-unit research upgrades the campaign has actually completed
## (UnitUpgradeCatalog). A pure, stateless static utility with no NodePath
## exports, no _ready(), and no reference to any runtime Node: the
## TechManager arrives as a plain parameter, the same shape
## HexPathfinder.is_water_crossing_blocked() and CombatEngine.
## resolve_engagement() already use for their own dependencies.
##
## **Derived, never stored.** design_doc.md §4 requires upgrades to
## "auto-apply to active & future units", and the cheapest way to guarantee
## that is to keep no per-unit copy of an upgrade at all — an upgrade
## becomes true for every unit of that type the instant its tech completes,
## because nothing cached the old value. That also means this adds NOTHING
## to the save file: which upgrades are researched is already in
## TechManager's own save state, and re-deriving from it is exactly what
## makes a loaded save agree with itself.
##
## The one exception, and it's deliberate: MAX_HP. A unit's current_hp is
## real per-instance state, so raising its ceiling has to hand the active
## unit the difference as well or the upgrade would read as "your health bar
## got emptier". UnitManager owns that grant — see its own tech_researched
## handler. Everything else here is pure derivation.
##
## Every function takes a possibly-null `tech_manager` and falls back to the
## raw definition value when it's null, matching the project's existing
## "optional dependency, unset means the feature is simply off" convention
## (BuildingManager.tech_manager_path's own doc comment). That's what lets
## the read sites wire this in without any of them becoming
## TechManager-mandatory.

## Multiplier to fold into the damage_multiplier CombatCoordinator already
## passes CombatEngine — deliberately a multiplier rather than an effective
## attack_damage, so it composes with morale/veterancy/day-night through the
## seam that already exists instead of needing a new one.
static func damage_multiplier(tech_manager: TechManager, definition: UnitDefinition) -> float:
	return _multiplier(tech_manager, definition, GameEnums.UnitUpgradeStat.ATTACK_DAMAGE)

## Effective max HP — an absolute value, not a multiplier, because every
## caller (the HP bar, UnitMorale's HP fraction, the retrain rescale)
## compares current_hp against it directly.
static func max_hp(tech_manager: TechManager, definition: UnitDefinition) -> float:
	if not definition:
		return 0.0
	return definition.max_hp * _multiplier(tech_manager, definition, GameEnums.UnitUpgradeStat.MAX_HP)

static func move_speed_multiplier(tech_manager: TechManager, definition: UnitDefinition) -> float:
	if not definition:
		return 1.0
	return definition.move_speed_multiplier * _multiplier(tech_manager, definition, GameEnums.UnitUpgradeStat.MOVE_SPEED)

## Flat hex-ring bonus applied on top of the definition's own radius, not a
## multiplier — most of the roster sits at vision_radius 0, and a multiplier
## off 0 is still 0 (see GameEnums.UnitUpgradeStat.VISION_RADIUS).
static func vision_radius(tech_manager: TechManager, definition: UnitDefinition) -> int:
	if not definition:
		return 0
	return definition.vision_radius + int(_sum(tech_manager, definition, GameEnums.UnitUpgradeStat.VISION_RADIUS))

## The two forced-melee multipliers CombatEngine would otherwise use
## unmodified, eased toward 1.0 (no penalty) by the researched relief
## fraction. Returned as a pair because the penalty IS a pair — softening
## only the outgoing half would quietly change what the mechanic means.
## Relief is clamped to 1.0 so stacking can never invert the penalty into a
## bonus.
static func forced_melee_multipliers(tech_manager: TechManager, definition: UnitDefinition) -> Dictionary:
	var relief := clampf(_sum(tech_manager, definition, GameEnums.UnitUpgradeStat.GUNPOWDER_RELIEF), 0.0, 1.0)
	return {
		"outgoing": lerpf(CombatEngine.FORCED_MELEE_DAMAGE_MULTIPLIER, 1.0, relief),
		"incoming": lerpf(CombatEngine.FORCED_MELEE_DAMAGE_TAKEN_MULTIPLIER, 1.0, relief),
	}

## True once `unit_type`'s upgrade at `upgrade_index` is researched — for UI
## that wants to show which of a unit's two upgrades are in hand without
## reconstructing tech ids itself.
static func is_researched(tech_manager: TechManager, unit_type: GameEnums.UnitType, upgrade_index: int) -> bool:
	if not tech_manager:
		return false
	return tech_manager.is_researched(UnitUpgradeCatalog.tech_id_for(unit_type, upgrade_index))

## Product of every researched upgrade matching `stat`. 1.0 (no change) when
## none are, which is what makes an unwired TechManager behave exactly as
## the game did before upgrades existed.
static func _multiplier(tech_manager: TechManager, definition: UnitDefinition, stat: GameEnums.UnitUpgradeStat) -> float:
	if not tech_manager or not definition:
		return 1.0
	var result := 1.0
	for upgrade in UnitUpgradeCatalog.get_upgrades_for(definition.unit_type):
		if upgrade.stat == stat and tech_manager.is_researched(upgrade.tech_id):
			result *= upgrade.magnitude
	return result

## Sum of every researched upgrade matching `stat` — for the additive stats
## (flat vision rings, relief fractions) where multiplying would be wrong.
static func _sum(tech_manager: TechManager, definition: UnitDefinition, stat: GameEnums.UnitUpgradeStat) -> float:
	if not tech_manager or not definition:
		return 0.0
	var result := 0.0
	for upgrade in UnitUpgradeCatalog.get_upgrades_for(definition.unit_type):
		if upgrade.stat == stat and tech_manager.is_researched(upgrade.tech_id):
			result += upgrade.magnitude
	return result
