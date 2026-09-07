extends Node

## Locks down what a building's noise actually reaches, now that reach is
## derived from a source level rather than stated as a constant radius. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless scenes/test/verify_noise_emission.tscn
##
## A scene rather than a `-s` script because it drives the real NoiseManager,
## which connects to the TimeCycleManager autoload — the split
## tools/ci/run_verifications.py's own header describes.
##
## What each check is for:
##
## 1. **The calibration.** NoisePropagation.HEARING_THRESHOLD_DB is the balance
##    knob the whole model hangs off, and it was chosen so the catalogue's
##    loudest building pulls a horde from the 2 hexes the flat aura it
##    replaced already reached. If that stops being true the change has
##    silently become a balance change, which is the one thing it claims not
##    to be.
## 2. **Reach differentiates.** The point of the rewrite: under the flat model
##    every building above `noise_output` 0 projected the identical 2-hex
##    disc. A Brickworks must now reach materially less far than a Bessemer
##    Smelting Complex.
## 3. **Falloff.** The old field was flat inside its disc and zero outside.
##    Attraction must now decrease with distance at every step.
## 4. **Sources combine as intensities.** Four equal sources on one hex are
##    +6 dB, not four times the attraction. Getting this wrong is invisible
##    on one building and wrong by 10x on a district.
## 5. **Terrain attenuates.** §6's three rules — woodland per kilometre, high
##    ground once, Level 4 mountain blocks entirely — each measured against an
##    otherwise identical path.
## 6. **The terrain cache is bounded and honest.** It answers the same as an
##    uncached computation, and it does not grow without limit.
##
## Fixture rather than the real map, same reasoning verify_building_power.gd
## and verify_gates.gd both record: HexMapGenerator builds the whole UK+Ireland
## corridor on every run, which is minutes per launch. Buildings are registered
## through BuildingManager.load_save_entries() for the same reason that file
## gives — placement legality is resolved at sub-hex resolution against baked
## raster a hand-built fixture cell cannot control.

const _FIXTURE_RADIUS: int = 5
const _HOME := Vector2i.ZERO
const _EPSILON: float = 0.001

## Quietest and loudest machinery in the catalogue. Read by TYPE and resolved
## through BuildingCatalog at runtime, so a balance pass that moves their
## levels moves this file's expectations with them rather than failing it.
const _QUIET := GameEnums.BuildingType.BRICKWORKS
const _LOUD := GameEnums.BuildingType.BESSEMER_SMELTING_COMPLEX

var _map: HexGridMap
var _buildings: BuildingManager
var _noise: NoiseManager
var _failures: Array[String] = []
var _next_id: int = 1


func _ready() -> void:
	_map = load("res://scenes/world/HexGridMap.tscn").instantiate()
	_map.auto_generate_on_ready = false
	add_child(_map)
	_map.load_cells(_build_fixture_cells())

	_buildings = load("res://scenes/buildings/BuildingManager.tscn").instantiate()
	_buildings.name = "BuildingManager"
	_buildings.hex_grid_map_path = _map.get_path()
	add_child(_buildings)

	_noise = load("res://scenes/world/NoiseManager.tscn").instantiate()
	_noise.name = "NoiseManager"
	_noise.hex_grid_map_path = _map.get_path()
	_noise.building_manager_path = _buildings.get_path()
	add_child(_noise)

	_check_loudest_building_still_reaches_two_hexes()
	_check_reach_differentiates()
	_check_attraction_falls_off_with_distance()
	_check_sources_combine_as_intensities()
	_check_terrain_attenuates()
	_check_terrain_cache_is_bounded_and_honest()

	print()
	if _failures.is_empty():
		print("All noise-emission checks passed.")
		get_tree().quit(0)
	else:
		print("FAILED (%d):" % _failures.size())
		for failure in _failures:
			print("  " + failure)
		get_tree().quit(1)


## The calibration this whole model was fitted to. Measured against
## HordeManager's own ATTRACTION_THRESHOLD, in hexes, because that is the unit
## the decision was made in: "does the loudest building still pull a horde
## from where the flat 2-hex disc did".
func _check_loudest_building_still_reaches_two_hexes() -> void:
	var pull_hexes := _pull_radius_hexes(_source_db(_LOUD))
	print("loudest building (%s, %.0f dB) pulls a horde from %.2f hexes (want 1.9-2.2, where the flat NOISE_RADIUS = 2 disc reached)" % [
		BuildingCatalog.get_definition(_LOUD).display_name, _source_db(_LOUD), pull_hexes])
	if pull_hexes < 1.9 or pull_hexes > 2.2:
		_failures.append("the loudest building pulls from %.2f hexes, not the ~2.0 the flat aura it replaced reached — HEARING_THRESHOLD_DB is no longer calibrated and this has become a balance change" % pull_hexes)


