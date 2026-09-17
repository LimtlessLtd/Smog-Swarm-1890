extends Node

## Locks down how a horde decides it is drawn to the player, and that going dark,
## lamps and decoys change that decision. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless scenes/test/verify_horde_perception.tscn
##
## What each check is for:
##
## 1. **Out of earshot is out of reach.** A horde reacts to the attraction that
##    REACHES its own hex. Before 2026-09-16 it compared the loudest hex within 6
##    hexes against the threshold, so a Brickworks — whose field falls under the
##    threshold inside one hex — drew a horde three hexes away.
## 2. **In earshot, the horde is drawn, and says by what.** The loudest building
##    in the catalogue reaches its neighbour; a horde there is ATTRACTED toward it,
##    `attraction_source` names it, and `horde_attracted` fires.
## 3. **Going dark releases the horde at once.** Switching the source off turns an
##    ATTRACTED horde back to WANDERING in the same frame the field is rebuilt, and
##    `horde_lost_attraction` fires — not on its next replan several hexes later.
## 4. **Lamps reach, and sum.** At night one Watchtower's light does not clear the
##    threshold two hexes out; three on one hex do (D101: a brighter settlement is
##    seen from further).
## 5. **A nearer decoy out-pulls the town, but one lamp does not.** Three lamps
##    at home: a single decoy lamp beside the horde loses to the brighter town
##    (a place is perceived, not a building); two decoy lamps beside it win.
## 6. **Siege pressure is contact-limited.** An 800-strong horde has 28 zombies at
##    a breach point, not 800.
##
## Fixture rather than the real map, same reasoning verify_noise_emission.gd gives.

const _FIXTURE_RADIUS: int = 7
const _HOME := Vector2i.ZERO
const _EPSILON: float = 0.001
const _DAY_PROGRESS: float = 0.25
const _NIGHT_PROGRESS: float = 0.75
const _RUNNING_SPEED_INDEX: int = 1

var _map: HexGridMap
var _resources: ResourceManager
var _buildings: BuildingManager
var _noise: NoiseManager
var _hordes: HordeManager
var _failures: Array[String] = []
var _next_id: int = 1
var _attracted_events: Array = []
var _lost_events: Array = []


func _ready() -> void:
	_pin_phase(_DAY_PROGRESS)

	_map = load("res://scenes/world/HexGridMap.tscn").instantiate()
	_map.auto_generate_on_ready = false
	_map.name = "HexGridMap"
	add_child(_map)
	_map.load_cells(_build_fixture_cells())

	_resources = load("res://scenes/economy/ResourceManager.tscn").instantiate()
	_resources.name = "ResourceManager"
	add_child(_resources)

	_buildings = load("res://scenes/buildings/BuildingManager.tscn").instantiate()
	_buildings.name = "BuildingManager"
	_buildings.hex_grid_map_path = NodePath("../HexGridMap")
	_buildings.resource_manager_path = NodePath("../ResourceManager")
	add_child(_buildings)

	_noise = load("res://scenes/world/NoiseManager.tscn").instantiate()
	_noise.name = "NoiseManager"
	_noise.hex_grid_map_path = NodePath("../HexGridMap")
	_noise.building_manager_path = NodePath("../BuildingManager")
	add_child(_noise)

	_hordes = load("res://scenes/world/HordeManager.tscn").instantiate()
	_hordes.name = "HordeManager"
	_hordes.hex_grid_map_path = NodePath("../HexGridMap")
	_hordes.building_manager_path = NodePath("../BuildingManager")
	_hordes.noise_manager_path = NodePath("../NoiseManager")
	add_child(_hordes)
	_hordes.horde_attracted.connect(func(horde: Horde, source: BuildingInstance, kind: StringName) -> void: _attracted_events.append([horde, source, kind]))
	_hordes.horde_lost_attraction.connect(func(horde: Horde, source: BuildingInstance) -> void: _lost_events.append([horde, source]))

	if TimeCycleManager.is_night():
		_failures.append("the clock was pinned to day but TimeCycleManager reads night — every day check below measures the wrong phase")
	_check_out_of_earshot_is_out_of_reach()
	_check_in_earshot_draws_and_names_the_source()
	_check_going_dark_releases_the_horde()

	_pin_phase(_NIGHT_PROGRESS)
	if not TimeCycleManager.is_night():
		_failures.append("the clock was pinned to night but TimeCycleManager reads day — the lamp checks below are vacuous")
	_check_lamps_reach_and_sum()
	_check_nearer_decoy_out_pulls_the_town()
	_check_siege_pressure_is_contact_limited()

	print()
	if _failures.is_empty():
		print("All horde-perception checks passed.")
		get_tree().quit(0)
	else:
		print("FAILED (%d):" % _failures.size())
		for failure in _failures:
			print("  " + failure)
		get_tree().quit(1)


