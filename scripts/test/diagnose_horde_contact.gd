extends Node

## Does the threat loop close? Do hordes actually reach the player's buildings,
## and what happens when they do. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/diagnose_horde_contact.tscn
##
## Not a gated verification, deliberately — every number here moves the moment
## any of the balance constants under it move (ATTRACTION_THRESHOLD,
## ATTRACTION_AWARENESS_RADIUS, MovementStepper.BASE_MOVE_SPEED, the
## infestation export knobs). This exists so the person turning them can see
## what the loop does end to end.
##
## **Hand-drives _process() at a fixed delta rather than awaiting real frames.**
## Two reasons, both learned the hard way:
##  - `--headless` never focuses its root window, so BackgroundExecutionManager's
##    focus_exited handler pins Engine.max_fps to 15 and an awaited-frame loop
##    is bound to real time — 30 simulated days took over 20 real minutes at 6%
##    CPU. This is the same trap decisions.md D72 records for the profiler.
##  - A fixed delta is deterministic. Real frame deltas make the run
##    unrepeatable, which is useless for comparing a before and an after.
##
## diagnose_infestation_pressure.gd hand-drives run_daily_tick() for the same
## reason and documents the cost: no frames pass there, so nothing moves. This
## drives the frame-driven half instead — horde movement, wall siege and
## CombatCoordinator contact are all per-frame.
##
## Writes to stdout AND to user://horde_contact.txt, because Godot block-buffers
## a redirected stdout and a long run otherwise shows nothing until it exits.

const _DAYS: int = 30

## Simulated seconds per driven step. 5.0 puts a horde about a quarter of a hex
## per step at the unmodified BASE_MOVE_SPEED, which is fine-grained enough that
## no wall or building is stepped over, and cheap enough that 30 days is 14,400
## steps.
const _STEP_SECONDS: float = 5.0

## Reporting buckets only, not a mechanic. 0 = standing on a player building's
## own hex, which is what CombatCoordinator._siege_buildings() triggers on.
const _CONTACT_RADII: Array[int] = [0, 1, 2, 3, 5, 8]

## How many individual hordes the closest-approach table prints before it
## collapses into a count. Before the merge/split rate fix this run produced
## 1,092 hordes by day 15 and the table was unreadable.
const _MAX_HORDES_LISTED: int = 20

var _main: Node
var _buildings: BuildingManager
var _hordes: HordeManager
var _infestation: InfestationManager

var _closest_approach: Dictionary = {}  ## horde id -> smallest hex distance to any player building ever seen.
var _ever_attracted: Dictionary = {}
var _ever_attacking: Dictionary = {}
var _steps: Dictionary = {}             ## horde id -> hex crossings, for the travel-rate column.

var _damage_events: int = 0
var _damage_total: float = 0.0
var _ruined: int = 0
var _ruin_names: Array[String] = []
var _log: FileAccess


func _ready() -> void:
	_log = FileAccess.open("user://horde_contact.txt", FileAccess.WRITE)
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	var hex_grid_map: HexGridMap = _main.get_node("WorldRoot/HexGridMap")
	if not hex_grid_map.get_all_cells().is_empty():
		_run()
	else:
		hex_grid_map.generation_completed.connect(func(_count: int) -> void: _run())


func _say(line: String) -> void:
	print(line)
	if _log:
		_log.store_line(line)
		_log.flush()  ## Every line, so a run that is still going can be watched.


func _run() -> void:
	_buildings = _main.get_node("BuildingManager")
	_hordes = _main.get_node("HordeManager")
	_infestation = _main.get_node("InfestationManager")

	_buildings.building_damaged.connect(func(_i: BuildingInstance, amount: float) -> void:
		_damage_events += 1
		_damage_total += amount)
	_buildings.building_ruined.connect(func(instance: BuildingInstance, _lost: int) -> void:
		_ruined += 1
		_ruin_names.append("%s at %s (day %d)" % [instance.definition.display_name, instance.hex_coord, TickManager.current_day]))
	_hordes.horde_moved.connect(func(horde: Horde, _from: Vector2i, _to: Vector2i) -> void:
		_steps[horde.id] = int(_steps.get(horde.id, 0)) + 1)

	var start_hexes := _buildings.get_starting_settlement_hexes()
	var start: Vector2i = start_hexes[0] if not start_hexes.is_empty() else Vector2i.ZERO
	_say("=== Opening state ===")
	_say("  starting settlement: %s" % start)
	_say("  player buildings: %d" % _buildings.get_all_buildings().size())
	_say("  hordes on the map: %d (%d zombies)" % [_hordes.get_all_hordes().size(), _total_horde_size()])
	for horde: Horde in _hordes.get_all_hordes():
		_say("    horde %d: %d zombies at %s, %d hexes from the nearest building" % [
			horde.id, horde.size, horde.hex_coord, _distance_to_nearest_building(horde.hex_coord)])

	_say("\n=== Simulating %d days at %.1f s/step ===" % [_DAYS, _STEP_SECONDS])
	_simulate()
	_report_final()
	get_tree().quit(0)


## One driven step = one "frame" of _STEP_SECONDS. TickManager._process()
## advances the day and fires day_completed, which InfestationManager is
## already connected to; TimeCycleManager._process() flips the day/night phase
## HordeManager's speed multipliers read; HordeManager._process() moves,
## sieges, and emits horde_moved, which CombatCoordinator is already connected
## to. Everything else in the contact path is signal-driven off those three.
func _simulate() -> void:
	var steps_per_day := int(TickManager.DAY_LENGTH_SECONDS / _STEP_SECONDS)
	for day in range(_DAYS):
		for _step in range(steps_per_day):
			TickManager._process(_STEP_SECONDS)
			TimeCycleManager._process(_STEP_SECONDS)
			_hordes._process(_STEP_SECONDS)
			_sample()
		_report_day()


