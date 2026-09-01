extends Node

## What the noise rewrite costs per recompute, and what the field looks like
## over real terrain. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless scenes/test/diagnose_noise_emission.tscn
##
## Two questions the gate does not answer, because they are measurements
## rather than assertions:
##
## 1. **Is recompute() still affordable?** It runs on every building
##    placed/removed/ruined/repaired/powered/completed and twice per in-game
##    day, and it now walks a terrain-attenuated path per source/listener pair
##    instead of stamping a flat disc. NoisePropagation samples each HEX's
##    terrain once and caches it, so the shape that matters is COLD versus WARM
##    at a realistic building count, not the average. This table is what killed
##    the first implementation, which sampled per source/listener PAIR and cost
##    55 s at 200 buildings.
## 2. **What does the field actually look like on real ground?** The catalogue
##    spread is a calculation; what a player sees is the attraction on the
##    hexes around their works, over terrain that attenuates.
##
## Runs over RealTerrainSampler's baked corridor so the attenuation paths read
## real woodland and real elevation, unlike verify_noise_emission.gd's fixture.

const _ORIGIN := Vector2i(80, 120)  ## Mid-corridor (RealTerrainSampler's corridor is q 55..105, r 85..160).
const _FIXTURE_RADIUS: int = 12
const _BUILDING_COUNTS: Array[int] = [1, 10, 50, 200]

## A representative industrial mix rather than 200 of one thing — a real
## colony's field is several overlapping sources of different levels.
const _MIX: Array[GameEnums.BuildingType] = [
	GameEnums.BuildingType.BRICKWORKS,
	GameEnums.BuildingType.COAL_MINE,
	GameEnums.BuildingType.IRON_FOUNDRY,
	GameEnums.BuildingType.SAWMILLS,
]

var _map: HexGridMap
var _buildings: BuildingManager
var _noise: NoiseManager
var _next_id: int = 1


func _ready() -> void:
	if not RealTerrainSampler.is_available():
		print("SKIP: baked rasters not present, nothing to measure.")
		get_tree().quit(0)
		return

	_map = load("res://scenes/world/HexGridMap.tscn").instantiate()
	_map.auto_generate_on_ready = false
	add_child(_map)
	_map.load_cells(_build_cells())

	_buildings = load("res://scenes/buildings/BuildingManager.tscn").instantiate()
	_buildings.name = "BuildingManager"
	_buildings.hex_grid_map_path = _map.get_path()
	add_child(_buildings)

	_noise = load("res://scenes/world/NoiseManager.tscn").instantiate()
	_noise.name = "NoiseManager"
	_noise.hex_grid_map_path = _map.get_path()
	_noise.building_manager_path = _buildings.get_path()
	add_child(_noise)

	_measure_recompute_cost()
	_report_terrain_profile()
	_report_field_over_real_terrain()
	get_tree().quit(0)


func _measure_recompute_cost() -> void:
	print("phase: %s" % ("night" if TimeCycleManager.is_night() else "day"))
	print("%-10s %10s %10s %10s %10s" % ["buildings", "cold ms", "warm ms", "paths", "hexes lit"])
	for count in _BUILDING_COUNTS:
		_place(count)
		NoisePropagation.clear_cache()
		var cold_start := Time.get_ticks_usec()
		_noise.recompute()
		var cold_us := Time.get_ticks_usec() - cold_start

		var warm_start := Time.get_ticks_usec()
		_noise.recompute()
		var warm_us := Time.get_ticks_usec() - warm_start

		print("%-10d %10.1f %10.1f %10d %10d" % [
			count, float(cold_us) / 1000.0, float(warm_us) / 1000.0,
			NoisePropagation.cache_size(), _lit_hex_count()])


