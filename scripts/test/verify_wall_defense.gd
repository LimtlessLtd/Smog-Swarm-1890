extends Node

## Locks down the wall fight: a horde drawn to a walled settlement sieges the wall
## piece in its way, siege pressure is contact-limited, and defenders standing
## within reach of that piece strike it from cover. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless scenes/test/verify_wall_defense.tscn
##
## What each check is for:
##
## 1. **A drawn horde sieges, at the wall.** A Bessemer complex inside the starting
##    perimeter draws an 800-strong horde from the next hex; it is stopped at a wall
##    piece, reports ATTACKING, `horde_siege_started` fires once, and it is standing
##    at that piece — not a hex away, where the whole-crossing wall check used to
##    stop it (found in the vertical slice, 2026-09-16).
## 2. **Pressure is contact-limited.** Wall damage per HordeManager.LOGIC_TICK_SECONDS
##    at night equals wall_contact_frontage() x WALL_DAMAGE_PER_CONTACT_ZOMBIE x
##    WALL_SIEGE_DAMAGE_MULTIPLIER x 2 — not the whole horde's damage.
## 3. **Reach decides who fights.** Archers beside the piece are defenders;
##    archers at the hex centre (kilometres away) are not; archers on the horde's
##    side of the wall are not.
## 4. **Striking from cover costs nothing.** A volley shrinks the horde and leaves
##    every defender's HP untouched, and engagement_resolved says `from_cover`.
## 5. **Holding the wall is a race the player can win or lose.** Undefended, the
##    piece breaches. Ten archers at it destroy the horde first. Three do not.
## 6. **The forecast tells the truth.** SiegeForecast.project() — what the siege
##    overlay's "at this rate" line and the debrief's counterfactual both read —
##    predicts each of those three races' outcome, and its time within
##    _FORECAST_TOLERANCE of the simulated one.
##
## Fixture rather than the real map, same reasoning verify_gates.gd gives.

const _FIXTURE_RADIUS: int = 3
const _HOME := Vector2i.ZERO
const _NEIGHBOUR := Vector2i(1, 0)
const _HORDE_SIZE: int = 800
const _NIGHT_PROGRESS: float = 0.75
const _STEP_SECONDS: float = 1.0
const _MAX_APPROACH_STEPS: int = 2000
const _MAX_SIEGE_STEPS: int = 20000
const _EPSILON: float = 0.001
const _MAX_SIEGE_STANDOFF_METRES: float = 50.0
const _FORECAST_TOLERANCE: float = 0.15

var _map: HexGridMap
var _resources: ResourceManager
var _buildings: BuildingManager
var _walls: WallManager
var _noise: NoiseManager
var _hordes: HordeManager
var _units: UnitManager
var _combat: CombatCoordinator
var _defense: WallDefenseController
var _failures: Array[String] = []
var _siege_started_events: int = 0
var _from_cover_events: int = 0


