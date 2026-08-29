extends Node

## Proves design_doc.md §2.1's tactical layer behaves as D12-D15 specify. Run
## (as a real scene, not `-s` — HordeManager reaches the TickManager autoload):
##
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/verify_tactical_zombies.tscn
##
## ## What each check is guarding against
##
## The layer's whole claim is that individual zombies are a VIEW of counts the
## strategic layer already owns (D42), bounded by observation (D13). The
## failures worth catching are the ones where that stops being true:
##
## * **The view becomes a second source of truth.** If instantiating,
##   destroying or stepping a crowd could change a Horde's size or a hex's
##   resident count, §2.1's conservation rule is broken and the map slowly
##   gains or loses zombies every time the player pans. Checks 5 and 6.
## * **The budget is exceeded.** ENTITY_BUDGET is the whole reason this design
##   works at 1e6 counts; an allocation that can overshoot it turns a city hex
##   into a frame-rate cliff. Check 2 drives it with a hex holding 40x the
##   budget.
## * **A besieging horde is starved by a Hive Core's residents.** The one thing
##   the player is certainly looking at must be instantiated first. Check 4.
## * **A zombie is never stepped.** Slicing is what makes the cost bounded; an
##   off-by-one in the slice walk would freeze a fraction of every large crowd
##   permanently, which reads as a rendering bug and is a simulation one.
##   Check 8.
##
## Headless cannot check the MultiMesh layout itself — the dummy rendering
## server backs no MultiMesh storage, so MultiMesh.buffer round-trips empty
## (measured 2026-08-29). Check 7 therefore asserts the buffer this class
## PRODUCES against its own documented offsets; that the offsets are the ones
## Godot reads is confirmed by looking at a windowed render.
##
## Fixture rather than the real map, same reasoning verify_infestation.gd
## records: HexMapGenerator builds the whole UK+Ireland corridor on every run.

const _FIXTURE_RADIUS: int = 8
const _CAPACITY: int = 2_500_000  ## Well above _CROWDED_RESIDENTS: InfestationManager clamps a hex to its own total_zombie_pop, so a small fixture capacity would silently cap the demand this file is trying to overload the budget with.
const _CENTER := Vector2i.ZERO

## Deliberately larger than ENTITY_BUDGET so the allocator has to refuse
## somebody — a fixture that fits inside the budget cannot prove a cap exists.
const _CROWDED_RESIDENTS: int = 2_400_000

## Far enough from the camera that it is live only because a building stands
## on it, and last in every nearest-first ordering.
const _DISTANT := Vector2i(7, 0)

var _map: HexGridMap
var _camera: CameraController
var _hordes: HordeManager
var _infestation: InfestationManager
var _tracker: LiveHexTracker
var _swarms: ZombieSwarmManager
var _failures: Array[String] = []


func _ready() -> void:
	_map = load("res://scenes/world/HexGridMap.tscn").instantiate()
	_map.auto_generate_on_ready = false
	_map.name = "HexGridMap"
	add_child(_map)
	_map.load_cells(_build_fixture_cells())

	_camera = load("res://scenes/camera/CameraController.tscn").instantiate()
	_camera.name = "CameraController"
	add_child(_camera)
	_look_at_hex(_CENTER)

	_hordes = load("res://scenes/world/HordeManager.tscn").instantiate()
	_hordes.name = "HordeManager"
	# Wired before add_child so _ready() resolves it, and the fixture's
	# district-less cells make seed_starting_hordes() a no-op — same setup and
	# same guard verify_infestation.gd uses, for the same reason: randomly
	# placed starting hordes would make every count below position-dependent.
	_hordes.hex_grid_map_path = NodePath("../HexGridMap")
	add_child(_hordes)
	if not _hordes.get_all_hordes().is_empty():
		_failures.append("the fixture seeded %d starting hordes — every count below is position-dependent" % _hordes.get_all_hordes().size())

	_infestation = load("res://scenes/world/InfestationManager.tscn").instantiate()
	_infestation.name = "InfestationManager"
	_infestation.hex_grid_map_path = NodePath("../HexGridMap")
	_infestation.horde_manager_path = NodePath("../HordeManager")
	add_child(_infestation)

	_tracker = load("res://scenes/world/LiveHexTracker.tscn").instantiate()
	_tracker.name = "LiveHexTracker"
	_tracker.camera_path = NodePath("../CameraController")
	_tracker.hex_grid_map_path = NodePath("../HexGridMap")
	add_child(_tracker)

	_swarms = load("res://scenes/world/ZombieSwarmManager.tscn").instantiate()
	_swarms.name = "ZombieSwarmManager"
	_swarms.live_hex_tracker_path = NodePath("../LiveHexTracker")
	_swarms.horde_manager_path = NodePath("../HordeManager")
	_swarms.infestation_manager_path = NodePath("../InfestationManager")
	add_child(_swarms)

	get_tree().quit(_run())


