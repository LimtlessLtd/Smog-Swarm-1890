extends "res://scripts/test/playtest/scenarios/scenario_base.gd"

## HORDE — a 2,000-strong horde appears five hexes out once the colony has a
## noise source (a Brickworks, after building_tier_1 — a Coal Mine cannot stand on
## the URBAN start hex; measured 2026-09-16). Measures what a
## player can know and do about it: when it becomes visible, whether it heads for
## the colony, how long they have, and what it does on arrival.
##
## Variants (--variant=):
##   (none)  a noisy colony — a Brickworks is placed so attraction has a source.
##   dark    the same colony, and every switchable building goes dark the moment
##           the horde is first visible: the counterplay vision.md P2 names.

const _HORDE_SIZE: int = 2000
const _SPAWN_DISTANCE: int = 5

var _horde_id: int = -1
var _spawn_hex: Vector2i
var _seen_seconds: float = -1.0
var _went_dark: bool = false
var _mine_attempted: bool = false
var _ever_attracted: bool = false
var _closest: int = 1 << 30


func days() -> int:
	return 12


func checkpoints() -> Array:
	return [4, 8, 12]


func setup(ctx) -> void:
	ctx.grant({GameEnums.ResourceType.WOOD: 1000.0, GameEnums.ResourceType.BRICKS: 500.0,
		GameEnums.ResourceType.RESEARCH_POINTS: 60.0, GameEnums.ResourceType.FOOD: 500.0})
	# Every noisy building is Tier 1+ (backlog: "17 of 42 buildings carry a
	# noise_source_db, every one of them industrial"), so the colony needs
	# building_tier_1 before it can make a sound for the horde to hear.
	# The starting colony has too little Energy capacity for a Brickworks (-30);
	# measured 2026-09-16, the placement was refused until a furnace stood.
	# Houses first: a furnace alone was also refused for capacity on day 1.
	ctx.place(GameEnums.BuildingType.WOODEN_HOUSES, ctx.start_hex)
	ctx.place(GameEnums.BuildingType.STEAM_FURNACE, ctx.start_hex)
	if not ctx.tech.start_research(&"building_tier_1"):
		ctx.note("could not research building_tier_1: %s" % ctx.tech.get_research_error(&"building_tier_1"))


func on_day(ctx, _day: int) -> void:
	if _horde_id != -1 or not ctx.tech.is_researched(&"building_tier_1"):
		return
	if not _mine_attempted:
		_mine_attempted = true
		ctx.note("capacity before Brickworks: Energy %.0f, Population %.0f" % [
			ctx.resources.get_amount(GameEnums.ResourceType.ENERGY), ctx.resources.get_amount(GameEnums.ResourceType.POPULATION)])
		ctx.place(GameEnums.BuildingType.BRICKWORKS, ctx.start_hex)
		return  ## A day for construction to start; the site is loud (D60) from placement.
	_spawn_hex = ctx.hex_at_distance(_SPAWN_DISTANCE, false, false)
	var horde: Horde = ctx.spawn_horde(_spawn_hex, _HORDE_SIZE)
	_horde_id = horde.id if horde else -2
	ctx.note("horde %d (%d) spawned at %s, %d hexes out" % [_horde_id, _HORDE_SIZE, _spawn_hex, _SPAWN_DISTANCE])


func on_step(ctx, _step: int) -> void:
	var horde := _find(ctx)
	if horde == null:
		return
	if horde.state == GameEnums.HordeState.ATTRACTED:
		_ever_attracted = true
	_closest = mini(_closest, HexCoord.distance(horde.hex_coord, ctx.start_hex))
	if _seen_seconds < 0.0 and ctx.fog.is_visible(horde.hex_coord):
		_seen_seconds = ctx.telemetry.elapsed()
		ctx.note("horde first visible at %s" % horde.hex_coord)
		if ctx.variant == "dark":
			_go_dark(ctx)


func _go_dark(ctx) -> void:
	_went_dark = true
	var count := 0
	for building: BuildingInstance in ctx.buildings.get_all_buildings():
		if ctx.buildings.can_power_down_building(building) and ctx.buildings.power_down_building(building):
			count += 1
	ctx.note("went dark: %d buildings switched off" % count)


func _find(ctx) -> Horde:
	for horde: Horde in ctx.hordes.get_all_hordes():
		if horde.id == _horde_id:
			return horde
	return null


func camera_focus(ctx) -> Vector2:
	var horde := _find(ctx)
	return HexCoord.axial_to_world(horde.hex_coord) + horde.local_position if horde else HexCoord.axial_to_world(ctx.start_hex)


func assess(ctx) -> Array:
	var t: Dictionary = ctx.telemetry.report()
	var firsts: Dictionary = t["firsts_game_seconds"]
	var counters: Dictionary = t["counters"]
	var contact: float = float(firsts.get("first_horde_contact", -1.0))
	var out: Array = []
	out.append(check("HORDE-1", "Can the player see a 2,000-strong horde before it arrives?",
		("visible after %s real min" % real_minutes(_seen_seconds)) if _seen_seconds >= 0.0 else "never visible",
		_seen_seconds < 0.0 or (contact >= 0.0 and _seen_seconds >= contact),
		"Visibility is fog-VISIBLE on the horde's hex; HUDReconTracker's ETA also needs the horde ATTRACTED."))
	var warning: float = contact - _seen_seconds if contact >= 0.0 and _seen_seconds >= 0.0 else -1.0
	# 2 real minutes: enough to switch buildings off and move a squad, the two
	# responses the game has. Less is a surprise, not a warning.
	out.append(check("HORDE-2", "How much warning does the player get?",
		("%s real min" % real_minutes(warning)) if warning >= 0.0 else ("no contact" if contact < 0.0 else "none"),
		contact >= 0.0 and warning < 2.0 * 60.0 * DEFAULT_SPEED,
		"Hordes move ~1 hex per 20 game-seconds (MovementStepper.BASE_MOVE_SPEED): 5 hexes is 20 real seconds at default speed."))
	out.append(check("HORDE-3", "Does the horde react to the colony at all?",
		"ATTRACTED ever: %s, closest %d hexes" % [_ever_attracted, _closest], not _ever_attracted and _closest > 1,
		"A horde that never notices the colony is 'numerous but strategically irrelevant'."))
	out.append(check("HORDE-4", "Does going dark change the outcome?" if ctx.variant == "dark" else "What does arrival cost the colony?",
		"%d buildings ruined, %d damage events, went dark: %s" % [int(counters.get("buildings_ruined", 0)), int(counters.get("building_damage_events", 0)), _went_dark],
		false,
		"Compare this row between the default run and --variant=dark; the difference IS the counterplay's value."))
	return out