func _check_out_of_earshot_is_out_of_reach() -> void:
	var works := _place_only([[GameEnums.BuildingType.BRICKWORKS, _HOME]])[0]
	var far := Vector2i(3, 0)
	var horde := _horde_at(far, 400)
	print("1. Brickworks at %s; field at %s = %.2f (threshold %.2f for this horde); state=%s" % [_HOME, far, _noise.get_noise_at(far), _threshold(horde), GameEnums.HordeState.keys()[horde.state]])
	if _noise.get_noise_at(works.hex_coord) < HordeManager.ATTRACTION_THRESHOLD:
		_failures.append("the Brickworks' own hex is under the attraction threshold, so 'out of earshot' measures nothing")
	if horde.state == GameEnums.HordeState.ATTRACTED or horde.attraction_source != null:
		_failures.append("a horde 3 hexes from a Brickworks (field %.2f there) was drawn to it — perception is reading the source's own hex, not what reaches the horde" % _noise.get_noise_at(far))


func _check_in_earshot_draws_and_names_the_source() -> void:
	var works := _place_only([[GameEnums.BuildingType.BESSEMER_SMELTING_COMPLEX, _HOME]])[0]
	var near := Vector2i(1, 0)
	_attracted_events.clear()
	var horde := _horde_at(near, 400)
	print("2. Bessemer at %s; field at %s = %.2f (threshold %.2f); state=%s source=%s" % [_HOME, near, _noise.get_noise_at(near), _threshold(horde), GameEnums.HordeState.keys()[horde.state], horde.attraction_source.definition.display_name if horde.attraction_source else "none"])
	if _noise.get_noise_at(near) < _threshold(horde):
		_failures.append("the loudest building's field on its neighbour (%.2f) is under this horde's threshold (%.2f) — check 2 has nothing to draw" % [_noise.get_noise_at(near), _threshold(horde)])
		return
	if horde.state != GameEnums.HordeState.ATTRACTED:
		_failures.append("a horde standing in the loudest building's field was %s, not ATTRACTED" % GameEnums.HordeState.keys()[horde.state])
	if horde.attraction_source != works:
		_failures.append("an ATTRACTED horde did not name the building drawing it")
	if _attracted_events.is_empty() or _attracted_events[-1][1] != works or _attracted_events[-1][2] != NoiseManager.KIND_NOISE:
		_failures.append("horde_attracted did not fire with the source and KIND_NOISE (events: %s)" % str(_attracted_events.size()))


func _check_going_dark_releases_the_horde() -> void:
	var hordes := _hordes.get_all_hordes()
	if hordes.is_empty():
		_failures.append("check 3 has no horde left from check 2")
		return
	var horde: Horde = hordes[0]
	var works: BuildingInstance = horde.attraction_source
	if works == null:
		_failures.append("check 3 needs the horde from check 2 to still be attracted")
		return
	_lost_events.clear()
	if not _buildings.power_down_building(works):
		_failures.append("the fixture's Bessemer complex refused to switch off (%s)" % _buildings.get_power_down_error(works))
		return
	print("3. switched off; field at horde %.2f; state=%s path=%s lost_events=%d" % [_noise.get_noise_at(horde.hex_coord), GameEnums.HordeState.keys()[horde.state], horde.path, _lost_events.size()])
	if horde.state == GameEnums.HordeState.ATTRACTED or horde.attraction_source != null:
		_failures.append("switching the only source off left the horde ATTRACTED until its next replan")
	if not horde.path.is_empty() and horde.path[-1] == works.hex_coord:
		_failures.append("the released horde is still pathing to the silent building's hex")
	if _lost_events.size() != 1 or _lost_events[0][1] != works:
		_failures.append("horde_lost_attraction fired %d times, want once naming the switched-off building" % _lost_events.size())


func _check_lamps_reach_and_sum() -> void:
	var probe := Vector2i(2, 0)
	_place_only([[GameEnums.BuildingType.WATCHTOWER, _HOME]])
	var one := _noise.get_noise_at(probe)
	_place_only([[GameEnums.BuildingType.WATCHTOWER, _HOME], [GameEnums.BuildingType.WATCHTOWER, _HOME], [GameEnums.BuildingType.WATCHTOWER, _HOME]])
	var three := _noise.get_noise_at(probe)
	var beyond := _noise.get_noise_at(Vector2i(NoiseManager.NIGHT_LIGHT_REACH_HEXES + 1, 0))
	print("4. night light 2 hexes out: one lamp %.2f, three lamps %.2f (threshold %.2f); %d hexes out: %.2f; dominant kind %s" % [one, three, HordeManager.ATTRACTION_THRESHOLD, NoiseManager.NIGHT_LIGHT_REACH_HEXES + 1, beyond, _noise.get_dominant_kind_at(probe)])
	if one >= HordeManager.ATTRACTION_THRESHOLD:
		_failures.append("one lamp alone clears the attraction threshold two hexes out (%.2f) — a single tower draws hordes from afar" % one)
	if three < HordeManager.ATTRACTION_THRESHOLD:
		_failures.append("three lamps on one hex do not clear the threshold two hexes out (%.2f) — light does not reach 'further afield' (D101)" % three)
	if absf(three - 3.0 * one) > _EPSILON:
		_failures.append("three lamps gave %.2f two hexes out, not three times one lamp's %.2f — lamps do not sum" % [three, one])
	if beyond > _EPSILON:
		_failures.append("light reached past NIGHT_LIGHT_REACH_HEXES (%.2f)" % beyond)
	if _noise.get_dominant_kind_at(probe) != NoiseManager.KIND_LIGHT:
		_failures.append("the Watchtowers' ring reported %s as its dominant kind, not light" % _noise.get_dominant_kind_at(probe))