## The reason the rewrite exists. Under the flat model these two numbers were
## both exactly 2.
func _check_reach_differentiates() -> void:
	var quiet := _pull_radius_hexes(_source_db(_QUIET))
	var loud := _pull_radius_hexes(_source_db(_LOUD))
	print("reach spread: %s %.2f hexes vs %s %.2f hexes (want the quiet one under 1.5 and clearly less)" % [
		BuildingCatalog.get_definition(_QUIET).display_name, quiet,
		BuildingCatalog.get_definition(_LOUD).display_name, loud])
	if quiet >= 1.5:
		_failures.append("the catalogue's QUIETEST machinery still pulls a horde from %.2f hexes — reach is not differentiating by source" % quiet)
	if loud - quiet < 0.75:
		_failures.append("loudest and quietest differ by only %.2f hexes of pull; the flat model this replaced differed by 0.00, so this is barely a change" % (loud - quiet))


## Attraction must decrease at every step out from the source. The flat model
## was constant inside its disc and zero outside — a cliff, not a curve, and
## nothing between the source and the edge told the player anything.
func _check_attraction_falls_off_with_distance() -> void:
	_place_only([[_LOUD, _HOME]])
	var readings: Array[float] = []
	for ring in 4:
		readings.append(_noise.get_noise_at(Vector2i(ring, 0)))
	print("attraction by ring from one %s: %.1f, %.1f, %.1f, %.1f" % [
		BuildingCatalog.get_definition(_LOUD).display_name, readings[0], readings[1], readings[2], readings[3]])
	for ring in range(1, readings.size()):
		if readings[ring] >= readings[ring - 1]:
			_failures.append("attraction did not fall between ring %d (%.1f) and ring %d (%.1f) — the field is still flat inside a disc" % [
				ring - 1, readings[ring - 1], ring, readings[ring]])
	if readings[0] <= 0.0:
		_failures.append("a %s put no attraction on its own hex at all" % BuildingCatalog.get_definition(_LOUD).display_name)


## Levels do not add; intensities do. Four equal sources are +6 dB, so the
## source hex should gain about 6 attraction, not triple.
func _check_sources_combine_as_intensities() -> void:
	_place_only([[_LOUD, _HOME]])
	var one := _noise.get_noise_at(_HOME)
	_place_only([[_LOUD, _HOME], [_LOUD, _HOME], [_LOUD, _HOME], [_LOUD, _HOME]])
	var four := _noise.get_noise_at(_HOME)
	var expected_gain := 10.0 * log(4.0) / log(10.0)
	print("one source %.1f -> four sources %.1f (gain %.1f, want %.1f; a linear sum would give %.1f)" % [
		one, four, four - one, expected_gain, one * 4.0])
	if absf((four - one) - expected_gain) > 0.1:
		_failures.append("four equal sources on one hex gained %.1f attraction, not the %.1f of 10*log10(4) — sound levels are being summed instead of intensities" % [four - one, expected_gain])


## §6's three terrain rules, each measured against the otherwise identical
## path. Terrain is set on the FIXTURE CELLS for the mountain rule, which is
## decided per macro hex off HexCell.elevation (CLAUDE.md §3's named
## exception, because MountainPassCarver's carve exists nowhere in the raster);
## the woodland and high-ground rules read the baked raster, which a fixture
## cannot control, so they are asserted through NoisePropagation's own model
## rather than by painting terrain that does not exist.
func _check_terrain_attenuates() -> void:
	var source_db := _source_db(_LOUD)
	var clear := NoisePropagation.distance_to_level(source_db, NoisePropagation.HEARING_THRESHOLD_DB) / _hex_step_metres()
	var over_hill := NoisePropagation.distance_to_level(source_db, NoisePropagation.HEARING_THRESHOLD_DB, NoisePropagation.HIGH_GROUND_ATTENUATION_DB) / _hex_step_metres()
	var through_wood := NoisePropagation.distance_to_level(source_db, NoisePropagation.HEARING_THRESHOLD_DB, NoisePropagation.WOODLAND_ATTENUATION_DB_PER_KM * 2.0) / _hex_step_metres()
	print("audible radius: %.2f hexes clear, %.2f over high ground, %.2f through 2 km of woodland" % [clear, over_hill, through_wood])
	if over_hill >= clear or through_wood >= clear:
		_failures.append("terrain did not attenuate: clear %.2f, high ground %.2f, woodland %.2f hexes" % [clear, over_hill, through_wood])
	if NoisePropagation.level_at(source_db, 1000.0, NoisePropagation.BLOCKED) > -1000.0:
		_failures.append("a path marked BLOCKED still returned a finite sound level — §6's Level 4 mountain does not block")

	# The mountain rule end to end, through the real path walk: raise one hex
	# of the fixture to Level 4 and check the path across it goes silent.
	var ridge := Vector2i(2, 0)
	var listener := Vector2i(4, 0)
	NoisePropagation.clear_cache()
	var before := NoisePropagation.attenuation_db(_HOME, listener, _map)
	_map.get_cell(ridge).elevation = ElevationLevels.mountain_threshold_elevation() + 0.01
	NoisePropagation.clear_cache()
	var after := NoisePropagation.attenuation_db(_HOME, listener, _map)
	print("path %s -> %s attenuation: %.1f dB clear, %s with a Level 4 hex across it" % [
		_HOME, listener, before, "BLOCKED" if after == NoisePropagation.BLOCKED else "%.1f dB" % after])
	if after != NoisePropagation.BLOCKED:
		_failures.append("a path crossing a Level 4 mountain hex returned %.1f dB of attenuation instead of BLOCKED" % after)
	_map.get_cell(ridge).elevation = 0.0
	NoisePropagation.clear_cache()


