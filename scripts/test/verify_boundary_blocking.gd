extends Node

## Proves the boundary rule's MOUNTAIN gate blocks and un-blocks exactly where
## it should, on a fixture whose elevations are set by hand.
##
## Run:
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/verify_boundary_blocking.tscn
##
## Companion to scripts/test/verify_boundary_connectivity.gd, which runs the
## rule over the real corridor and answers the opposite question (does it
## strand anything). A rule that never fires passes that check perfectly while
## doing nothing, so "it is safe" and "it works" cannot be the same run.
##
## The branch under test is the one with real regression risk, and it is the
## reason SubHexPortalGraph consults a macro hex at all rather than being
## purely sub-hex (see its own comment): MountainPassCarver opens a pass by
## LOWERING HexCell.elevation at generation, and that carve exists only in hex
## data — the baked elevation raster the sub-hex layer samples knows nothing
## about it. Deriving the mountain verdict per sub-cell from the raster would
## therefore re-seal every carved pass and strand exactly the hexes
## MountainPassCarver exists to keep reachable, which is the failure
## scripts/test/verify_elevation.gd was originally written to catch. This
## checks a carved pass still crosses.
##
## Elevations are set through MountainPassCarver.pass_elevation() and
## ElevationLevels.mountain_threshold_elevation() rather than as literals, so
## the test cannot drift out of step with the thresholds it is asserting about.

const _CENTRE := Vector2i(0, 0)
const _NEIGHBOUR := Vector2i(1, 0)

var _map: HexGridMap


func _ready() -> void:
	_map = load("res://scenes/world/HexGridMap.tscn").instantiate()
	_map.auto_generate_on_ready = false
	add_child(_map)
	get_tree().quit(_run())


## A small passable disk, all default HexCell fields (MOORLAND, no terrain
## feature, elevation 0.0 — passable per HexCell.is_passable()). Deliberately
## outside RealTerrainSampler's baked corridor so every sub-hex sample returns
## {} and falls back to the macro verdict: that isolates the mountain gate from
## the raster, which is what this test is about. The seam case the rule also
## covers is real-data-dependent and is measured by the connectivity run
## instead.
func _load_fixture() -> void:
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(_CENTRE, 3):
		cells[coord] = HexCell.new(coord)
	_map.load_cells(cells)
	SubHexPortalGraph.clear_cache()
	SubHexTerrainQuery.clear_cache()


func _set_elevation(coord: Vector2i, elevation: float) -> void:
	_map.get_cell(coord).elevation = elevation
	SubHexPortalGraph.clear_cache()  ## has_any_crossing() caches per hex pair; the fixture is mutated between cases.


func _run() -> int:
	var failures: Array[String] = []
	var mountain := ElevationLevels.mountain_threshold_elevation()

	# 1. Flat ground: the rule must not block an ordinary crossing. Without
	#    this, a rule that blocks everything would pass every other case here
	#    while severing the whole map.
	_load_fixture()
	var flat_blocked := HexPathfinder.is_boundary_impassable(_map, _CENTRE, _NEIGHBOUR)
	var flat_route := HexPathfinder.find_path(_map, _CENTRE, _NEIGHBOUR)
	print("flat ground:   blocked=%s route=%d" % [flat_blocked, flat_route.size()])
	if flat_blocked:
		failures.append("two ordinary flat neighbours are blocked")
	if flat_route.is_empty():
		failures.append("no route between two ordinary flat neighbours")

	# 2. Mountain: a summit hex must block every crossing into it.
	_load_fixture()
	_set_elevation(_NEIGHBOUR, mountain + 0.05)
	var peak_blocked := HexPathfinder.is_boundary_impassable(_map, _CENTRE, _NEIGHBOUR)
	print("mountain:      blocked=%s (neighbour level %d)" % [
		peak_blocked, _map.get_cell(_NEIGHBOUR).height_level()])
	if not peak_blocked:
		failures.append("a MOUNTAIN hex does not block the crossing into it")

	# 3. Carved pass: MountainPassCarver's own output elevation must cross.
	#    This is the regression the macro-hex gate exists to prevent.
	_load_fixture()
	_set_elevation(_NEIGHBOUR, MountainPassCarver.pass_elevation())
	var pass_blocked := HexPathfinder.is_boundary_impassable(_map, _CENTRE, _NEIGHBOUR)
	var pass_route := HexPathfinder.find_path(_map, _CENTRE, _NEIGHBOUR)
	print("carved pass:   blocked=%s route=%d (neighbour level %d)" % [
		pass_blocked, pass_route.size(), _map.get_cell(_NEIGHBOUR).height_level()])
	if pass_blocked:
		failures.append("a carved MountainPassCarver pass is blocked — the carve has been undone")
	if pass_route.is_empty():
		failures.append("no route through a carved pass")

	for failure in failures:
		print("FAIL: %s" % failure)
	return 1 if not failures.is_empty() else 0
