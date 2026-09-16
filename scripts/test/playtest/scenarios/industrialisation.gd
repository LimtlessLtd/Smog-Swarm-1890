extends "res://scripts/test/playtest/scenarios/scenario_base.gd"

## INDUSTRIALISATION — research building and unit tiers 1-5 back to back with
## research and materials granted, and record what each tier changes. The question
## is PLAYER_EXPERIENCE.md's "does each tier change what the player can DO, or does
## a number get bigger?" — answered from what the catalogues unlock, since the
## capability a tier adds is data, not something a simulation has to discover.

const _QUEUE: Array[StringName] = [
	&"building_tier_1", &"unit_tier_1", &"building_tier_2", &"unit_tier_2", &"building_tier_3",
	&"unit_tier_3", &"building_tier_4", &"unit_tier_4", &"building_tier_5", &"unit_tier_5",
]

var _index: int = 0
var _finished_day: Dictionary = {}


func days() -> int:
	return 60


func checkpoints() -> Array:
	return []


func setup(ctx) -> void:
	ctx.grant({GameEnums.ResourceType.RESEARCH_POINTS: 10000.0, GameEnums.ResourceType.IRON: 5000.0})
	_start_next(ctx)


func on_day(ctx, day: int) -> void:
	if _index < _QUEUE.size() and ctx.tech.is_researched(_QUEUE[_index]):
		_finished_day[String(_QUEUE[_index])] = day
		_index += 1
		_start_next(ctx)


func _start_next(ctx) -> void:
	if _index >= _QUEUE.size():
		return
	if not ctx.tech.start_research(_QUEUE[_index]):
		ctx.note("could not research %s: %s" % [_QUEUE[_index], ctx.tech.get_research_error(_QUEUE[_index])])
		_index = _QUEUE.size()


func assess(ctx) -> Array:
	var out: Array = []
	var tiers: Array = []
	var unit_rows: Array = []
	var linear := true
	var previous_ratio := -1.0
	for tier in range(6):
		var building_names: Array[String] = []
		for definition: BuildingDefinition in BuildingCatalog.get_all_definitions():
			if definition.tier == tier:
				building_names.append(definition.display_name)
		var units_in_tier := UnitCatalog.get_definitions_in_tier(tier)
		var roles := {}
		var hp_sum := 0.0
		var dmg_sum := 0.0
		for definition: UnitDefinition in units_in_tier:
			roles[GameEnums.UnitRole.keys()[definition.role]] = definition.display_name
			hp_sum += definition.max_hp
			dmg_sum += definition.attack_damage
		var n := maxf(1.0, float(units_in_tier.size()))
		unit_rows.append({"tier": tier, "units": roles, "mean_hp": snappedf(hp_sum / n, 0.1), "mean_damage": snappedf(dmg_sum / n, 0.1)})
		tiers.append({"tier": tier, "buildings": building_names,
			"researched_day": _finished_day.get("building_tier_%d" % tier, 0 if tier == 0 else -1)})
		if tier > 0:
			var ratio: float = (dmg_sum / n) / maxf(0.001, float(unit_rows[tier - 1]["mean_damage"]))
			if previous_ratio > 0.0 and absf(ratio - previous_ratio) > 0.5:
				linear = false
			previous_ratio = ratio

	out.append(check("IND-1", "What does each building tier unlock?", tiers, false,
		"Read the names: a tier that adds only bigger versions of existing buildings adds numbers, not capability."))
	out.append(check("IND-2", "Do unit tiers change tactics or only stats?", unit_rows, true,
		"CombatEngine resolves MELEE, RANGED and SPECIAL identically as a same-hex exchange with no range stat; the tier ladder is `3 + 2*tier` damage. Concern is recorded from the code, not measured here."))
	out.append(check("IND-3", "Is stat growth a smooth ramp with no step change?", "smooth: %s" % linear, linear,
		"A perfectly smooth ramp means no tier is a turning point the player feels."))
	var research_days: int = int(_finished_day.get("unit_tier_5", -1))
	out.append(check("IND-4", "How long is the full tech path with unlimited research points?",
		("day %d" % research_days) if research_days > 0 else "incomplete: %s" % str(_finished_day), research_days < 0,
		"Research is one tech at a time and counts whole days; this is the floor, before any economy."))
	return out