func _run() -> int:
	_check_live_hex_rule()
	_check_budget_is_never_exceeded()
	_check_nearest_observer_first()
	_check_hordes_are_served_before_residents()
	_check_counts_are_a_view()
	_check_dissolve_and_recondense_conserves()
	_check_buffer_layout()
	_check_every_zombie_is_stepped()
	_check_crowd_follows_its_anchor()
	_check_save_round_trip()
	_check_horde_keeps_its_crowd_across_a_boundary()

	print()
	if _failures.is_empty():
		print("All tactical zombie checks passed.")
		return 0
	print("FAILED (%d):" % _failures.size())
	for failure in _failures:
		print("  " + failure)
	return 1


## --- 1. D13's live-hex rule -------------------------------------------------

func _check_live_hex_rule() -> void:
	_look_at_hex(_CENTER)
	_tracker.refresh()
	var live := _tracker.get_live_hexes()
	print("live at Tactical zoom, camera on %s: %d hexes" % [_CENTER, live.size()])
	if live.size() != 7:
		_failures.append("camera hex + 6 neighbours is 7 hexes, got %d" % live.size())
	for coord in HexCoord.hex_disk(_CENTER, 1):
		if not _tracker.is_live(coord):
			_failures.append("%s is in the camera's own neighbourhood and is not live" % coord)
	if _tracker.is_live(_DISTANT):
		_failures.append("%s is 7 hexes away with nothing on it and is live" % _DISTANT)

	# The one addition this project makes to the spec's rule: no Tactical zoom,
	# no individuals. Nothing can draw them, so nothing should build them.
	_camera.zoom = Vector2.ONE * (_camera.tactical_zoom_threshold * 0.5)
	_tracker.refresh()
	print("live at Strategic zoom: %d hexes" % _tracker.get_live_hexes().size())
	if not _tracker.get_live_hexes().is_empty():
		_failures.append("the live set is not empty at Strategic zoom, where no individual can be drawn")
	_swarms.allocate()
	if _swarms.get_entity_count() != 0:
		_failures.append("%d zombies instantiated at Strategic zoom" % _swarms.get_entity_count())

	_camera.zoom = Vector2.ONE * 4.0
	_tracker.refresh()


## --- 2. The budget ----------------------------------------------------------

