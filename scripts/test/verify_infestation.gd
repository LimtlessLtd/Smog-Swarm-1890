extends Node

## Proves design_doc.md §2.1's infestation model is the model, not a set of
## numbers that happen to move. Run (as a real scene, not `-s` — it needs the
## TickManager autoload InfestationManager connects to):
##
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/verify_infestation.tscn
##
## ## What each check is guarding against
##
## The model's whole claim is that ONE mutable number per hex drives everything
## (D1), so the failures worth catching are the ones where a second source of
## truth quietly appears:
##
## * A hex's zombies are its residents PLUS whatever horde stands on it. If the
##   two are ever added wrong, killing a horde stops lowering infestation —
##   which is D8's only suppression mechanism — or a horde walking over cleared
##   ground fails to re-infest it (§2.1's re-infestation). Checks 2 and 3.
## * Export must CONSERVE. A pump that loses zombies on the way out, or one that
##   ships more than the 75% floor allows, breaks D4's "breed to 100, export to
##   75, repeat" into either a decaying map or an infinite one. Check 4 asserts
##   the total across the hex and its new horde is unchanged.
## * The ring seed is the opening state the player meets (D7). Getting it wrong
##   is invisible on day one and decides the whole early game. Check 1.
##
## Fixture rather than the real map, same reasoning verify_gates.gd and
## verify_horde_infrastructure.gd both record: HexMapGenerator builds the whole
## UK+Ireland corridor on every run, which is minutes per launch.

const _FIXTURE_RADIUS: int = 6
const _CAPACITY: int = 10_000
const _START := Vector2i.ZERO
const _EPSILON: float = 0.001

var _map: HexGridMap
var _hordes: HordeManager
var _infestation: InfestationManager
var _failures: Array[String] = []


func _ready() -> void:
	_map = load("res://scenes/world/HexGridMap.tscn").instantiate()
	_map.auto_generate_on_ready = false
	_map.name = "HexGridMap"
	add_child(_map)
	_map.load_cells(_build_fixture_cells())

	_hordes = load("res://scenes/world/HordeManager.tscn").instantiate()
	_hordes.name = "HordeManager"
	# Wired BEFORE add_child so _ready() resolves it — a horde whose manager has
	# no map crashes in _pick_drift_target() on the very next frame.
	#
	# HordeManager._ready() also calls seed_starting_hordes(), and this fixture
	# makes that a no-op rather than working around it: its cells carry no
	# districts, so HexCell.is_frontier() is false everywhere and
	# _spawnable_coords() comes back empty. Three randomly-placed starting
	# hordes would make every count below depend on where they landed, so the
	# assertion under it is the guard rather than the comment.
	_hordes.hex_grid_map_path = NodePath("../HexGridMap")
	add_child(_hordes)
	if not _hordes.get_all_hordes().is_empty():
		_failures.append("the fixture seeded %d starting hordes — every count below is position-dependent" % _hordes.get_all_hordes().size())

	_infestation = load("res://scenes/world/InfestationManager.tscn").instantiate()
	_infestation.name = "InfestationManager"
	_infestation.hex_grid_map_path = NodePath("../HexGridMap")
	_infestation.horde_manager_path = NodePath("../HordeManager")
	add_child(_infestation)
	_infestation.seed_rings_from(_START)

	get_tree().quit(_run())


func _run() -> int:
	_check_ring_seed()
	_check_band_table()
	_check_hordes_count_toward_the_hex()
	_check_killing_lowers_infestation()
	_check_breed_and_export()
	_check_export_is_bounded_by_the_player()
	_check_build_rights()
	_check_wall_rights()
	_check_save_round_trip()

	print()
	if _failures.is_empty():
		print("All infestation checks passed.")
		return 0
	print("FAILED (%d):" % _failures.size())
	for failure in _failures:
		print("  " + failure)
	return 1


## D7: 0% on the player's own hex, then 25 / 50 / 75, and 100% from ring four.
func _check_ring_seed() -> void:
	var expected := InfestationManager.RING_SEED_PERCENT
	for ring in range(0, _FIXTURE_RADIUS + 1):
		var coord := _START + Vector2i(ring, 0)
		var want: float = expected[mini(ring, expected.size() - 1)]
		var got := _infestation.infestation_at(coord)
		print("ring %d: %.1f%% (want %.1f%%)  band=%s" % [ring, got, want, _band_name(_infestation.band_at(coord))])
		if absf(got - want) > 0.5:
			_failures.append("ring %d seeded at %.1f%%, D7 says %.1f%%" % [ring, got, want])
	if not _infestation.is_cleared(_START):
		_failures.append("the player's own starting hex is not Cleared")
	if _infestation.band_at(_START + Vector2i(3, 0)) != GameEnums.InfestationBand.HIVE_CORE:
		_failures.append("ring three is not Hive Core — D7 puts it exactly on the threshold so breeding is visible from home")


