extends Node

## Locks down the equivalence the minimap's 2026-09-07 optimisation rests on:
## that iterating a manager's own sparse field visits exactly the hexes that
## scanning the whole map would have found interesting. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless scenes/test/verify_sparse_field_iteration.tscn
##
## `MinimapView._draw()` used to walk all 27,566 generated cells twice per
## frame — once asking FogOfWarManager.get_fog_state() and once asking
## NoiseManager.get_noise_at() — to find answers the size of the explored set
## and the noise field respectively. Measured at **17.7 ms and 14.0 ms of a
## 48 ms frame**, against 2.2 ms for the entire simulated world
## (scripts/test/profile_tactical_bisect.gd). It now iterates
## FogOfWarManager.get_explored_hexes() and NoiseManager.get_attracting_hexes().
##
## That is only correct if the sparse set is a superset of the interesting
## hexes. It is, by construction — get_fog_state() and get_noise_at() both
## default to "nothing here" for an absent key, so an absent hex could never
## have drawn anything — but "by construction" is an argument, and the
## constructions are in two other classes that are free to change. This is the
## check that notices if one of them does.
##
## What each check would catch:
##
## 1. A fog state reachable WITHOUT a dictionary entry — a default other than
##    UNSEEN, or a second store the accessor does not cover. The minimap would
##    silently stop drawing terrain it used to draw.
## 2. The same for the noise field.
## 3. The sparse sets actually being sparse. If a future change made
##    FogOfWarManager pre-seed every hex, the equivalence would still hold and
##    the whole optimisation would be gone — a passing check that measures
##    nothing is worse than no check.

const _FIXTURE_RADIUS: int = 6
const _HOME := Vector2i.ZERO
const _TOWER_HEX := Vector2i(2, -1)   ## Vision source: lights a ring of fog around itself.
const _MINE_HEX := Vector2i(-2, 1)    ## Noise source: Coal Mine, 95 dB.
const _TOWER := GameEnums.BuildingType.WATCHTOWER
const _MINE := GameEnums.BuildingType.COAL_MINE

var _map: HexGridMap
var _resources: ResourceManager
var _buildings: BuildingManager
var _fog: FogOfWarManager
var _noise: NoiseManager
var _failures: Array[String] = []


func _ready() -> void:
	_map = load("res://scenes/world/HexGridMap.tscn").instantiate()
	_map.auto_generate_on_ready = false
	_map.name = "HexGridMap"
	add_child(_map)
	_map.load_cells(_build_fixture_cells())

	_resources = load("res://scenes/economy/ResourceManager.tscn").instantiate()
	_resources.name = "ResourceManager"
	add_child(_resources)

	# Wired BEFORE add_child so _ready() resolves them, same ordering
	# verify_building_state_emissions.gd and verify_building_power.gd record.
	_buildings = load("res://scenes/buildings/BuildingManager.tscn").instantiate()
	_buildings.name = "BuildingManager"
	_buildings.hex_grid_map_path = NodePath("../HexGridMap")
	_buildings.resource_manager_path = NodePath("../ResourceManager")
	add_child(_buildings)

	_fog = load("res://scenes/world/FogOfWarManager.tscn").instantiate()
	_fog.name = "FogOfWarManager"
	_fog.hex_grid_map_path = NodePath("../HexGridMap")
	_fog.building_manager_path = NodePath("../BuildingManager")
	add_child(_fog)

	_noise = load("res://scenes/world/NoiseManager.tscn").instantiate()
	_noise.name = "NoiseManager"
	_noise.hex_grid_map_path = NodePath("../HexGridMap")
	_noise.building_manager_path = NodePath("../BuildingManager")
	add_child(_noise)

	_buildings.load_save_entries(_fixture_entries(), 100)
	_fog.recompute()
	_noise.recompute()

	_check_fog_iteration_is_equivalent()
	_check_noise_iteration_is_equivalent()
	_check_the_sparse_sets_are_actually_sparse()

	print()
	if _failures.is_empty():
		print("All sparse-field iteration checks passed.")
		get_tree().quit(0)
	else:
		print("FAILED (%d):" % _failures.size())
		for failure in _failures:
			print("  " + failure)
		get_tree().quit(1)