## What the terrain around the fixture actually costs a source, which is the
## gap between the gate's calibration (measured on a clear path) and what a
## player sees. The gate asserts the loudest building pulls from ~2 hexes; this
## says how much of that real ground gives back.
func _report_terrain_profile() -> void:
	print()
	var attenuations: Array[float] = []
	var worst := 0.0
	for coord in HexCoord.hex_ring(_ORIGIN, 1):
		var value := NoisePropagation.attenuation_db(_ORIGIN, coord, _map)
		if value == NoisePropagation.BLOCKED:
			continue
		attenuations.append(value)
		worst = maxf(worst, value)
	var total := 0.0
	for value in attenuations:
		total += value
	var mean := total / maxf(float(attenuations.size()), 1.0)

	var loud := BuildingCatalog.get_definition(GameEnums.BuildingType.BESSEMER_SMELTING_COMPLEX).noise_source_db
	var target := NoisePropagation.HEARING_THRESHOLD_DB + HordeManager.ATTRACTION_THRESHOLD
	var clear_hexes := NoisePropagation.distance_to_level(loud, target) / _hex_step_metres()
	var real_hexes := NoisePropagation.distance_to_level(loud, target, mean) / _hex_step_metres()
	print("terrain around %s: mean %.1f dB attenuation to a neighbouring hex, worst %.1f dB" % [_ORIGIN, mean, worst])
	print("  loudest building pulls %.2f hexes on a clear path, %.2f through this ground (%.0f%% of it)" % [
		clear_hexes, real_hexes, 100.0 * real_hexes / clear_hexes])


## The field one building of each catalogue level actually produces on real
## corridor ground, ring by ring — the number a player reads off the Threat
## Meter, against NoiseVisuals.VISUALIZATION_MAX_NOISE.
func _report_field_over_real_terrain() -> void:
	print()
	print("attraction by ring over real terrain (HordeManager reacts at %.1f, the Threat Meter saturates at %.1f):" % [
		HordeManager.ATTRACTION_THRESHOLD, NoiseVisuals.VISUALIZATION_MAX_NOISE])
	for building_type in _MIX:
		var definition := BuildingCatalog.get_definition(building_type)
		_place_one(building_type)
		var readings := PackedStringArray()
		for ring in 4:
			readings.append("%6.1f" % _noise.get_noise_at(_ORIGIN + Vector2i(ring, 0)))
		print("  %-26s %5.0f dB   %s   (%d hexes lit)" % [
			definition.display_name, definition.noise_source_db, " ".join(readings), _lit_hex_count()])


func _hex_step_metres() -> float:
	return HexCoord.axial_to_world(Vector2i(1, 0)).length() / HexCoord.WORLD_UNITS_PER_REAL_METER


func _lit_hex_count() -> int:
	var lit := 0
	for coord in HexCoord.hex_disk(_ORIGIN, _FIXTURE_RADIUS):
		if _noise.get_noise_at(coord) > 0.0:
			lit += 1
	return lit


## `count` buildings spread over the fixture in a deterministic spiral, cycling
## through _MIX so the field is a mixture of levels rather than one repeated.
func _place(count: int) -> void:
	var coords := HexCoord.hex_disk(_ORIGIN, _FIXTURE_RADIUS)
	var entries: Array[BuildingSaveEntry] = []
	for i in count:
		var definition := BuildingCatalog.get_definition(_MIX[i % _MIX.size()])
		entries.append(BuildingSaveEntry.new(definition.building_type, coords[i % coords.size()],
			_next_id, Vector2.ZERO, definition.population_provided, definition.get_max_hp()))
		_next_id += 1
	_buildings.load_save_entries(entries, _next_id)


func _place_one(building_type: GameEnums.BuildingType) -> void:
	var definition := BuildingCatalog.get_definition(building_type)
	var entries: Array[BuildingSaveEntry] = [BuildingSaveEntry.new(building_type, _ORIGIN, _next_id,
		Vector2.ZERO, definition.population_provided, definition.get_max_hp())]
	_next_id += 1
	_buildings.load_save_entries(entries, _next_id)
	_noise.recompute()


func _build_cells() -> Dictionary:
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(_ORIGIN, _FIXTURE_RADIUS):
		var cell := HexCell.new(coord)
		var sample := RealTerrainSampler.majority_biome(coord)
		if not sample.is_empty():
			cell.biome_type = sample["biome_type"]
			cell.elevation = sample["elevation"]
		cells[coord] = cell
	return cells