func _check_budget_is_never_exceeded() -> void:
	_reset_world()
	# Every hex in the camera's neighbourhood crowded, so the allocator has to
	# stop partway through rather than simply running out of hexes.
	for coord in HexCoord.hex_disk(_CENTER, 1):
		_infestation.add_zombies(coord, _CROWDED_RESIDENTS)
	_swarms.allocate()

	var total := _swarms.get_entity_count()
	var actual := 0
	for coord in HexCoord.hex_disk(_CENTER, 1):
		actual += _swarms.entity_count_at(coord)
	print("7 hexes holding %s zombies each -> %d instantiated (budget %d)"
			% [_CROWDED_RESIDENTS, actual, ZombieSwarmManager.ENTITY_BUDGET])
	if total > ZombieSwarmManager.ENTITY_BUDGET:
		_failures.append("allocated %d, over the %d budget" % [total, ZombieSwarmManager.ENTITY_BUDGET])
	if actual != total:
		_failures.append("reported %d entities, the swarms actually hold %d" % [total, actual])
	# Demand is 280x the budget, so anything short of spending all of it is a
	# bug in the walk, not a shortage.
	if total != ZombieSwarmManager.ENTITY_BUDGET:
		_failures.append("spent %d of a %d budget with 2.4M zombies per hex asking for it"
				% [total, ZombieSwarmManager.ENTITY_BUDGET])
	_check_slicing_is_global()


## Slicing sized per swarm instead of per frame was a real 4x regression (see
## ZombieSwarm.SLICE_TARGET_ENTITIES), and it is invisible from any single
## crowd: the fixture below gives every swarm a count far under the slice
## target while the FRAME holds several times it, so a per-swarm rule reports
## 1 and the correct rule reports more.
func _check_slicing_is_global() -> void:
	_reset_world()
	var per_hex := ZombieSwarm.SLICE_TARGET_ENTITIES / 2
	for coord in HexCoord.hex_disk(_CENTER, 1):
		_infestation.add_zombies(coord, per_hex)
	_swarms.allocate()

	var total := _swarms.get_entity_count()
	var expected := ZombieSwarm.slices_for(total)
	var largest_swarm := 0
	var wrong := 0
	for swarm: ZombieSwarm in _swarms.get_swarms():
		largest_swarm = maxi(largest_swarm, swarm.size())
		if swarm.slice_count() != expected:
			wrong += 1
	print("%d zombies over %d swarms (largest %d): every swarm slices %d, per-swarm rule would say %d"
			% [total, _swarms.get_swarms().size(), largest_swarm, expected,
			ZombieSwarm.slices_for(largest_swarm)])
	if expected <= ZombieSwarm.slices_for(largest_swarm):
		_failures.append("the fixture cannot tell a global slice rule from a per-swarm one — largest swarm is %d of %d total"
				% [largest_swarm, total])
	if wrong > 0:
		_failures.append("%d swarms are not sliced by the frame's whole population" % wrong)


## --- 3. Nearest the observer first ------------------------------------------

func _check_nearest_observer_first() -> void:
	_reset_world()
	# Both hexes want more than the whole budget. The camera's hex must take it.
	_infestation.add_zombies(_CENTER, _CROWDED_RESIDENTS)
	_infestation.add_zombies(_DISTANT, _CROWDED_RESIDENTS)
	# _DISTANT is live only because it is a player hex; the tracker reads that
	# from BuildingManager in the real game, so the fixture drives the same
	# path by making it live directly.
	_force_live([_CENTER, _DISTANT])
	_swarms.allocate()

	var near := _swarms.entity_count_at(_CENTER)
	var far := _swarms.entity_count_at(_DISTANT)
	print("camera hex %d zombies, hex 7 away %d zombies (both hold %s)" % [near, far, _CROWDED_RESIDENTS])
	if near != ZombieSwarmManager.ENTITY_BUDGET:
		_failures.append("the camera's own hex got %d of the %d budget" % [near, ZombieSwarmManager.ENTITY_BUDGET])
	if far != 0:
		_failures.append("a hex 7 rings away got %d zombies while the camera hex was still hungry" % far)


## --- 4. A horde is never starved by residents -------------------------------

func _check_hordes_are_served_before_residents() -> void:
	_reset_world()
	var besieged := _CENTER + Vector2i(1, 0)
	# The camera's own hex is a Hive Core wanting far more than the budget; the
	# horde is one hex further out, so a purely nearest-first walk would reach
	# it only after the budget was gone.
	_infestation.add_zombies(_CENTER, _CROWDED_RESIDENTS)
	_hordes.spawn_horde_at(besieged, 800)
	_force_live(HexCoord.hex_disk(_CENTER, 1))
	_swarms.allocate()

	var horde_entities := _swarms.entity_count_at(besieged)
	print("horde of 800 next to a 2.4M-resident hex -> %d individuals drawn" % horde_entities)
	if horde_entities != 800:
		_failures.append("a besieging horde of 800 got %d individuals — pass 1 is not reserving for hordes" % horde_entities)


