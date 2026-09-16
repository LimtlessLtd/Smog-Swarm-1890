extends Node

## Checks the one rule the Gate rework exists to create, on a small
## hand-built fixture perimeter rather than the real seeded starting hex:
##
##   the player's own units can leave the walled starting hex; a horde
##   cannot get in.
##
## D18, verbatim: "for all intents and purposes walls and gates are the same,
## the only difference is friendly units can pass through gates." Checked at
## three layers, because each has failed on its own before:
##   1. HexPathfinder.find_path() — the route exists for a unit and not for a
##      horde.
##   2. A real UnitOrderController walking a real unit out, frame by frame.
##      The route and the per-crossing re-check (_blocked_by_wall()) once
##      disagreed and live-locked a unit in place with a valid route, which a
##      pathfinder-only check cannot see. The unit must also leave START
##      through an edge that holds a gate, not around the ring somehow.
##   3. The line HordeManager._advance_horde() tests, aimed straight at the
##      gate: it must hit the gate itself (so the horde sieges it), and once
##      the gate is breached it must stop blocking anything.
##
## Run (as a real scene, not `-s`):
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/verify_gates.tscn
##
## Why a scene and not a `-s` SceneTree script (the shape verify_elevation.gd
## uses): `-s` does not resolve autoload singletons as GDScript identifiers
## at compile time, so any script that references one — TickManager,
## TimeCycleManager, transitively pulled in by BuildingManager/WallManager/
## HordeManager/TechManager — fails to compile at all under `-s`. Loading an
## actual scene goes through the normal autoload-registration path (same
## reason the project's own convention is "run --headless scenes/main/
## Main.tscn --quit" for anything touching a manager's _ready()). Confirmed
## by reproducing the compile cascade directly before rewriting this.
##
## Why a fixture and not the real map (this script's own prior version):
## instantiating the real HexGridMap scene runs HexMapGenerator, which since
## the Real-Geography Vector Terrain epic's full-map pass (design_doc.md §1,
## 99.9% coverage) generates the ENTIRE UK+Ireland corridor on every run —
## many minutes of real work (measured: still running after 90s, over 1GB
## RSS and climbing) for a check that only needs a handful of hexes. This
## script builds its own small hex_disk fixture and installs it via
## HexGridMap.load_cells() instead of calling generate_map().
##
## Both halves fail SILENTLY and in opposite directions, which is why this
## exists as a script rather than a look at the screen: a wall that blocks
## nothing looks exactly like a wall that works until a horde walks through
## it, and a gate that blocks the player looks exactly like a wall until a
## garrison sits trapped in its own perimeter with no message about why.

const _FIXTURE_RADIUS := 6  ## Must exceed the distance-4 ring _run() routes to, with room for the perimeter wall itself.
const _START: Vector2i = Vector2i.ZERO
const _MAX_WALK_FRAMES := 12000  ## verify_unit_border_crossing.gd measured ~480 frames per hex; the gated route is ~7 hexes.
## A unit live-locked at a wall re-plans every frame, so frames get slow exactly
## when the check is failing: a first cut bounded by frames alone ran past 10
## minutes. Passing takes ~20 s.
const _MAX_WALK_MSEC := 120000

var _map: HexGridMap
var _buildings: BuildingManager
var _walls: WallManager
var _units: UnitManager
var _orders: UnitOrderController