func _ready() -> void:
	TickManager.load_save_state({"current_day": 1, "elapsed_in_day": TickManager.DAY_LENGTH_SECONDS * _NIGHT_PROGRESS, "speed_index": 1})
	TimeCycleManager._process(0.0)

	_map = _add("res://scenes/world/HexGridMap.tscn", "HexGridMap", {})
	_map.auto_generate_on_ready = false
	_map.load_cells(_build_fixture_cells())
	_resources = _add("res://scenes/economy/ResourceManager.tscn", "ResourceManager", {})
	_buildings = _add("res://scenes/buildings/BuildingManager.tscn", "BuildingManager", {"hex_grid_map_path": "../HexGridMap", "resource_manager_path": "../ResourceManager"})
	_walls = _add("res://scenes/defense/WallManager.tscn", "WallManager", {"hex_grid_map_path": "../HexGridMap", "building_manager_path": "../BuildingManager"})
	_buildings.seed_starting_buildings()
	_walls.seed_starting_defenses()
	_noise = _add("res://scenes/world/NoiseManager.tscn", "NoiseManager", {"hex_grid_map_path": "../HexGridMap", "building_manager_path": "../BuildingManager"})
	_hordes = _add("res://scenes/world/HordeManager.tscn", "HordeManager", {"hex_grid_map_path": "../HexGridMap", "building_manager_path": "../BuildingManager", "wall_manager_path": "../WallManager", "noise_manager_path": "../NoiseManager"})
	_units = _add("res://scenes/units/UnitManager.tscn", "UnitManager", {"hex_grid_map_path": "../HexGridMap"})
	_combat = _add("res://scenes/units/CombatCoordinator.tscn", "CombatCoordinator", {"unit_manager_path": "../UnitManager", "horde_manager_path": "../HordeManager"})
	_defense = _add("res://scenes/defense/WallDefenseController.tscn", "WallDefenseController", {"unit_manager_path": "../UnitManager", "horde_manager_path": "../HordeManager", "combat_coordinator_path": "../CombatCoordinator"})
	_hordes.horde_siege_started.connect(func(_h: Horde, _s: WallSegment) -> void: _siege_started_events += 1)
	_combat.engagement_resolved.connect(func(_u: UnitInstance, _h: Horde, result: Dictionary) -> void:
		if result.get("from_cover", false):
			_from_cover_events += 1)

	if not TimeCycleManager.is_night():
		_failures.append("the clock was pinned to night but reads day — check 2's night multiplier is wrong")
	# Loud enough to reach the neighbouring hex; the only thing drawing the horde.
	var entries: Array[BuildingSaveEntry] = [BuildingSaveEntry.new(GameEnums.BuildingType.BESSEMER_SMELTING_COMPLEX, _HOME, 1, Vector2.ZERO, 0, BuildingCatalog.get_definition(GameEnums.BuildingType.BESSEMER_SMELTING_COMPLEX).get_max_hp())]
	_buildings.load_save_entries(entries, 2)
	_noise.recompute()

	var siege := _approach_and_siege()
	if siege.is_empty():
		_finish()
		return
	var horde: Horde = siege[0]
	var segment: WallSegment = siege[1]
	_check_pressure_is_contact_limited(horde, segment)
	_check_reach_decides_who_fights(horde, segment)
	_check_striking_from_cover_costs_nothing(horde, segment)
	_check_the_race()
	_finish()


func _finish() -> void:
	print()
	if _failures.is_empty():
		print("All wall-defence checks passed.")
		get_tree().quit(0)
	else:
		print("FAILED (%d):" % _failures.size())
		for failure in _failures:
			print("  " + failure)
		get_tree().quit(1)


## Check 1. Returns [horde, segment] or [] when no siege started.
func _approach_and_siege() -> Array:
	for existing in _hordes.get_all_hordes():
		_hordes.remove_horde(existing)
	_units.load_save_entries([], 1)
	for segment in _walls.get_segments():
		segment.current_hp = segment.get_max_hp()
	_siege_started_events = 0
	_hordes.spawn_horde_at(_NEIGHBOUR, _HORDE_SIZE)
	var horde: Horde = _hordes.get_all_hordes()[0]
	for _i in range(_MAX_APPROACH_STEPS):
		_hordes._process(_STEP_SECONDS)
		if _hordes.get_sieged_segment(horde) != null:
			break
	var segment := _hordes.get_sieged_segment(horde)
	if segment == null:
		_failures.append("an 800-strong horde drawn from %s toward a Bessemer complex inside the perimeter never sieged a wall piece (state %s, at %s)" % [_NEIGHBOUR, GameEnums.HordeState.keys()[horde.state], horde.hex_coord])
		return []
	if horde.state != GameEnums.HordeState.ATTACKING:
		_failures.append("a horde blocked at a wall piece reports %s, not ATTACKING" % GameEnums.HordeState.keys()[horde.state])
	if _siege_started_events != 1:
		_failures.append("horde_siege_started fired %d times for one siege, want 1" % _siege_started_events)
	var standoff := WallDefenseController.distance_to_segment_metres(HexCoord.axial_to_world(horde.hex_coord) + horde.local_position, segment)
	if _siege_started_events == 1:
		print("1. horde sieging piece %d from %.0f m away" % [segment.id, standoff])
	if standoff > _MAX_SIEGE_STANDOFF_METRES:
		_failures.append("the sieging horde stands %.0f m from the piece it is clawing at (want <= %.0f m)" % [standoff, _MAX_SIEGE_STANDOFF_METRES])
	return [horde, segment]