## --- 5. Counts are a view, never a source of truth ---------------------------

func _check_counts_are_a_view() -> void:
	_reset_world()
	var coord := _CENTER + Vector2i(1, 0)
	_hordes.spawn_horde_at(coord, 500)
	_infestation.add_zombies(_CENTER, 3_000)
	_force_live(HexCoord.hex_disk(_CENTER, 1))
	_swarms.allocate()

	var horde: Horde = _hordes.get_hordes_at(coord)[0]
	var before_size := horde.size
	var before_residents := _infestation.resident_count_at(_CENTER)
	for i in 120:
		_swarms.step(1.0 / 60.0)
	_swarms.allocate()

	print("after 120 steps: horde %d -> %d, residents %d -> %d"
			% [before_size, horde.size, before_residents, _infestation.resident_count_at(_CENTER)])
	if horde.size != before_size:
		_failures.append("stepping the tactical layer changed a Horde's size (%d -> %d)" % [before_size, horde.size])
	if _infestation.resident_count_at(_CENTER) != before_residents:
		_failures.append("stepping the tactical layer changed a hex's resident count")

	# Killing at the strategic layer must pull the view down with it.
	_hordes.remove_horde(horde)
	_swarms.allocate()
	if _swarms.entity_count_at(coord) != 0:
		_failures.append("removing a horde left %d of its individuals standing" % _swarms.entity_count_at(coord))


## --- 6. Dissolve and re-condense -------------------------------------------

func _check_dissolve_and_recondense_conserves() -> void:
	_reset_world()
	var coord := _CENTER + Vector2i(1, 0)
	_hordes.spawn_horde_at(coord, 400)
	_infestation.add_zombies(coord, 5_000)
	_force_live(HexCoord.hex_disk(_CENTER, 1))
	_swarms.allocate()
	var live_entities := _swarms.entity_count_at(coord)

	var horde: Horde = _hordes.get_hordes_at(coord)[0]
	var size_before := horde.size
	var residents_before := _infestation.resident_count_at(coord)

	# Pan far away: the hex leaves the live set and every swarm on it is
	# destroyed. §2.1 calls this re-condensing; here it costs nothing to get
	# right, because the count never left the Horde in the first place.
	_look_at_hex(Vector2i(-6, 0))
	_tracker.refresh()
	_swarms.allocate()
	var after_dissolve := _swarms.entity_count_at(coord)

	print("crowd of %d dissolved to %d on panning away; horde %d -> %d, residents %d -> %d"
			% [live_entities, after_dissolve, size_before, horde.size,
			residents_before, _infestation.resident_count_at(coord)])
	if after_dissolve != 0:
		_failures.append("panning away left %d individuals on an unobserved hex" % after_dissolve)
	if horde.size != size_before:
		_failures.append("re-condensing changed the horde's size (%d -> %d)" % [size_before, horde.size])
	if _infestation.resident_count_at(coord) != residents_before:
		_failures.append("re-condensing changed the hex's resident count (%d -> %d)"
				% [residents_before, _infestation.resident_count_at(coord)])

	_look_at_hex(_CENTER)
	_force_live(HexCoord.hex_disk(_CENTER, 1))
	_swarms.allocate()
	if _swarms.entity_count_at(coord) != live_entities:
		_failures.append("panning back gave %d individuals, not the %d that dissolved"
				% [_swarms.entity_count_at(coord), live_entities])


## --- 7. The buffer this class produces --------------------------------------