## The §2.1 table itself, checked at its own boundaries rather than through a
## hex, so an off-by-one in a comparison operator cannot hide behind rounding.
func _check_band_table() -> void:
	var cases := [
		[0.0, GameEnums.InfestationBand.CLEARED],
		[4.9, GameEnums.InfestationBand.CLEARED],
		[5.0, GameEnums.InfestationBand.FRINGE],
		[25.0, GameEnums.InfestationBand.FRINGE],
		[25.1, GameEnums.InfestationBand.CONTESTED],
		[74.9, GameEnums.InfestationBand.CONTESTED],
		[75.0, GameEnums.InfestationBand.HIVE_CORE],
		[100.0, GameEnums.InfestationBand.HIVE_CORE],
	]
	for case in cases:
		var got: GameEnums.InfestationBand = InfestationManager.band_for(case[0])
		if got != case[1]:
			_failures.append("%.1f%% reads as %s, design_doc.md §2.1 says %s" % [case[0], _band_name(got), _band_name(case[1])])


## §2.1's re-infestation: "A roaming horde crossing a Cleared hex raises its
## count and can push it back over 5.0."
func _check_hordes_count_toward_the_hex() -> void:
	var before := _infestation.infestation_at(_START)
	# 6% of capacity — enough to clear the 5% threshold and nothing more, so
	# this fails if the two halves are added with the wrong weight, not just if
	# they are not added at all.
	_hordes.spawn_horde_at(_START, int(0.06 * _CAPACITY))
	var after := _infestation.infestation_at(_START)
	print("cleared hex %.1f%% -> %.1f%% with a horde standing on it" % [before, after])
	if after <= before:
		_failures.append("a horde standing on a hex does not raise its infestation at all")
	if _infestation.is_cleared(_START):
		_failures.append("a horde worth 6%% of capacity left the hex Cleared (%.1f%%)" % after)
	if absf(after - 6.0) > 0.5:
		_failures.append("expected ~6%% with a 600-strong horde on a 10,000 hex, got %.1f%%" % after)


## D8, verbatim: "Zombies create infestation. Suppressing infestion means
## getting rid of zombies." Killing has to be arithmetic on the same number,
## not a separate suppression rule.
func _check_killing_lowers_infestation() -> void:
	var occupied := _infestation.infestation_at(_START)
	for horde in _hordes.get_hordes_at(_START):
		_hordes.remove_horde(horde)
	var cleared := _infestation.infestation_at(_START)
	print("killing the horde: %.1f%% -> %.1f%%" % [occupied, cleared])
	if cleared >= occupied:
		_failures.append("removing every horde from a hex did not lower its infestation")
	if not _infestation.is_cleared(_START):
		_failures.append("the starting hex did not return to Cleared after the horde was killed")