func _check_pressure_is_contact_limited(horde: Horde, segment: WallSegment) -> void:
	var before := segment.current_hp
	_hordes._process(HordeManager.LOGIC_TICK_SECONDS)
	var dealt := before - segment.current_hp
	var expected := float(HordeManager.wall_contact_frontage(horde.size)) * HordeManager.WALL_DAMAGE_PER_CONTACT_ZOMBIE * HordeManager.WALL_SIEGE_DAMAGE_MULTIPLIER * HordeManager.NIGHT_AGGRESSION_MULTIPLIER
	print("1-2. siege on piece %d (%s, %.0f HP): %.2f damage in one logic tick at night, want %.2f; whole-horde damage would be %.0f" % [segment.id, "gate" if segment.is_gate else "wall", segment.get_max_hp(), dealt, expected, horde.get_combat_damage() * HordeManager.WALL_SIEGE_DAMAGE_MULTIPLIER * 2.0])
	if absf(dealt - expected) > _EPSILON:
		_failures.append("one logic tick of siege dealt %.3f, want contact-limited %.3f" % [dealt, expected])


func _check_reach_decides_who_fights(horde: Horde, segment: WallSegment) -> void:
	_place_archers(3, _HOME, _beside_wall(segment, horde, 20.0))
	var beside := _defender_count(horde, segment)
	_place_archers(3, _HOME, Vector2.ZERO)
	var centre := _defender_count(horde, segment)
	_place_archers(3, horde.hex_coord, _beside_wall(segment, horde, -20.0, horde.hex_coord))
	var outside := _defender_count(horde, segment)
	print("3. defenders: beside the piece %d/3, at the hex centre %d/3, on the horde's side %d/3" % [beside, centre, outside])
	if beside != 3:
		_failures.append("archers 20 m inside the sieged piece counted %d defenders, want 3" % beside)
	if centre != 0:
		_failures.append("archers at the hex centre counted %d defenders — reach is not being applied" % centre)
	if outside != 0:
		_failures.append("archers on the horde's side of the wall counted %d defenders" % outside)


func _check_striking_from_cover_costs_nothing(horde: Horde, segment: WallSegment) -> void:
	_place_archers(5, _HOME, _beside_wall(segment, horde, 20.0))
	var hp_before: Array[float] = []
	for instance in _units.get_all_units():
		hp_before.append(instance.current_hp)
	var size_before := horde.size
	_from_cover_events = 0
	_defense.run_volley()
	var took_damage := false
	var i := 0
	for instance in _units.get_all_units():
		if absf(instance.current_hp - hp_before[i]) > _EPSILON:
			took_damage = true
		i += 1
	print("4. volley of 5: horde %d -> %d, from_cover events %d, any defender damaged %s" % [size_before, horde.size, _from_cover_events, took_damage])
	if horde.size >= size_before:
		_failures.append("a volley of five defenders did not shrink the horde")
	if took_damage:
		_failures.append("a defender striking from behind an unbreached wall took damage")
	if _from_cover_events != 5:
		_failures.append("engagement_resolved reported from_cover %d times for 5 defenders" % _from_cover_events)