func _check_buffer_layout() -> void:
	var swarm := ZombieSwarm.new(1234)
	swarm.anchor = Vector2(1000.0, -500.0)
	swarm.spread = 100.0
	swarm.set_count(64)
	var buffer := swarm.buffer()
	var positions := swarm.get_positions()

	if buffer.size() != 64 * ZombieSwarm.TRANSFORM_FLOATS:
		_failures.append("buffer is %d floats for 64 zombies, expected %d"
				% [buffer.size(), 64 * ZombieSwarm.TRANSFORM_FLOATS])
		return

	var mismatches := 0
	var bad_basis := 0
	for i in 64:
		var base := i * ZombieSwarm.TRANSFORM_FLOATS
		if absf(buffer[base + ZombieSwarm.ORIGIN_X_INDEX] - positions[i * 2]) > 0.01:
			mismatches += 1
		if absf(buffer[base + ZombieSwarm.ORIGIN_Y_INDEX] - positions[i * 2 + 1]) > 0.01:
			mismatches += 1
		# The rotation half is written once at spawn and must survive stepping,
		# or every zombie renders as a degenerate quad.
		if buffer[base] != 1.0 or buffer[base + 5] != 1.0 or buffer[base + 1] != 0.0 or buffer[base + 4] != 0.0:
			bad_basis += 1

	for i in 20:
		swarm.step(1.0 / 60.0)
	buffer = swarm.buffer()
	positions = swarm.get_positions()
	var stale := 0
	for i in 64:
		var base := i * ZombieSwarm.TRANSFORM_FLOATS
		if absf(buffer[base + ZombieSwarm.ORIGIN_X_INDEX] - positions[i * 2]) > 0.01:
			stale += 1
		if buffer[base] != 1.0 or buffer[base + 5] != 1.0:
			bad_basis += 1

	print("buffer: %d floats, %d origin mismatches at spawn, %d stale after 20 steps, %d bad bases"
			% [buffer.size(), mismatches, stale, bad_basis])
	if mismatches > 0:
		_failures.append("%d buffer origins disagree with get_positions() at spawn" % mismatches)
	if stale > 0:
		_failures.append("%d buffer origins were not republished after stepping" % stale)
	if bad_basis > 0:
		_failures.append("%d transforms have a non-identity basis" % bad_basis)


## --- 8. Slicing reaches everybody -------------------------------------------

func _check_every_zombie_is_stepped() -> void:
	var count := ZombieSwarm.SLICE_TARGET_ENTITIES * ZombieSwarm.MAX_SLICES
	var swarm := ZombieSwarm.new(77)
	swarm.anchor = Vector2.ZERO
	swarm.spread = 4000.0  ## Wide, so nobody is pinned by the return-to-anchor branch.
	swarm.slices = ZombieSwarm.slices_for(count)
	swarm.set_count(count)
	var slices := swarm.slice_count()
	var before := swarm.get_positions()

	for i in slices:
		swarm.step(1.0 / 60.0)
	var after := swarm.get_positions()

	var unmoved := 0
	for i in count:
		if before[i * 2] == after[i * 2] and before[i * 2 + 1] == after[i * 2 + 1]:
			unmoved += 1
	print("%d zombies in %d slices: %d never moved in %d steps" % [count, slices, unmoved, slices])
	if slices != ZombieSwarm.MAX_SLICES:
		_failures.append("%d zombies sliced into %d passes, expected the MAX_SLICES cap of %d"
				% [count, slices, ZombieSwarm.MAX_SLICES])
	if unmoved > 0:
		_failures.append("%d of %d zombies were never visited in a full slice cycle" % [unmoved, count])


## --- 9. The crowd follows a moving anchor -----------------------------------