func _ready() -> void:
	# NodePaths set by hand ("../SiblingName") rather than via get_path_to():
	# get_path_to() needs BOTH nodes already inside the tree to find a common
	# ancestor, but the DI convention (@export var *_path resolved in
	# _ready()) needs the path set BEFORE add_child() triggers that
	# resolution. All three managers end up as siblings directly under this
	# node, same as the scenes/*.tscn each one instantiates from names itself.
	_map = load("res://scenes/world/HexGridMap.tscn").instantiate()
	_map.auto_generate_on_ready = false
	add_child(_map)
	_map.load_cells(_build_fixture_cells())

	_buildings = load("res://scenes/buildings/BuildingManager.tscn").instantiate()
	_buildings.hex_grid_map_path = NodePath("../HexGridMap")
	add_child(_buildings)

	_walls = load("res://scenes/defense/WallManager.tscn").instantiate()
	_walls.hex_grid_map_path = NodePath("../HexGridMap")
	_walls.building_manager_path = NodePath("../BuildingManager")
	add_child(_walls)

	# seed_starting_buildings() scans for is_settlement+URBAN+region_name==
	# "Manchester", which the fixture's center hex satisfies; it also places
	# a free Town Hall/Lumber Yard/Farm, which this check doesn't need but
	# costs nothing to let happen (_register_instance() bypasses resource
	# spend) — cheaper than duplicating its target-selection logic here.
	_buildings.seed_starting_buildings()
	_walls.seed_starting_defenses()

	_units = load("res://scenes/units/UnitManager.tscn").instantiate()
	_units.hex_grid_map_path = NodePath("../HexGridMap")
	add_child(_units)

	_orders = load("res://scenes/units/UnitOrderController.tscn").instantiate()
	_orders.hex_grid_map_path = NodePath("../HexGridMap")
	_orders.unit_manager_path = NodePath("../UnitManager")
	_orders.wall_manager_path = NodePath("../WallManager")
	add_child(_orders)

	var failures := _run()
	failures.append_array(await _run_unit_walk())
	failures.append_array(_run_horde_at_gate())
	for failure in failures:
		print("FAIL: %s" % failure)
	if failures.is_empty():
		print("PASS: units route and walk through gates; hordes are stopped by, siege, and pass only a breached gate")
	get_tree().quit(1 if not failures.is_empty() else 0)


## One hex_disk around _START: default HexCell fields (MOORLAND, no terrain
## feature, elevation 0.0) are already passable per HexCell.is_passable(), so
## every hex needs no field set beyond coord — except the center, marked as
## the settlement BuildingManager.get_starting_settlement_hexes() expects.
func _build_fixture_cells() -> Dictionary:
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(_START, _FIXTURE_RADIUS):
		var cell := HexCell.new(coord)
		if coord == _START:
			cell.is_settlement = true
			cell.biome_type = GameEnums.BiomeType.URBAN
			cell.region_name = "Manchester"
		cells[coord] = cell
	return cells


func _run() -> Array[String]:
	var segments := _walls.get_segments()
	var gates := segments.filter(func(s: WallSegment) -> bool: return s.is_gate)
	print("seeded perimeter: %d segments, %d of them gates" % [segments.size(), gates.size()])
	if gates.is_empty():
		return ["the starting perimeter has no gate, so nothing can leave it"]

	# Somewhere outside the perimeter, far enough that any route has to cross
	# the ring rather than wander around inside one hex.
	var goal := _first_passable_at_distance(_START, 4)
	if goal == Vector2i.ZERO:
		return ["no passable hex 4 rings out to route to"]

	var unit_route := HexPathfinder.find_path(_map, _START, goal, null, _walls, true)
	var horde_route := HexPathfinder.find_path(_map, _START, goal, null, _walls, false)
	print("unit route (gates passable):  %d hexes" % unit_route.size())
	print("horde route (gates blocking): %d hexes" % horde_route.size())

	var failures: Array[String] = []
	if unit_route.is_empty():
		failures.append("a unit cannot leave the starting perimeter — gates are not letting it through")
	if not horde_route.is_empty():
		failures.append("a horde routes straight out of the perimeter — the ring is not blocking")

	# The perimeter must also actually intersect a crossing. A wall laid
	# along the direction of travel rather than across it passes the two
	# checks above by being invisible to both, which is exactly the bug this
	# replaced.
	var blocked_edges := 0
	for neighbor in HexCoord.neighbors(_START):
		if _walls.get_blocking_segment(_START, neighbor, HexCoord.axial_to_world(_START), HexCoord.axial_to_world(neighbor)) != null:
			blocked_edges += 1
	print("boundary edges of the starting hex actually blocked to a horde: %d" % blocked_edges)
	if blocked_edges == 0:
		failures.append("no crossing out of the starting hex is blocked at all — the wall geometry never intersects a travel line")

	return failures


