extends "res://scripts/test/playtest/scenarios/scenario_base.gd"

## VERTICAL SLICE — VerticalSliceConfig played through by a scripted player, to
## measure whether the slice's beats land inside 10-20 real minutes and whether
## the player's choices change the outcome. Variants are three players:
##
## - (default) "hold": clears the moor; on the report trains six Toxophilites at
##   the Garrison and, at dusk, pulls the whole squad onto the wall facing the
##   horde, lamps lit; resumes clearing once the horde is gone.
## - "naive": the same, without training anyone — the ten it started with.
## - "dark": clears; switches every Watchtower and the Brickworks off the moment
##   the horde is reported, back on at dawn.
## - "ignore": clears and never reacts to the horde.
##
## The debrief's claims are the evidence here: does going dark change whether the
## horde comes, does holding the wall change whether it breaches.

const _ARCHER_INSET_METRES: float = 15.0
const _TRAINED_ARCHERS: int = 6

var _director: VerticalSliceDirector
var _log: ConsequenceLog
var _finished_at: float = -1.0
var _outcome: StringName = &""
var _reported_at: float = -1.0
var _attracted_at: float = -1.0
var _siege_at: float = -1.0
var _siege_segment: WallSegment = null
var _defending: bool = false
var _returned_to_clearing: bool = false
var _dark: bool = false
var _dispatches: Array[String] = []
var _farm_ordered: bool = false


func launch_vertical_slice() -> bool:
	return true


func days() -> int:
	return 3


func checkpoints() -> Array:
	return [0]


## Report, dusk, siege under way, siege late, after. Game-seconds since the start.
func shot_seconds() -> Array:
	return [800.0, 1215.0, 1300.0, 1500.0, 1900.0]


## Hex scale (the town, the moor and the ring the lamps reach) and wall scale.
func shot_zooms() -> Array:
	return [0.3, 5.0]


func setup(ctx) -> void:
	_director = ctx.main.get_node("VerticalSliceDirector")
	_log = ctx.main.get_node("ConsequenceLog")
	if not _director.is_active():
		ctx.note("the slice director is not active — GameLaunchState did not carry the slice")
		return
	_director.dispatch.connect(func(title: String, _body: String, _world: Vector2, _zoom: float, _urgent: bool) -> void:
		_dispatches.append("%s %s" % [_real(_director.get_elapsed_seconds()), title])
		ctx.note("dispatch at %s: %s" % [_real(_director.get_elapsed_seconds()), title]))
	_director.slice_finished.connect(func(outcome: StringName) -> void:
		_outcome = outcome
		_finished_at = _director.get_elapsed_seconds())
	ctx.hordes.horde_attracted.connect(func(horde: Horde, _s: BuildingInstance, _k: StringName) -> void:
		if horde == _director.get_horde() and _attracted_at < 0.0:
			_attracted_at = _director.get_elapsed_seconds())
	ctx.hordes.horde_siege_started.connect(func(horde: Horde, segment: WallSegment) -> void:
		if horde == _director.get_horde():
			if _siege_at < 0.0:
				_siege_at = _director.get_elapsed_seconds()
			_siege_segment = segment)
	ctx.note("slice start %s: %d buildings, %d units, %d wall pieces, target %d residents" % [
		ctx.start_hex, ctx.buildings.get_all_buildings().size(), ctx.living_units().size(), ctx.walls.get_segments().size(), _director.get_target_seeded()])
	# The first slice start, (79, 119), had no unit route out at all (a PEAT_BOG
	# feature on an URBAN hex); this note is what would show that again.
	var route := HexPathfinder.find_path(ctx.main.get_node("WorldRoot/HexGridMap"), ctx.start_hex, VerticalSliceConfig.TARGET_HEX, ctx.main.get_node("LogisticsNetwork"), ctx.walls, true)
	ctx.note("unit route start -> target: %s" % str(route))
	ctx.attack_move_all(VerticalSliceConfig.TARGET_HEX)


func on_day(ctx, _day: int) -> void:
	if _director == null:
		return
	var where: Dictionary = {}
	for unit in ctx.living_units():
		var key := "%s %s" % [unit.hex_coord, GameEnums.UnitOrderType.keys()[unit.order]]
		where[key] = int(where.get(key, 0)) + 1
	ctx.note("units: %s; target %d dead; contact kills there %d" % [where, ctx.infestation.zombie_count_at(VerticalSliceConfig.TARGET_HEX), _log.get_contact_kills_at(VerticalSliceConfig.TARGET_HEX)])


