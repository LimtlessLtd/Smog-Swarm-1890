extends "res://scripts/test/playtest/scenarios/scenario_base.gd"

## OPENING — the first twenty in-game days with a plain, sensible build: housing
## and clay on day 1, four Tier 0 units, a probe into the nearest ring-1 hex on
## day 3, a Watchtower on day 6. Not an optimal build order; the question is what
## the opening gives an ordinary player to do and how soon it pushes back.

var _probe_target: Vector2i
var _probe_ordered: bool = false


func days() -> int:
	return 20


func checkpoints() -> Array:
	return [0, 5, 20]


func setup(ctx) -> void:
	ctx.note("start stockpile Wood %.0f Food %.0f" % [
		ctx.resources.get_amount(GameEnums.ResourceType.WOOD), ctx.resources.get_amount(GameEnums.ResourceType.FOOD)])
	ctx.place(GameEnums.BuildingType.WOODEN_HOUSES, ctx.start_hex)
	ctx.place(GameEnums.BuildingType.CLAY_PIT, ctx.start_hex)
	ctx.train(GameEnums.UnitType.TRUNCHEONEER, 2)
	ctx.train(GameEnums.UnitType.TOXOPHILITE, 2)
	_probe_target = ctx.hex_at_distance(1, false)


func on_day(ctx, day: int) -> void:
	if day >= 3 and not _probe_ordered and not ctx.living_units().is_empty():
		_probe_ordered = true
		ctx.note("probe %d units into %s (infestation %.0f%%)" % [ctx.living_units().size(), _probe_target, ctx.infestation.infestation_at(_probe_target)])
		ctx.attack_move_all(_probe_target)
	if day == 6:
		ctx.place(GameEnums.BuildingType.WATCHTOWER, ctx.start_hex)
		ctx.place(GameEnums.BuildingType.LUMBER_YARD, ctx.start_hex)


func assess(ctx) -> Array:
	var t: Dictionary = ctx.telemetry.report()
	var firsts: Dictionary = t["firsts_game_seconds"]
	var counters: Dictionary = t["counters"]
	var out: Array = []

	# 3 real minutes: TAB's first unit is out in well under one; three is generous.
	var first_unit: float = firsts.get("first_unit_trained", INF)
	out.append(check("OPEN-1", "How long until the player commands their first unit?",
		"%s real min" % real_minutes(first_unit), first_unit > 3.0 * 60.0 * DEFAULT_SPEED,
		"Training is a whole-day job, so this is bounded below by one day = 8 real minutes at default speed."))

	# 10 real minutes of nothing is the 'waiting' failure mode named in PLAYER_EXPERIENCE.md.
	var first_action_back: float = minf(float(firsts.get("first_engagement", INF)), float(firsts.get("first_horde_contact", INF)))
	out.append(check("OPEN-2", "How long until the world pushes back (first fight or first horde at a building)?",
		"%s real min" % real_minutes(first_action_back), first_action_back > 10.0 * 60.0 * DEFAULT_SPEED,
		"The probe into ring 1 is the player's own first fight; a horde at the colony is the world's."))

	var ruined: int = int(counters.get("buildings_ruined", 0))
	var warned: int = int(t["hordes_seen_before_contact"])
	var contacts: int = int(t["hordes_that_made_contact"])
	out.append(check("OPEN-3", "Does every horde that reaches the colony get seen first?",
		"%d of %d seen before contact" % [warned, contacts], contacts > warned,
		"Seen = the horde's hex was fog-VISIBLE at any step before contact. No warning = no counterplay."))
	out.append(check("OPEN-4", "Does the opening colony survive twenty days of ordinary play?",
		"%d buildings ruined" % ruined, ruined > 0 and TickManager.current_day <= 10,
		"Losses are fine; losses before day 10 with no warning are the unfair-opening case."))

	var rejections: int = int(counters.get("placements_rejected", 0))
	out.append(check("OPEN-5", "Did the obvious opening builds place?",
		"%d rejected" % rejections, rejections > 0,
		"A rejected obvious build in the first minutes is a readability problem before it is a balance one."))
	return out