## Caching may not change an answer, and may not grow without limit. The value
## is a pure function of static baked terrain, so the cache is free to evict
## but never free to disagree.
func _check_terrain_cache_is_bounded_and_honest() -> void:
	NoisePropagation.clear_cache()
	var pairs: Array[Array] = []
	for coord in HexCoord.hex_disk(_HOME, 3):
		pairs.append([_HOME, coord])
	var cold: Array[float] = []
	for pair in pairs:
		cold.append(NoisePropagation.attenuation_db(pair[0], pair[1], _map))
	var disagreed := 0
	for i in pairs.size():
		if NoisePropagation.attenuation_db(pairs[i][0], pairs[i][1], _map) != cold[i]:
			disagreed += 1
	print("%d paths re-read against a warm cache: %d disagreed with their cold value (want 0)" % [pairs.size(), disagreed])
	if disagreed > 0:
		_failures.append("%d of %d paths disagreed with the value they were computed from" % [disagreed, pairs.size()])

	# Flood past the cap with distinct hexes. The fixture has nowhere near
	# enough, so these deliberately name coordinates off the map —
	# attenuation_db() has to answer for those too (a null cell does not
	# block), and what is being measured is the cache, not the terrain.
	var flood := NoisePropagation.MAX_CACHED_HEX_OPACITY + 500
	for i in flood:
		NoisePropagation.attenuation_db(Vector2i(2000 + i, 0), Vector2i(2000 + i, 1), null)
	print("cache after %d distinct hexes: %d held (cap %d)" % [
		flood, NoisePropagation.cache_size(), NoisePropagation.MAX_CACHED_HEX_OPACITY])
	if NoisePropagation.cache_size() > NoisePropagation.MAX_CACHED_HEX_OPACITY:
		_failures.append("the terrain cache holds %d entries against its own cap of %d" % [
			NoisePropagation.cache_size(), NoisePropagation.MAX_CACHED_HEX_OPACITY])
	NoisePropagation.clear_cache()


## The distance at which a source falls to HordeManager's ATTRACTION_THRESHOLD
## above the hearing threshold — "how far away a horde starts walking toward
## this" — in hexes.
func _pull_radius_hexes(source_db: float) -> float:
	var target := NoisePropagation.HEARING_THRESHOLD_DB + HordeManager.ATTRACTION_THRESHOLD
	return NoisePropagation.distance_to_level(source_db, target) / _hex_step_metres()


## The catalogue level for a type, plus the night bonus when the clock says
## night — so this file measures the phase it actually ran in rather than
## assuming one, the same guard verify_building_state_emissions.gd uses.
func _source_db(building_type: GameEnums.BuildingType) -> float:
	var source_db := BuildingCatalog.get_definition(building_type).noise_source_db
	if TimeCycleManager.is_night():
		source_db += NoisePropagation.NIGHT_PROPAGATION_BONUS_DB
	return source_db


func _hex_step_metres() -> float:
	return HexCoord.axial_to_world(Vector2i(1, 0)).length() / HexCoord.WORLD_UNITS_PER_REAL_METER


## Replaces the whole building set, so each check starts from exactly the
## sources it names. load_save_entries() clears every existing instance first,
## which is why this is a replace rather than an add.
func _place_only(placements: Array) -> void:
	var entries: Array[BuildingSaveEntry] = []
	for placement in placements:
		var building_type: GameEnums.BuildingType = placement[0]
		var definition := BuildingCatalog.get_definition(building_type)
		entries.append(BuildingSaveEntry.new(building_type, placement[1], _next_id, Vector2.ZERO,
			definition.population_provided, definition.get_max_hp()))
		_next_id += 1
	_buildings.load_save_entries(entries, _next_id)
	_noise.recompute()


func _build_fixture_cells() -> Dictionary:
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(_HOME, _FIXTURE_RADIUS):
		cells[coord] = HexCell.new(coord)
	return cells