func _check_nearer_decoy_out_pulls_the_town() -> void:
	var decoy_hex := Vector2i(4, 0)
	var horde_hex := Vector2i(3, 0)
	var town: Array = [[GameEnums.BuildingType.WATCHTOWER, _HOME], [GameEnums.BuildingType.WATCHTOWER, _HOME], [GameEnums.BuildingType.WATCHTOWER, _HOME]]
	_place_only(town + [[GameEnums.BuildingType.WATCHTOWER, decoy_hex]])
	var horde := _horde_at(horde_hex, 400)
	var one_decoy_source := horde.attraction_source
	print("5a. town 3 lamps, ONE decoy lamp at %s, horde at %s: field %.2f, drawn to %s" % [decoy_hex, horde_hex, _noise.get_noise_at(horde_hex), one_decoy_source.hex_coord if one_decoy_source else "nothing"])
	if one_decoy_source == null or one_decoy_source.hex_coord != _HOME:
		_failures.append("one decoy lamp (2.0 at the horde) beat a town of three (3.0) — a place's lamps are not being summed")
	_place_only(town + [[GameEnums.BuildingType.WATCHTOWER, decoy_hex], [GameEnums.BuildingType.WATCHTOWER, decoy_hex]])
	horde = _horde_at(horde_hex, 400)
	print("5b. town 3 lamps, TWO decoy lamps at %s: field %.2f, drawn to %s" % [decoy_hex, _noise.get_noise_at(horde_hex), horde.attraction_source.hex_coord if horde.attraction_source else "nothing"])
	if _noise.get_noise_at(horde_hex) < _threshold(horde):
		_failures.append("the decoy fixture's field at the horde (%.2f) is under its threshold — nothing to choose between" % _noise.get_noise_at(horde_hex))
		return
	if horde.attraction_source == null or horde.attraction_source.hex_coord != decoy_hex:
		_failures.append("a horde beside two decoy lamps (4.0) still walked to the town's three (3.0) — a decoy cannot pull a horde away")


func _check_siege_pressure_is_contact_limited() -> void:
	var cases := [[1, 1], [100, 10], [800, 28], [3000, 55], [100000, HordeManager.WALL_CONTACT_FRONTAGE_MAX]]
	for case in cases:
		var got := HordeManager.wall_contact_frontage(case[0])
		if got != case[1]:
			_failures.append("wall_contact_frontage(%d) = %d, want %d" % [case[0], got, case[1]])
	print("6. contact frontage: 800 -> %d, 3000 -> %d" % [HordeManager.wall_contact_frontage(800), HordeManager.wall_contact_frontage(3000)])


func _threshold(horde: Horde) -> float:
	return HordeManager.ATTRACTION_THRESHOLD / maxf(0.01, horde.mean_susceptibility())


## Removes every horde, spawns one of `size` at `coord`, and advances HordeManager
## a sliver so its first replan runs.
func _horde_at(coord: Vector2i, size: int) -> Horde:
	for existing in _hordes.get_all_hordes():
		_hordes.remove_horde(existing)
	_hordes.spawn_horde_at(coord, size)
	_hordes._process(0.001)
	return _hordes.get_hordes_at(coord)[0] if not _hordes.get_hordes_at(coord).is_empty() else _hordes.get_all_hordes()[0]


## Pins TickManager to `progress` through the day and hand-drives
## TimeCycleManager so the phase flips now rather than on a real frame (the
## process_frame ordering trap recorded in verify_building_state_emissions.gd).
func _pin_phase(progress: float) -> void:
	TickManager.load_save_state({
		"current_day": 1,
		"elapsed_in_day": TickManager.DAY_LENGTH_SECONDS * progress,
		"speed_index": _RUNNING_SPEED_INDEX,
	})
	TimeCycleManager._process(0.0)


## Replaces the whole building set and returns the new instances in order.
func _place_only(placements: Array) -> Array[BuildingInstance]:
	var entries: Array[BuildingSaveEntry] = []
	var ids: Array[int] = []
	for placement in placements:
		var building_type: GameEnums.BuildingType = placement[0]
		var definition := BuildingCatalog.get_definition(building_type)
		entries.append(BuildingSaveEntry.new(building_type, placement[1], _next_id, Vector2.ZERO,
			definition.population_provided, definition.get_max_hp()))
		ids.append(_next_id)
		_next_id += 1
	_buildings.load_save_entries(entries, _next_id)
	_noise.recompute()
	var result: Array[BuildingInstance] = []
	for id in ids:
		for instance in _buildings.get_all_buildings():
			if instance.id == id:
				result.append(instance)
	return result


func _build_fixture_cells() -> Dictionary:
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(_HOME, _FIXTURE_RADIUS):
		cells[coord] = HexCell.new(coord)
	return cells