## The check that caught the first cut's real bug: milling speed is a quarter
## of BASE_MOVE_SPEED, so a crowd steered home at milling speed can never
## follow a horde travelling at 1.5x it, and every advancing horde would have
## left its individuals strewn behind it across the map.
func _check_crowd_follows_its_anchor() -> void:
	var swarm := ZombieSwarm.new(9)
	swarm.anchor = Vector2.ZERO
	swarm.spread = 40.0
	swarm.set_count(300)
	for i in 200:
		swarm.step(1.0 / 60.0)
	var settled := _max_distance_from_anchor(swarm)

	# An advancing horde, at the fastest it ever moves: BASE_MOVE_SPEED with
	# HordeManager's night multiplier. The crowd must stay with it for the
	# whole crossing, not merely end up near it.
	var per_step := MovementStepper.BASE_MOVE_SPEED * HordeManager.NIGHT_MOVE_SPEED_MULTIPLIER / 60.0
	var worst_while_moving := 0.0
	for i in 600:
		swarm.anchor += Vector2(per_step, 0.0)
		swarm.step(1.0 / 60.0)
		worst_while_moving = maxf(worst_while_moving, _max_distance_from_anchor(swarm))
	var chase_limit := swarm.spread * ZombieSwarm.SNAP_SPREAD_MULTIPLE

	# A teleport, which is what a load or a step at 1000x game speed looks
	# like from in here. Chasing it across 5,000 world units would be visible
	# nonsense; re-forming around the anchor is the intended answer.
	swarm.anchor = Vector2(50_000.0, 0.0)
	var reformed := -1
	for i in 8:
		swarm.step(1.0 / 60.0)
		if _max_distance_from_anchor(swarm) <= swarm.spread * 1.5:
			reformed = i + 1
			break

	print("settled within %.1f wu (spread %.0f); worst lag while advancing at %.1f wu/s was %.1f wu; re-formed after a teleport in %d steps"
			% [settled, swarm.spread, per_step * 60.0, worst_while_moving, reformed])
	if settled > swarm.spread * 1.5:
		_failures.append("a settled crowd strayed %.1f wu from an anchor with spread %.0f" % [settled, swarm.spread])
	if worst_while_moving > chase_limit:
		_failures.append("a crowd fell %.1f wu behind an advancing horde, past the %.1f wu snap threshold — CHASE_SPEED does not exceed horde speed"
				% [worst_while_moving, chase_limit])
	if reformed < 0:
		_failures.append("the crowd never re-formed around a teleported anchor")


func _max_distance_from_anchor(swarm: ZombieSwarm) -> float:
	var worst := 0.0
	for i in swarm.size():
		worst = maxf(worst, swarm.position_at(i).distance_to(swarm.anchor))
	return worst


## --- 10. Save round trip (D15) ----------------------------------------------

func _check_save_round_trip() -> void:
	_reset_world()
	var coord := _CENTER + Vector2i(1, 0)
	_hordes.spawn_horde_at(coord, 600)
	_force_live(HexCoord.hex_disk(_CENTER, 1))
	_swarms.allocate()
	for i in 90:
		_swarms.step(1.0 / 60.0)

	var state := _swarms.get_save_state()
	var saved_floats: int = state[coord].size() if state.has(coord) else 0
	var before := _positions_on(coord)

	_swarms.load_save_state(state)
	var after := _positions_on(coord)

	var moved := 0
	for i in mini(before.size(), after.size()):
		if before[i].distance_to(after[i]) > 0.01:
			moved += 1
	print("save round trip on %s: %d floats, %d/%d individuals restored in place"
			% [coord, saved_floats, before.size() - moved, before.size()])
	if saved_floats != 600 * 2:
		_failures.append("saved %d floats for 600 zombies, expected %d" % [saved_floats, 600 * 2])
	if before.size() != after.size():
		_failures.append("restored %d individuals from a save of %d" % [after.size(), before.size()])
	if moved > 0:
		_failures.append("%d individuals teleported across a save/load — D15's whole point" % moved)

	# A count that moved between save and load must still land: the layer
	# re-sizes from the strategic count and takes as many saved positions as
	# it can use, rather than trusting the save's own length.
	_hordes.get_hordes_at(coord)[0].size = 200
	_swarms.load_save_state(state)
	print("same save applied after the horde was killed down to 200: %d individuals"
			% _swarms.entity_count_at(coord))
	if _swarms.entity_count_at(coord) != 200:
		_failures.append("a save of 600 restored %d individuals onto a horde of 200"
				% _swarms.entity_count_at(coord))