func _check_the_race() -> void:
	var undefended := _run_race(0)
	var defended := _run_race(10)
	var thin := _run_race(3)
	print("5. night race vs %d: undefended %s; 10 archers %s; 3 archers %s" % [_HORDE_SIZE, undefended, defended, thin])
	if undefended["outcome"] != "breached":
		_failures.append("an undefended Wooden piece was not breached by an 800-strong horde (%s)" % undefended)
	if defended["outcome"] != "destroyed":
		_failures.append("ten archers at the piece did not destroy the horde before it breached (%s)" % defended)
	if thin["outcome"] != "breached":
		_failures.append("three archers held the piece against 800 — a thin defence should lose (%s)" % thin)
	var kills := SiegeForecast.kills_per_strike(UnitCatalog.get_definition(GameEnums.UnitType.TOXOPHILITE), TimeCycleManager.is_day())
	for pair in [[0, undefended], [10, defended], [3, thin]]:
		var simulated: Dictionary = pair[1]
		var forecast := SiegeForecast.project(_HORDE_SIZE, WallCatalog.get_max_hp(WallCatalog.WOODEN), pair[0], kills, TimeCycleManager.is_night())
		var want: StringName = &"breach" if simulated["outcome"] == "breached" else &"destroyed"
		var error := absf(float(forecast["seconds"]) - float(simulated.get("game_seconds", 0.0))) / maxf(1.0, float(simulated.get("game_seconds", 1.0)))
		print("6. forecast with %d archers: %s at %.0f game-s; simulated %s at %.0f (error %.0f%%)" % [pair[0], forecast["outcome"], forecast["seconds"], simulated["outcome"], simulated.get("game_seconds", 0.0), error * 100.0])
		if forecast["outcome"] != want:
			_failures.append("SiegeForecast predicts %s with %d archers where the siege %s" % [forecast["outcome"], pair[0], simulated["outcome"]])
		elif error > _FORECAST_TOLERANCE:
			_failures.append("SiegeForecast's time with %d archers is %.0f%% off the simulated siege" % [pair[0], error * 100.0])


## Resets the siege, stations `archers` beside the sieged piece, and steps horde
## and defence together until the piece breaches or the horde is gone.
func _run_race(archers: int) -> Dictionary:
	var siege := _approach_and_siege()
	if siege.is_empty():
		return {"outcome": "no siege"}
	var horde: Horde = siege[0]
	var segment: WallSegment = siege[1]
	_place_archers(archers, _HOME, _beside_wall(segment, horde, 20.0))
	var seconds := 0.0
	for _i in range(_MAX_SIEGE_STEPS):
		if segment.is_breached():
			return {"outcome": "breached", "game_seconds": seconds, "real_seconds_at_5x": seconds / 5.0, "horde_left": horde.size}
		if not _hordes.get_all_hordes().has(horde) or horde.size <= 0:
			return {"outcome": "destroyed", "game_seconds": seconds, "real_seconds_at_5x": seconds / 5.0, "wall_hp_left": segment.current_hp}
		_hordes._process(_STEP_SECONDS)
		_defense._process(_STEP_SECONDS)
		seconds += _STEP_SECONDS
	return {"outcome": "undecided", "game_seconds": seconds}


func _defender_count(horde: Horde, segment: WallSegment) -> int:
	return _defense.get_defenders(horde, segment).size()


## A local position `metres` inward (positive) from the piece's midpoint toward
## `coord`'s centre; negative goes outward, toward the horde.
func _beside_wall(segment: WallSegment, horde: Horde, metres: float, coord: Vector2i = _HOME) -> Vector2:
	var mid := (segment.point_a + segment.point_b) * 0.5
	var inward := (HexCoord.axial_to_world(_HOME) - HexCoord.axial_to_world(horde.hex_coord)).normalized()
	var world := mid + inward * metres * HexCoord.WORLD_UNITS_PER_REAL_METER
	return world - HexCoord.axial_to_world(coord)


func _place_archers(count: int, coord: Vector2i, local_position: Vector2) -> void:
	var entries: Array[UnitSaveEntry] = []
	var definition := UnitCatalog.get_definition(GameEnums.UnitType.TOXOPHILITE)
	for i in range(count):
		entries.append(UnitSaveEntry.new(GameEnums.UnitType.TOXOPHILITE, coord, 100 + i, definition.max_hp, GameEnums.UnitOrderType.HOLD, coord, [], 0, local_position))
	_units.load_save_entries(entries, 100 + count)


func _add(scene: String, node_name: String, paths: Dictionary) -> Node:
	var node: Node = load(scene).instantiate()
	node.name = node_name
	for key in paths:
		node.set(key, NodePath(paths[key]))
	if node is HexGridMap:
		node.auto_generate_on_ready = false
	add_child(node)
	return node


func _build_fixture_cells() -> Dictionary:
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(_HOME, _FIXTURE_RADIUS):
		var cell := HexCell.new(coord)
		if coord == _HOME:
			cell.is_settlement = true
			cell.biome_type = GameEnums.BiomeType.URBAN
			cell.region_name = "Manchester"
		cells[coord] = cell
	return cells
