extends "res://scripts/test/playtest/scenarios/scenario_base.gd"

## EXPANSION — clear the least-populated ring-1 hex with a Tier 0 force, then
## claim it with a Lumber Yard. Starting resources are topped up so the question
## is the clearing and the reward, not the opening economy (opening.gd owns that).

var _target: Vector2i
var _ordered: bool = false
var _cleared_day: int = -1
var _claimed: bool = false
var _start_infestation: float = 0.0
var _start_zombies: int = 0


func days() -> int:
	return 15


func checkpoints() -> Array:
	return [3, 15]


func setup(ctx) -> void:
	ctx.grant({GameEnums.ResourceType.WOOD: 2000.0, GameEnums.ResourceType.FOOD: 1000.0})
	ctx.place(GameEnums.BuildingType.WOODEN_HOUSES, ctx.start_hex)
	ctx.place(GameEnums.BuildingType.WOODEN_HOUSES, ctx.start_hex)
	ctx.train(GameEnums.UnitType.TRUNCHEONEER, 8)
	ctx.train(GameEnums.UnitType.TOXOPHILITE, 4)
	_target = ctx.hex_at_distance(1, false)
	_start_infestation = ctx.infestation.infestation_at(_target)
	_start_zombies = ctx.infestation.zombie_count_at(_target)
	ctx.note("target %s: %d zombies, %.1f%% infested, capacity %d" % [_target, _start_zombies, _start_infestation, ctx.infestation.capacity_at(_target)])


func on_day(ctx, day: int) -> void:
	if not _ordered and not ctx.living_units().is_empty():
		_ordered = true
		ctx.note("attack-move %d units into %s" % [ctx.living_units().size(), _target])
		ctx.attack_move_all(_target)
	if _cleared_day < 0 and ctx.infestation.is_cleared(_target):
		_cleared_day = day
		ctx.note("%s cleared (%d zombies left)" % [_target, ctx.infestation.zombie_count_at(_target)])
	if _cleared_day >= 0 and not _claimed:
		_claimed = ctx.place(GameEnums.BuildingType.LUMBER_YARD, _target)
		if _claimed:
			ctx.note("claimed %s with a Lumber Yard" % _target)


func camera_focus(ctx) -> Vector2:
	return HexCoord.axial_to_world(_target)


func assess(ctx) -> Array:
	var t: Dictionary = ctx.telemetry.report()
	var counters: Dictionary = t["counters"]
	var out: Array = []
	var clear_seconds: float = float(_cleared_day - 1) * TickManager.DAY_LENGTH_SECONDS if _cleared_day > 0 else INF
	# 20 real minutes to take the first neighbouring hex is already slow for a
	# genre where the first expansion is a few minutes' push.
	out.append(check("EXP-1", "How long does clearing the easiest neighbouring hex take?",
		("day %d (%s real min)" % [_cleared_day, real_minutes(clear_seconds)]) if _cleared_day > 0 else "not cleared in %d days" % days(),
		_cleared_day < 0 or clear_seconds > 20.0 * 60.0 * DEFAULT_SPEED,
		"Started at %d zombies / %.1f%%. Clearing is killing (decisions.md D8), so this is combat throughput." % [_start_zombies, _start_infestation]))
	out.append(check("EXP-2", "Does clearing unlock something the player wanted?",
		"Lumber Yard placed: %s" % _claimed, not _claimed,
		"The reward today is build rights only; a Lumber Yard gives the same flat output on any hex."))
	var lost: int = int(counters.get("units_removed", 0))
	out.append(check("EXP-3", "Did expansion cost anything?",
		"%d of 12 units lost, %d engagements" % [lost, int(counters.get("engagements", 0))], (lost == 0 and _cleared_day > 0) or lost >= 12,
		"No losses is 'expanding without resistance'; losing the whole force with nothing cleared is no counterplay. Both are concerns."))
	var exported: float = float(counters.get("exported_hordes", 0.0))
	out.append(check("EXP-4", "Did pushing out provoke a response from the map?",
		"%d exported hordes, %d reached a building" % [int(exported), int(t["hordes_that_made_contact"])],
		exported == 0.0 and int(t["hordes_that_made_contact"]) == 0,
		"PLAYER_EXPERIENCE.md: expansion should attract attention. Nothing ties export to the player's activity today (D39 is distance only)."))
	return out