func _sample() -> void:
	for horde: Horde in _hordes.get_all_hordes():
		var distance := _distance_to_nearest_building(horde.hex_coord)
		if distance < int(_closest_approach.get(horde.id, 1 << 30)):
			_closest_approach[horde.id] = distance
		if horde.state == GameEnums.HordeState.ATTRACTED:
			_ever_attracted[horde.id] = true
		elif horde.state == GameEnums.HordeState.ATTACKING:
			_ever_attacking[horde.id] = true


func _report_day() -> void:
	var within_3 := 0
	var nearest := 1 << 30
	for horde: Horde in _hordes.get_all_hordes():
		var distance := _distance_to_nearest_building(horde.hex_coord)
		nearest = mini(nearest, distance)
		if distance <= 3:
			within_3 += 1
	_say("  day %2d: %2d hordes (%8d zombies), nearest %3d hexes, %d within 3, %d hits, %d ruined" % [
		TickManager.current_day, _hordes.get_all_hordes().size(), _total_horde_size(),
		nearest, within_3, _damage_events, _ruined])


func _report_final() -> void:
	_say("\n=== Closest each horde ever got to a player building ===")
	var buckets := {}
	for radius in _CONTACT_RADII:
		buckets[radius] = 0
	var ids := _closest_approach.keys()
	ids.sort_custom(func(a, b) -> bool: return int(_closest_approach[a]) < int(_closest_approach[b]))
	# Only the nearest few are printed individually — a run that fragments
	# badly produces thousands of hordes and the per-horde table stops being
	# readable long before it stops being long. The buckets below are the
	# summary; this is the detail for the ones that actually got close.
	for i in range(mini(_MAX_HORDES_LISTED, ids.size())):
		var id = ids[i]
		var labels: Array[String] = []
		if _ever_attracted.has(id):
			labels.append("ATTRACTED")
		if _ever_attacking.has(id):
			labels.append("ATTACKING")
		_say("  horde %-5d closest %3d hexes, %5d hexes travelled%s" % [
			id, int(_closest_approach[id]), int(_steps.get(id, 0)),
			("  [" + ", ".join(labels) + "]") if not labels.is_empty() else ""])
	if ids.size() > _MAX_HORDES_LISTED:
		_say("  ... and %d more, summarised below" % (ids.size() - _MAX_HORDES_LISTED))
	for id in ids:
		var distance: int = _closest_approach[id]
		for radius in _CONTACT_RADII:
			if distance <= radius:
				buckets[radius] = int(buckets[radius]) + 1

	var total := ids.size()
	_say("\n=== Hordes that ever came within N hexes of a player building ===")
	for radius in _CONTACT_RADII:
		_say("  within %d hexes: %d of %d (%.0f%%)" % [
			radius, buckets[radius], total, 100.0 * float(buckets[radius]) / maxf(1.0, float(total))])

	_say("\n=== What contact actually did ===")
	_say("  building damage events: %d, total damage %.1f" % [_damage_events, _damage_total])
	_say("  buildings ruined: %d" % _ruined)
	for ruin_name in _ruin_names:
		_say("    %s" % ruin_name)
	_say("  hordes that ever reached ATTRACTED: %d of %d" % [_ever_attracted.size(), total])
	_say("  hordes that ever reached ATTACKING: %d of %d" % [_ever_attacking.size(), total])

	_say("\n=== Travel rate (is BASE_MOVE_SPEED sane at this hex scale?) ===")
	var total_steps := 0
	for id in _steps:
		total_steps += int(_steps[id])
	var metres_per_hex := HexCoord.HEX_SIZE * 1.7320508075688772 / HexCoord.WORLD_UNITS_PER_REAL_METER
	var per_horde_per_day := float(total_steps) / maxf(1.0, float(total)) / float(_DAYS)
	_say("  %d hex crossings across %d hordes over %d days" % [total_steps, total, _DAYS])
	_say("  = %.1f hexes/horde/day = %.1f km/day at %.0f m per hex" % [
		per_horde_per_day, per_horde_per_day * metres_per_hex / 1000.0, metres_per_hex])

	# The fragmentation signal. A mean parked just above
	# HordeManager.SPLIT_MIN_SIZE is what unbounded splitting looks like.
	var live := _hordes.get_all_hordes()
	var largest := 0
	for horde: Horde in live:
		largest = maxi(largest, horde.size)
	_say("
=== Horde size at the end ===")
	_say("  %d hordes holding %d zombies: mean %.1f, largest %d (SPLIT_MIN_SIZE is %d)" % [
		live.size(), _total_horde_size(), float(_total_horde_size()) / maxf(1.0, float(live.size())),
		largest, HordeManager.SPLIT_MIN_SIZE])


## Hex distance to the nearest non-ruined player building, or a large sentinel
## if the player has none left standing.
func _distance_to_nearest_building(coord: Vector2i) -> int:
	var nearest := 1 << 30
	for building: BuildingInstance in _buildings.get_all_buildings():
		if building.is_ruined:
			continue
		nearest = mini(nearest, HexCoord.distance(coord, building.hex_coord))
	return nearest


func _total_horde_size() -> int:
	var total := 0
	for horde: Horde in _hordes.get_all_hordes():
		total += horde.size
	return total
