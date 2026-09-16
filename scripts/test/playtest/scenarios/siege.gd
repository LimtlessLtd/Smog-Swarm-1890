extends "res://scripts/test/playtest/scenarios/scenario_base.gd"

## SIEGE — the starting settlement walled by WallManager.seed_starting_defenses()
## (which has no production caller as of 2026-09-16, so a real new game starts
## unwalled — the scenario calls it the way verify_gates.gd does) with six Truncheoneers on garrison, and a 3,000-strong horde placed on an
## adjacent hex on day 2. Measures the siege arc PLAYER_EXPERIENCE.md describes:
## contact, pressure, breach, response, recovery.

const _HORDE_SIZE: int = 3000

var _spawned: bool = false
var _horde_id: int = -1
var _spawn_hex: Vector2i
var _breach_day: int = -1
var _horde_dead_day: int = -1


func days() -> int:
	return 6


func checkpoints() -> Array:
	return [2, 3, 6]


func setup(ctx) -> void:
	ctx.grant({GameEnums.ResourceType.WOOD: 2000.0, GameEnums.ResourceType.FOOD: 1000.0})
	ctx.place(GameEnums.BuildingType.WOODEN_HOUSES, ctx.start_hex)
	ctx.train(GameEnums.UnitType.TRUNCHEONEER, 6)
	ctx.walls.seed_starting_defenses()
	ctx.note("%d wall pieces around the start" % ctx.walls.get_segments().size())


func on_day(ctx, day: int) -> void:
	if day == 2 and not _spawned:
		_spawned = true
		for unit in ctx.living_units():
			ctx.orders.issue_garrison_order(unit)
		_spawn_hex = ctx.hex_at_distance(1, true, false)
		var horde: Horde = ctx.spawn_horde(_spawn_hex, _HORDE_SIZE)
		_horde_id = horde.id if horde else -1
		ctx.note("%d units garrisoned; horde %d (%d) placed at %s" % [ctx.living_units().size(), _horde_id, _HORDE_SIZE, _spawn_hex])
	if _breach_day < 0 and int(ctx.telemetry.report()["counters"].get("wall_breaches", 0)) > 0:
		_breach_day = day
	if _spawned and _horde_dead_day < 0:
		var alive := false
		for horde: Horde in ctx.hordes.get_all_hordes():
			if horde.id == _horde_id and horde.size > 0:
				alive = true
		if not alive:
			_horde_dead_day = day


func assess(ctx) -> Array:
	var t: Dictionary = ctx.telemetry.report()
	var c: Dictionary = t["counters"]
	var out: Array = []
	var wall_hits: int = int(c.get("wall_damage_events", 0))
	var engagements: int = int(c.get("engagements", 0))
	out.append(check("DEF-1", "Does a horde next door actually besiege the settlement?",
		"%d wall damage events, %d engagements" % [wall_hits, engagements], wall_hits == 0,
		"Hordes WANDER unless attracted, and residents never attack buildings (D49), so a siege is not guaranteed."))
	out.append(check("DEF-2", "Do walls buy time rather than immunity?",
		("breached day %d" % _breach_day) if _breach_day > 0 else "no breach",
		wall_hits > 0 and _breach_day < 0 and int(c.get("buildings_ruined", 0)) == 0,
		"decisions.md D17: walls buy time, never safety. Unbreached AND undamaged colony under a 3,000 horde = immunity."))
	out.append(check("DEF-3", "Did the defenders have anything to do during the siege?",
		"%d engagements, %d units lost" % [engagements, int(c.get("units_removed", 0))], engagements == 0,
		"Units fight only when sharing a hex with the horde; nobody can shoot from a wall today."))
	out.append(check("DEF-4", "Is the outcome a setback rather than an ending?",
		"%d ruined, horde destroyed day %d" % [int(c.get("buildings_ruined", 0)), _horde_dead_day],
		t["firsts_game_seconds"].has("campaign_lost"),
		"PLAYER_EXPERIENCE.md: a lost district is a setback; the campaign ending here would be the wrong stakes."))
	return out