func on_step(ctx, _step: int) -> void:
	if _director == null or not _director.is_active() or _finished_at >= 0.0:
		return
	var horde := _director.get_horde()
	if not _farm_ordered and ctx.infestation.is_cleared(VerticalSliceConfig.TARGET_HEX):
		_farm_ordered = true
		ctx.note("farm on the cleared moor at %s: %s" % [_real(_director.get_elapsed_seconds()), ctx.place(GameEnums.BuildingType.SMALLHOLDING_FARM, VerticalSliceConfig.TARGET_HEX)])
	if horde != null and _reported_at < 0.0:
		_reported_at = _director.get_elapsed_seconds()
		if ctx.variant == "dark":
			_set_lights(ctx, false)
		if ctx.variant == "" or ctx.variant == "hold":
			var started: int = ctx.train(GameEnums.UnitType.TOXOPHILITE, _TRAINED_ARCHERS)
			ctx.note("trained %d Toxophilites on the report; wood left %.0f" % [started, ctx.resources.get_amount(GameEnums.ResourceType.WOOD)])
	if ctx.variant == "dark" and _dark and TimeCycleManager.is_day() and _director.get_elapsed_seconds() > 2400.0:
		_set_lights(ctx, true)
	if ctx.variant != "" and ctx.variant != "hold" and ctx.variant != "naive":
		return
	if horde != null and not _defending and (TimeCycleManager.is_night() or horde.state == GameEnums.HordeState.ATTRACTED or horde.state == GameEnums.HordeState.ATTACKING):
		_defending = true
		_man_wall_facing(ctx, horde)
	if _defending and _siege_segment != null and horde != null:
		_station_on_segment(ctx, horde, _siege_segment)
		_siege_segment = null
	if _defending and horde == null and not _returned_to_clearing:
		_returned_to_clearing = true
		ctx.note("horde gone at %s; squad back to clearing" % _real(_director.get_elapsed_seconds()))
		ctx.attack_move_all(VerticalSliceConfig.TARGET_HEX)


func _set_lights(ctx, on: bool) -> void:
	_dark = not on
	for instance: BuildingInstance in ctx.buildings.get_buildings_at(ctx.start_hex):
		if not (instance.definition.lit_at_night or instance.definition.noise_source_db > 0.0):
			continue
		if on:
			ctx.buildings.restart_building(instance)
		else:
			ctx.buildings.power_down_building(instance)
	ctx.note("lights %s at %s" % ["on" if on else "off", _real(_director.get_elapsed_seconds())])


## Before the siege: to the start hex's edge toward the horde.
func _man_wall_facing(ctx, horde: Horde) -> void:
	var direction := (HexCoord.axial_to_world(horde.hex_coord) - HexCoord.axial_to_world(ctx.start_hex)).normalized()
	var local := direction * HexCoord.HEX_SIZE * 0.8
	for unit in ctx.living_units():
		ctx.orders.issue_move_order(unit, ctx.start_hex, local)
	ctx.note("horde turned toward the town at %s; squad ordered to the %s wall" % [_real(_director.get_elapsed_seconds()), VerticalSliceDirector._bearing_word(ctx.start_hex, horde.hex_coord)])


## Once the piece is known: just inside its midpoint.
func _station_on_segment(ctx, horde: Horde, segment: WallSegment) -> void:
	var mid := (segment.point_a + segment.point_b) * 0.5
	var inward := (HexCoord.axial_to_world(ctx.start_hex) - HexCoord.axial_to_world(horde.hex_coord)).normalized()
	var world := mid + inward * _ARCHER_INSET_METRES * HexCoord.WORLD_UNITS_PER_REAL_METER
	for unit in ctx.living_units():
		ctx.orders.issue_move_order(unit, ctx.start_hex, world - HexCoord.axial_to_world(ctx.start_hex))
	ctx.note("siege on a %s at %s; squad moved onto it" % ["gate" if segment.is_gate else "wall piece", _real(_director.get_elapsed_seconds())])