## D4's pump, and the conservation law under it. A hex at 100% ships whatever
## sits above the 75% floor; the zombies leave `_resident` and arrive as a
## Horde on the same hex, so the hex's own total must not move.
func _check_breed_and_export() -> void:
	var far := _START + Vector2i(5, 0)  ## Seeded at 100% by the ring rule.
	if _infestation.infestation_at(far) < 99.9:
		_failures.append("fixture hex %s is not at 100%% before the export check" % far)
		return
	var total_before := _infestation.zombie_count_at(far)
	# No BuildingManager wired, so _nearest_exportable() has no player to
	# measure against and nothing ships. Breeding still has to hold the hex at
	# its cap rather than running past it.
	_infestation.run_daily_tick()
	var total_after := _infestation.zombie_count_at(far)
	print("hex at capacity after a day with no player on the map: %d -> %d" % [total_before, total_after])
	if total_after > _CAPACITY:
		_failures.append("breeding pushed a hex past its own capacity (%d > %d)" % [total_after, _CAPACITY])
	if not _hordes.get_hordes_at(far).is_empty():
		_failures.append("a Hive Core exported a horde with no player buildings anywhere on the map")

	# Now do the export by hand, which is what a wired BuildingManager would
	# have caused, and assert the conservation directly.
	var resident_before := _infestation.resident_count_at(far)
	var shipped := _infestation.export_from(far)
	var resident_after := _infestation.resident_count_at(far)
	var roaming := _hordes.get_zombie_count_at(far)
	print("export: resident %d -> %d, horde %d, shipped %d" % [resident_before, resident_after, roaming, shipped])
	if shipped <= 0:
		_failures.append("a hex at 100%% exported nothing")
	if resident_after + roaming != resident_before:
		_failures.append("export lost or invented zombies: %d resident + %d roaming != %d before"
			% [resident_after, roaming, resident_before])
	var per_day := int(round(InfestationManager.MAX_EXPORT_FRACTION_PER_DAY * float(_CAPACITY)))
	if shipped != per_day:
		_failures.append("export shipped %d, MAX_EXPORT_FRACTION_PER_DAY allows %d" % [shipped, per_day])
	if _infestation.band_at(far) != GameEnums.InfestationBand.HIVE_CORE:
		_failures.append("a hex that just exported dropped out of Hive Core — only killing may take it below 75%%")

	# D4's floor is the hard constraint under the rate cap, so drain the hex
	# with nothing breeding it back and assert where it stops. A cap that
	# forgot the floor would walk it to zero one 2.5% step at a time, which is
	# exactly the failure a single-export check cannot see.
	var floor_count := int(round(InfestationManager.EXPORT_FLOOR_FRACTION * float(_CAPACITY)))
	var steps := 0
	while _infestation.export_from(far) > 0 and steps < 100:
		steps += 1
	var drained := _infestation.resident_count_at(far)
	print("drained by repeated export in %d steps: %d residents (floor %d)" % [steps, drained, floor_count])
	if drained < floor_count:
		_failures.append("repeated export took the hex to %d, under D4's %d floor" % [drained, floor_count])
	if drained > floor_count:
		_failures.append("repeated export stopped at %d, above D4's %d floor — the pump stalls early" % [drained, floor_count])
	if _infestation.band_at(far) != GameEnums.InfestationBand.HIVE_CORE:
		_failures.append("a fully drained Hive Core left the band without anyone killing anything")


## The bound that keeps worldgen's ~4,655 hexes at 100% from each shipping a
## horde on day one. Without a player on the map there is nothing to measure
## distance against, so nothing ships — asserted above; here the guard is that
## the cap itself is a real number rather than "however many candidates there
## were".
func _check_export_is_bounded_by_the_player() -> void:
	if InfestationManager.MAX_EXPORTS_PER_DAY < 1:
		_failures.append("MAX_EXPORTS_PER_DAY is %d — the pump can never ship" % InfestationManager.MAX_EXPORTS_PER_DAY)
	if InfestationManager.EXPORT_MAX_DISTANCE_FROM_PLAYER < 1:
		_failures.append("EXPORT_MAX_DISTANCE_FROM_PLAYER is %d — no hex can ever be in range" % InfestationManager.EXPORT_MAX_DISTANCE_FROM_PLAYER)
	var candidates := 0
	for cell: HexCell in _map.get_all_cells():
		if _infestation.infestation_at(cell.coord) >= 99.9:
			candidates += 1
	print("hexes at 100%% in the fixture: %d, of which at most %d may ship per day"
		% [candidates, InfestationManager.MAX_EXPORTS_PER_DAY])
	if candidates <= InfestationManager.MAX_EXPORTS_PER_DAY:
		_failures.append("the fixture has only %d hexes at 100%%, so the export cap is not actually exercised" % candidates)


## design_doc.md §2.1's Build Rights column, which is the whole player-facing
## point of the band — P1's "every hex the player wants costs a fight". Checked
## through get_infestation_placement_error() rather than get_placement_error()
## so a failure here is unambiguously the band clause and not a tier, cost or
## terrain rule that happens to reject the same hex.
func _check_build_rights() -> void:
	var buildings: BuildingManager = load("res://scenes/buildings/BuildingManager.tscn").instantiate()
	buildings.name = "BuildingManager"
	buildings.infestation_manager_path = NodePath("../InfestationManager")
	add_child(buildings)

	var defensive := BuildingCatalog.get_definition(GameEnums.BuildingType.WATCHTOWER)
	var ordinary := BuildingCatalog.get_definition(GameEnums.BuildingType.LUMBER_YARD)
	if not defensive.is_defensive:
		_failures.append("the Watchtower is not flagged is_defensive — design_doc.md §2.1 names it in the Fringe allow-list")
	if ordinary.is_defensive:
		_failures.append("the Lumber Yard is flagged is_defensive, so the Fringe check below is vacuous")

	# ring -> (defensive allowed, ordinary allowed), straight off the §2.1 table.
	var cases := [
		[0, true, true],    ## Cleared
		[1, true, false],   ## Fringe
		[2, false, false],  ## Contested
		[4, false, false],  ## Hive Core
	]
	for case in cases:
		var coord: Vector2i = _START + Vector2i(int(case[0]), 0)
		var band := _infestation.band_at(coord)
		var defensive_ok := buildings.get_infestation_placement_error(defensive, coord).is_empty()
		var ordinary_ok := buildings.get_infestation_placement_error(ordinary, coord).is_empty()
		print("%-10s Watchtower=%s  Lumber Yard=%s" % [_band_name(band), defensive_ok, ordinary_ok])
		if defensive_ok != bool(case[1]):
			_failures.append("%s allows a Watchtower = %s, §2.1 says %s" % [_band_name(band), defensive_ok, case[1]])
		if ordinary_ok != bool(case[2]):
			_failures.append("%s allows a Lumber Yard = %s, §2.1 says %s" % [_band_name(band), ordinary_ok, case[2]])
	buildings.queue_free()


