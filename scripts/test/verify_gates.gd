extends Node

## Checks the one rule the Gate rework exists to create, on a small
## hand-built fixture perimeter rather than the real seeded starting hex:
##
##   the player's own units can leave the walled starting hex; a horde
##   cannot get in.
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

var _map: HexGridMap
var _buildings: BuildingManager
var _walls: WallManager


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

	get_tree().quit(_run())


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


func _run() -> int:
	var segments := _walls.get_segments()
	var gates := segments.filter(func(s: WallSegment) -> bool: return s.is_gate)
	print("seeded perimeter: %d segments, %d of them gates" % [segments.size(), gates.size()])
	if gates.is_empty():
		print("FAIL: the starting perimeter has no gate, so nothing can leave it.")
		return 1

	# Somewhere outside the perimeter, far enough that any route has to cross
	# the ring rather than wander around inside one hex.
	var goal := _first_passable_at_distance(_START, 4)
	if goal == Vector2i.ZERO:
		print("FAIL: no passable hex 4 rings out to route to.")
		return 1

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

	for failure in failures:
		print("FAIL: %s" % failure)
	return 1 if not failures.is_empty() else 0


func _first_passable_at_distance(from: Vector2i, radius: int) -> Vector2i:
	for coord in HexCoord.hex_ring(from, radius):
		var cell := _map.get_cell(coord)
		if cell and cell.is_passable():
			return coord
	return Vector2i.ZERO