## Layer 2: a real unit, a real move order, real frames.
func _run_unit_walk() -> Array[String]:
	var goal := _first_passable_at_distance(_START, 4)
	var entry := UnitSaveEntry.new(GameEnums.UnitType.TRUNCHEONEER, _START, 1, 100.0)
	_units.load_save_entries([entry], 2)
	var instance := _units.get_all_units()[0]
	_orders.issue_move_order(instance, goal)

	var exit_hex := _START
	var frame := 0
	var started_msec := Time.get_ticks_msec()
	while frame < _MAX_WALK_FRAMES and Time.get_ticks_msec() - started_msec < _MAX_WALK_MSEC:
		await get_tree().process_frame
		frame += 1
		if exit_hex == _START and instance.hex_coord != _START:
			exit_hex = instance.hex_coord
		if instance.hex_coord == goal:
			break
	print("unit walk: ended at %s after %d frames, left the walled hex into %s" % [instance.hex_coord, frame, exit_hex])

	var failures: Array[String] = []
	if exit_hex == _START:
		failures.append("a unit ordered out of the perimeter never left the walled hex in %d frames" % frame)
	elif _walls.get_gate_crossing_offset(_START, exit_hex) == null:
		failures.append("the unit left the walled hex across %s->%s, an edge with no gate on it" % [_START, exit_hex])
	if instance.hex_coord != goal:
		failures.append("the unit did not reach %s (stuck at %s after %d frames)" % [goal, instance.hex_coord, frame])
	return failures


## Layer 3: the exact line HordeManager._advance_horde() tests — from the
## horde's own position to the next hex's crossing point — aimed through the
## middle of a gate.
func _run_horde_at_gate() -> Array[String]:
	var gate_neighbor := _START
	for neighbor in HexCoord.neighbors(_START):
		if _walls.get_gate_crossing_offset(_START, neighbor) != null:
			gate_neighbor = neighbor
			break
	if gate_neighbor == _START:
		return ["no boundary edge of the starting hex holds a gate"]

	var from_world := HexCoord.axial_to_world(_START)
	var to_world: Vector2 = HexCoord.axial_to_world(gate_neighbor) + _walls.get_gate_crossing_offset(_START, gate_neighbor)
	var failures: Array[String] = []
	var blocker := _walls.get_blocking_segment(_START, gate_neighbor, from_world, to_world)
	if blocker == null:
		return ["a horde walking straight at a gate is not blocked by anything"]
	if not blocker.is_gate:
		failures.append("the line through the gate's own midpoint hit solid wall id=%d, not the gate" % blocker.id)
	if _walls.get_blocking_segment(_START, gate_neighbor, from_world, to_world, true) != null:
		failures.append("the same line is blocked for a friendly unit")

	var hp_before := blocker.current_hp
	_walls.damage_segment(blocker, 1.0)
	print("horde at gate: blocked by %s id=%d, hp %.1f -> %.1f after 1.0 damage" % ["gate" if blocker.is_gate else "wall", blocker.id, hp_before, blocker.current_hp])
	if blocker.current_hp >= hp_before:
		failures.append("damage_segment() did not damage the gate — a horde cannot siege it")
	_walls.damage_segment(blocker, blocker.current_hp)
	if not blocker.is_breached():
		failures.append("a gate at 0 HP does not read as breached")
	elif _walls.get_blocking_segment(_START, gate_neighbor, from_world, to_world) != null:
		failures.append("a breached gate still blocks the horde's line")
	return failures


func _first_passable_at_distance(from: Vector2i, radius: int) -> Vector2i:
	for coord in HexCoord.hex_ring(from, radius):
		var cell := _map.get_cell(coord)
		if cell and cell.is_passable():
			return coord
	return Vector2i.ZERO