## Walls are Defensive Tier too (§2.1's Fringe allow-list reads "Watchtowers,
## Garrisons, Walls, Supply Dumps"), and they are not BuildingDefinitions, so
## WallManager carries the rule separately and needs its own check.
func _check_wall_rights() -> void:
	var walls: WallManager = load("res://scenes/defense/WallManager.tscn").instantiate()
	walls.name = "WallManager"
	walls.hex_grid_map_path = NodePath("../HexGridMap")
	walls.infestation_manager_path = NodePath("../InfestationManager")
	add_child(walls)

	# Two points inside ONE hex, so the piece's two endpoint cells are the same
	# hex and the result is a statement about that hex's band alone.
	var cases := [[1, true], [2, false], [4, false]]
	for case in cases:
		var coord: Vector2i = _START + Vector2i(int(case[0]), 0)
		var centre := HexCoord.axial_to_world(coord)
		var allowed := walls.can_place_wall_piece(centre + Vector2(-20.0, 0.0), centre + Vector2(20.0, 0.0))
		print("%-10s wall piece allowed = %s" % [_band_name(_infestation.band_at(coord)), allowed])
		if allowed != bool(case[1]):
			_failures.append("%s allows a wall = %s, §2.1 says %s" % [_band_name(_infestation.band_at(coord)), allowed, case[1]])
	walls.queue_free()


## D1 says `infestation` and `is_cleared` are derived and never saved. The
## round trip therefore has to restore identically from the count alone — and
## an EMPTY dictionary has to mean "a save from before this model existed",
## not "the world is empty", or loading an old save yields a dead map.
func _check_save_round_trip() -> void:
	var sampled: Array[Vector2i] = [_START, _START + Vector2i(2, 0), _START + Vector2i(5, 0)]
	var before: Array[int] = []
	for coord in sampled:
		before.append(_infestation.resident_count_at(coord))
	var state := _infestation.get_save_state()
	if state.has("infestation") or state.has("is_cleared") or state.has("total_zombie_pop"):
		_failures.append("the save state carries a derived or static field: %s" % [state.keys()])

	_infestation.load_save_state({})
	var kept := true
	for i in sampled.size():
		if _infestation.resident_count_at(sampled[i]) != before[i]:
			kept = false
	if not kept:
		_failures.append("loading an empty save state wiped the worldgen rings — a pre-infestation save would load a dead world")

	_infestation.add_zombies(_START, 500)
	_infestation.load_save_state(state)
	for i in sampled.size():
		var restored := _infestation.resident_count_at(sampled[i])
		if restored != before[i]:
			_failures.append("%s restored to %d, saved %d" % [sampled[i], restored, before[i]])
	print("save round trip: %d sampled hexes restored" % sampled.size())


func _build_fixture_cells() -> Dictionary:
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(_START, _FIXTURE_RADIUS):
		var cell := HexCell.new(coord)
		cell.biome_type = GameEnums.BiomeType.MOORLAND
		cell.soil_fertility = GameEnums.SoilFertility.POOR
		# Flat capacity across the fixture so every percentage below is a
		# statement about the model rather than about the population bake.
		cell.total_zombie_pop = _CAPACITY
		cells[coord] = cell
	return cells


func _band_name(band: GameEnums.InfestationBand) -> String:
	match band:
		GameEnums.InfestationBand.CLEARED:
			return "Cleared"
		GameEnums.InfestationBand.FRINGE:
			return "Fringe"
		GameEnums.InfestationBand.CONTESTED:
			return "Contested"
		_:
			return "Hive Core"