## The set the old loop drew, against the set the new one draws.
func _check_fog_iteration_is_equivalent() -> void:
	var by_full_scan: Dictionary = {}
	for cell in _map.get_all_cells():
		if _fog.get_fog_state(cell.coord) != GameEnums.FogState.UNSEEN:
			by_full_scan[cell.coord] = _fog.get_fog_state(cell.coord)

	var by_sparse: Dictionary = {}
	for coord in _fog.get_explored_hexes():
		if _fog.get_fog_state(coord) != GameEnums.FogState.UNSEEN:
			by_sparse[coord] = _fog.get_fog_state(coord)

	print("fog: full scan of %d cells found %d explored; get_explored_hexes() found %d" % [
		_map.get_all_cells().size(), by_full_scan.size(), by_sparse.size()])
	if by_full_scan.is_empty():
		_failures.append("the fixture lit no fog at all, so this check is vacuous — the Watchtower is not a vision source here")
	_report_set_difference("fog", by_full_scan, by_sparse)


func _check_noise_iteration_is_equivalent() -> void:
	var by_full_scan: Dictionary = {}
	for cell in _map.get_all_cells():
		if _noise.get_noise_at(cell.coord) > 0.0:
			by_full_scan[cell.coord] = _noise.get_noise_at(cell.coord)

	var by_sparse: Dictionary = {}
	for coord in _noise.get_attracting_hexes():
		if _noise.get_noise_at(coord) > 0.0:
			by_sparse[coord] = _noise.get_noise_at(coord)

	print("noise: full scan of %d cells found %d attracting; get_attracting_hexes() found %d" % [
		_map.get_all_cells().size(), by_full_scan.size(), by_sparse.size()])
	if by_full_scan.is_empty():
		_failures.append("the fixture generated no attraction at all, so this check is vacuous — the Coal Mine is not emitting here")
	_report_set_difference("noise", by_full_scan, by_sparse)


## The point of the change. An equivalence that holds because both sides visit
## every hex would pass checks 1 and 2 and have optimised nothing.
func _check_the_sparse_sets_are_actually_sparse() -> void:
	var cells := _map.get_all_cells().size()
	var known := _fog.get_explored_hexes().size()
	var attracting := _noise.get_attracting_hexes().size()
	print("sparsity: %d cells; fog holds %d (%.0f%%), noise holds %d (%.0f%%)" % [
		cells, known, 100.0 * known / maxf(cells, 1), attracting, 100.0 * attracting / maxf(cells, 1)])
	if known >= cells:
		_failures.append("FogOfWarManager reports every one of the %d cells as explored — iterating it is no longer cheaper than scanning the map. This check has already caught exactly that once: _fog_state is DENSE (seeded UNSEEN per cell in _ready()) and the first version of get_explored_hexes() returned its keys." % cells)
	if attracting >= cells:
		_failures.append("NoiseManager holds attraction for every one of the %d cells — iterating it is no longer cheaper than scanning the map" % cells)


func _report_set_difference(label: String, full_scan: Dictionary, sparse: Dictionary) -> void:
	var missing: Array[Vector2i] = []
	for coord in full_scan:
		if not sparse.has(coord) or sparse[coord] != full_scan[coord]:
			missing.append(coord)
	var extra: Array[Vector2i] = []
	for coord in sparse:
		if not full_scan.has(coord):
			extra.append(coord)
	if not missing.is_empty():
		_failures.append("%s: %d hexes a full map scan would have drawn are missing from the sparse set (e.g. %s) — the minimap would silently stop drawing them"
			% [label, missing.size(), missing[0]])
	if not extra.is_empty():
		_failures.append("%s: the sparse set holds %d hexes a full map scan would not have drawn (e.g. %s)"
			% [label, extra.size(), extra[0]])


func _fixture_entries() -> Array[BuildingSaveEntry]:
	var entries: Array[BuildingSaveEntry] = []
	entries.append(_entry(_TOWER, _TOWER_HEX, 1))
	entries.append(_entry(_MINE, _MINE_HEX, 2))
	return entries


## current_hp is passed explicitly: BuildingSaveEntry defaults it to 0.0,
## which would restore every fixture building as an already-destroyed shell —
## and a ruin emits neither vision nor noise (D59), so both checks would go
## vacuous rather than fail.
func _entry(building_type: GameEnums.BuildingType, coord: Vector2i, id: int) -> BuildingSaveEntry:
	var definition := BuildingCatalog.get_definition(building_type)
	return BuildingSaveEntry.new(building_type, coord, id, Vector2.ZERO,
		definition.population_provided, definition.get_max_hp())


## URBAN rather than HexCell's default MOORLAND, whose get_vision_penalty() of
## 1 shrinks every vision radius — the same fixture choice
## verify_building_state_emissions.gd records for the same reason.
func _build_fixture_cells() -> Dictionary:
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(_HOME, _FIXTURE_RADIUS):
		var cell := HexCell.new(coord)
		cell.biome_type = GameEnums.BiomeType.URBAN
		cells[coord] = cell
	return cells