func assess(ctx) -> Array:
	var out: Array = []
	if _director == null or not _director.is_active():
		out.append(check("SLICE", "Did the slice start?", "no", true, "VerticalSliceDirector inactive."))
		return out
	var totals := _log.get_totals()
	var objectives := _director.get_objectives()
	var summary: Array[String] = []
	for objective in objectives:
		summary.append("%s=%s (%s)" % [objective["id"], objective["state"], objective["detail"]])
	var length := _finished_at if _finished_at >= 0.0 else _director.get_elapsed_seconds()
	out.append(check("SLICE-LENGTH", "Does the slice end inside 10-20 real minutes?",
		"%s, outcome %s" % [_real(length), _outcome if _outcome != &"" else "unfinished"], _finished_at < 0.0 or length < 1800.0 or length > 6000.0,
		"The ask: a 10-20 minute vertical slice. This player reacts instantly and never reads a dispatch, so its length is a floor for a person's: concern under 6 real minutes (1,800 game-seconds) or over 20."))
	out.append(check("HORDE-1", "Was the horde reported before it arrived?",
		"reported %s, attracted %s, siege %s" % [_real(_reported_at), _real(_attracted_at), _real(_siege_at)],
		_reported_at < 0.0 or (_siege_at >= 0.0 and _siege_at <= _reported_at),
		"The scouting dispatch fires on release; it must precede any siege."))
	out.append(check("HORDE-2", "Was the warning long enough to act on?",
		"%s from report to siege" % (_real(_siege_at - _reported_at) if _siege_at >= 0.0 else "no siege"),
		_siege_at >= 0.0 and _siege_at - _reported_at < 300.0,
		"Under one real minute (300 game-seconds) between report and contact is not enough to move a squad and decide on lamps."))
	out.append(check("HORDE-4", "Did this player's choice about the horde show in the outcome?",
		"variant %s: attracted %s, siege %s, kills from cover %d, breaches %d, units lost %d" % [ctx.variant if ctx.variant else "hold", _attracted_at >= 0.0, _siege_at >= 0.0, int(totals["kills_from_cover"]), _count(_log, ConsequenceLog.KIND_BREACH), int(totals["units_lost"])],
		false, "Compare the three variants: dark should see no siege, hold no breach, ignore a breach."))
	out.append(check("EXP-1", "Was the first clear an operation of minutes?",
		"; ".join(summary), not _objective_done(objectives, VerticalSliceDirector.OBJECTIVE_CLEAR),
		"The target must clear inside the slice."))
	var hud: VerticalSliceHUD = ctx.main.get_node("VerticalSliceHUD")
	var debrief := hud.get_debrief_preview(_outcome if _outcome != &"" else &"time")
	for line in debrief["why"]:
		ctx.note("DEBRIEF WHY: " + line)
	for line in debrief["timeline"]:
		ctx.note("DEBRIEF TIMELINE: " + line)
	out.append(check("DEBRIEF", "Does the debrief say why, not only what?",
		"%d why-lines, %d timeline lines: %s" % [debrief["why"].size(), debrief["timeline"].size(), debrief["title"]], debrief["why"].size() < 2,
		"The ask: 'immediately understand why what I did mattered'. At least the horde and the ground each need a cause."))
	out.append(check("FEEDBACK", "Did the world explain itself?",
		"%d dispatches: %s | %d log entries" % [_dispatches.size(), " / ".join(_dispatches), _log.get_entries().size()], _dispatches.size() < 4,
		"Start, report, nightfall and at least one horde response should all be spoken."))
	return out


## Follows the action so each checkpoint frames what a player would be looking at:
## the sieged piece while there is one, the horde while it is out, the town and the
## moor otherwise.
func camera_focus(ctx) -> Vector2:
	var horde: Horde = _director.get_horde() if _director else null
	if horde != null:
		var segment := ctx.hordes.get_sieged_segment(horde) as WallSegment
		if segment != null:
			return (segment.point_a + segment.point_b) * 0.5
		return (HexCoord.axial_to_world(ctx.start_hex) + HexCoord.axial_to_world(horde.hex_coord) + horde.local_position) * 0.5
	return (HexCoord.axial_to_world(ctx.start_hex) + HexCoord.axial_to_world(VerticalSliceConfig.TARGET_HEX)) * 0.5


static func _objective_done(objectives: Array[Dictionary], id: StringName) -> bool:
	for objective in objectives:
		if objective["id"] == id:
			return objective["state"] == &"done"
	return false


static func _count(log: ConsequenceLog, kind: StringName) -> int:
	var n := 0
	for entry in log.get_entries():
		if entry["kind"] == kind:
			n += 1
	return n


static func _real(game_seconds: float) -> String:
	if game_seconds < 0.0:
		return "never"
	var real := int(round(game_seconds / DEFAULT_SPEED))
	return "%d:%02d" % [real / 60, real % 60]