func _positions_on(coord: Vector2i) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for swarm: ZombieSwarm in _swarms.get_swarms():
		if swarm.anchor.distance_to(HexCoord.axial_to_world(coord)) > HexCoord.HEX_SIZE:
			continue
		for i in swarm.size():
			out.append(swarm.position_at(i))
	return out


## --- 11. A horde keeps its crowd across a hex boundary ----------------------

## §2.1: "the seam is a pure representation change, so the player never sees a
## horde 'pop' — it arrives as individuals." The first cut keyed a horde's
## crowd by (hex, horde id), so stepping across a boundary destroyed the group
## and built a fresh one — a full re-scatter at the exact moment a horde
## reaches the player's wall.
func _check_horde_keeps_its_crowd_across_a_boundary() -> void:
	_reset_world()
	var from_coord := _CENTER + Vector2i(1, 0)
	var to_coord := _CENTER + Vector2i(0, 1)
	_hordes.spawn_horde_at(from_coord, 300)
	_force_live(HexCoord.hex_disk(_CENTER, 1))
	_swarms.allocate()
	for i in 30:
		_swarms.step(1.0 / 60.0)
	var before := _positions_on(from_coord)

	var horde: Horde = _hordes.get_hordes_at(from_coord)[0]
	horde.hex_coord = to_coord
	_swarms.allocate()
	var after := _positions_on(to_coord)

	var moved := 0
	for i in mini(before.size(), after.size()):
		if before[i].distance_to(after[i]) > 1.0:
			moved += 1
	print("horde crossed %s -> %s: %d individuals before, %d after, %d re-scattered"
			% [from_coord, to_coord, before.size(), after.size(), moved])
	if after.size() != before.size():
		_failures.append("crossing a hex boundary changed a crowd from %d to %d individuals"
				% [before.size(), after.size()])
	if moved > 0:
		_failures.append("%d individuals were re-scattered by their horde crossing a hex boundary" % moved)


## --- Fixture ----------------------------------------------------------------

func _build_fixture_cells() -> Dictionary:
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(_CENTER, _FIXTURE_RADIUS):
		var cell := HexCell.new(coord)
		cell.biome_type = GameEnums.BiomeType.MOORLAND
		cell.soil_fertility = GameEnums.SoilFertility.POOR
		cell.total_zombie_pop = _CAPACITY
		cells[coord] = cell
	return cells


## Puts the camera at a hex's exact center, at a zoom well inside Tactical.
func _look_at_hex(coord: Vector2i) -> void:
	_camera.global_position = HexCoord.axial_to_world(coord)
	_camera.zoom = Vector2.ONE * 4.0


## Clears every horde and every resident count. Each check builds the world it
## needs from nothing, so an earlier check's crowd cannot make a later one pass.
func _reset_world() -> void:
	for horde in _hordes.get_all_hordes():
		_hordes.remove_horde(horde)
	for coord in HexCoord.hex_disk(_CENTER, _FIXTURE_RADIUS):
		var residents := _infestation.resident_count_at(coord)
		if residents > 0:
			_infestation.remove_zombies(coord, residents)
	_look_at_hex(_CENTER)
	_tracker.refresh()
	_swarms.allocate()


## In the real game a distant hex is live because BuildingManager says the
## player owns it; the fixture has no buildings, so it drives the tracker's
## own set directly rather than standing up a BuildingManager and a
## ResourceManager to place one.
func _force_live(coords: Array[Vector2i]) -> void:
	var ordered: Array[Vector2i] = []
	for coord in coords:
		if not ordered.has(coord):
			ordered.append(coord)
	_tracker.override_live_hexes_for_test(ordered)
