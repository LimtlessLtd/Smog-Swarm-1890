extends Node

## Proves zombies get nothing from roads, rails or canals — and that they can
## still cross bridges. Run (as a real scene, not `-s`):
##
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/verify_horde_infrastructure.tscn
##
## D6, verbatim: "zombies shouldn't travel faster over roads or rails or canals
## because they can't drive or take the train lol"
##
## ## Why this needs a test rather than a read of the diff
##
## Infrastructure reaches a mover through TWO independent paths, and removing
## only one leaves the rule half-true in a way nothing visibly complains about:
##
##   * HexPathfinder.get_step_cost() decides which way something GOES.
##   * HexPathfinder.get_movement_speed_multiplier() decides how fast it MOVES.
##
## A horde denied the routing discount but not the speed one still sprints down
## any road its drift happens to cross. A horde denied the speed but not the
## routing still seeks roads out and then crawls along them. Only the pair is
## the rule, so both are checked here, separately.
##
## ## The vacuity trap
##
## "Horde is unaffected by the railway" passes trivially if the fixture's railway
## does not affect anything. Every check below therefore asserts the PLAYER's
## answer changes over the identical fixture, in the same call. A regression that
## disables the discount for everyone fails just as loudly as one that hands it
## back to hordes.
##
## ## Bridges are not a speed modifier
##
## The tempting implementation is to pass a null LogisticsNetwork for hordes.
## That also removes bridges — HexPathfinder.is_water_crossing_blocked() consults
## the same network — and would silently make every river in the game
## uncrossable for zombies, which is a far larger change than the one asked for
## and would look like terrain bugs, not like a pathfinding regression. Check 5
## is the guard.
##
## Fixture rather than the real map, same reasoning verify_gates.gd records:
## HexMapGenerator builds the entire UK+Ireland corridor on every run.

const _FIXTURE_RADIUS: int = 3
const _A: Vector2i = Vector2i.ZERO

## Railway is +300%, i.e. a 4.0 speed multiplier and a step costing
## BASE_HEX_COST / 4. Two railed steps therefore cost 0.5 against one plain
## MOORLAND step's 1.0, so a detour that is LONGER in hexes is CHEAPER for the
## player and dearer for a horde. That inversion is what makes the routing
## checks below read a real decision rather than a tie.
const _RAIL_SPEED: float = 4.0
const _EPSILON: float = 0.0001

var _map: HexGridMap
var _network: LogisticsNetwork
var _failures: Array[String] = []

var _b: Vector2i      ## Neighbour of _A: the direct one-step route.
var _c: Vector2i      ## Adjacent to both _A and _B: the two-step railed detour.
var _water: Vector2i  ## WATERWAY neighbour of _A, for the bridge check.


func _ready() -> void:
	_map = load("res://scenes/world/HexGridMap.tscn").instantiate()
	_map.auto_generate_on_ready = false
	add_child(_map)

	_pick_fixture_hexes()
	_map.load_cells(_build_fixture_cells())

	_network = load("res://scenes/logistics/LogisticsNetwork.tscn").instantiate()
	_network.hex_grid_map_path = NodePath("../HexGridMap")
	add_child(_network)

	# Railed detour A -> C -> B, leaving A -> B as plain ground.
	_network.add_supply_line(GameEnums.SupplyLineType.RAILWAY, _A, _c, 0)
	_network.add_supply_line(GameEnums.SupplyLineType.RAILWAY, _c, _b, 0)

	get_tree().quit(_run())


## _B is any neighbour of _A; _C is a hex adjacent to BOTH (two adjacent hexes
## always share exactly two such neighbours, so this cannot come up empty on a
## disk of radius 3). _WATER is a neighbour of _A that is neither.
func _pick_fixture_hexes() -> void:
	var a_neighbours := HexCoord.neighbors(_A)
	_b = a_neighbours[0]
	var b_neighbours := HexCoord.neighbors(_b)
	for candidate in a_neighbours:
		if candidate != _b and b_neighbours.has(candidate):
			_c = candidate
			break
	for candidate in a_neighbours:
		if candidate != _b and candidate != _c:
			_water = candidate
			break


## Default HexCell fields (MOORLAND, no feature, elevation 0) are passable and
## carry no _BIOME_COST_MULTIPLIER entry, so every step costs exactly
## BASE_HEX_COST and the only variable in play is infrastructure.
##
## _B is the exception, and has to be: it is WETLAND (1.8x). With _B left as
## plain ground the player's A* returned the direct route too, and NOT because
## the discount was broken — find_path()'s own doc comment records that its
## hex-count heuristic is inadmissible once a speed multiplier is in play. A*
## terminates when it POPS the goal, and an adjacent goal at f = 1.0 pops before
## the railed detour's first hex at f = 1.25, so the cheaper route is never
## examined. Making the direct step cost 1.8 puts the detour's entry ahead of it
## in the queue and the search sees both.
##
## That is a property of the fixture, not a workaround: the check needs a case
## where infrastructure genuinely changes a decision, and one step to an
## adjacent hex is too short a route for a routing discount to change anything.
func _build_fixture_cells() -> Dictionary:
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(_A, _FIXTURE_RADIUS):
		var cell := HexCell.new(coord)
		if coord == _water:
			cell.biome_type = GameEnums.BiomeType.WATERWAY
		elif coord == _b:
			cell.biome_type = GameEnums.BiomeType.WETLAND
		cells[coord] = cell
	return cells


func _run() -> int:
	_check_step_cost()
	_check_movement_speed()
	_check_routing()
	_check_flow_field()
	_check_bridges_still_crossable()

	print()
	if _failures.is_empty():
		print("All horde-infrastructure checks passed.")
		return 0
	print("FAILED (%d):" % _failures.size())
	for f in _failures:
		print("  " + f)
	return 1


## 1. Which way it GOES. A railed edge is cheap for the player, ordinary ground
##    for a horde.
func _check_step_cost() -> void:
	var cell_c := _map.get_cell(_c)
	var player := HexPathfinder.get_step_cost(_A, _c, cell_c, _network, true)
	var horde := HexPathfinder.get_step_cost(_A, _c, cell_c, _network, false)
	var plain := HexPathfinder.BASE_HEX_COST
	print("step cost over a railway: player %.3f, horde %.3f (plain ground %.3f)"
		% [player, horde, plain])

	if absf(player - plain / _RAIL_SPEED) > _EPSILON:
		_failures.append("player step cost over rail is %.3f, expected %.3f -- the fixture is not exercising the discount at all"
			% [player, plain / _RAIL_SPEED])
	if absf(horde - plain) > _EPSILON:
		_failures.append("horde step cost over rail is %.3f, expected plain ground %.3f"
			% [horde, plain])


## 2. How fast it MOVES. Separate mechanism from check 1, separate check.
func _check_movement_speed() -> void:
	var player := HexPathfinder.get_movement_speed_multiplier(_map, _network, _A, _c, true)
	var horde := HexPathfinder.get_movement_speed_multiplier(_map, _network, _A, _c, false)
	var terrain := HexPathfinder.get_terrain_speed_multiplier(_map.get_cell(_A))
	print("speed over a railway: player %.3fx, horde %.3fx (terrain alone %.3fx)"
		% [player, horde, terrain])

	if absf(player - _RAIL_SPEED) > _EPSILON:
		_failures.append("player speed over rail is %.3fx, expected %.3fx -- fixture not exercising the bonus"
			% [player, _RAIL_SPEED])
	if absf(horde - terrain) > _EPSILON:
		_failures.append("horde speed over rail is %.3fx, expected terrain %.3fx"
			% [horde, terrain])


## 3. End to end through A*: the player takes the longer railed detour because it
##    is cheaper; the horde takes the short way because to it the rail is nothing.
func _check_routing() -> void:
	var player := HexPathfinder.find_path(_map, _A, _b, _network, null, false, true)
	var horde := HexPathfinder.find_path(_map, _A, _b, _network, null, false, false)
	print("route A->B: player %s, horde %s" % [player, horde])

	if not player.has(_c):
		_failures.append("player route %s does not detour via the railed hex %s -- the fixture is vacuous, so the horde result below proves nothing"
			% [player, _c])
	if horde.has(_c):
		_failures.append("horde route %s detours via the railed hex %s -- hordes are still routing along infrastructure"
			% [horde, _c])
	var direct: Array[Vector2i] = [_A, _b]
	if horde != direct:
		_failures.append("horde route is %s, expected the direct %s" % [horde, direct])


## 4. The route hordes actually use. HordeFlowField, not find_path(), is what
##    HordeManager._replan() calls, and it costs its edges through the same
##    get_step_cost() -- so it needs its own check, not an inference from 3.
##
##    Also asserted: the field is IDENTICAL to one built with no logistics
##    network at all. That is the real property -- building a railway across a
##    horde's path must not move the horde.
func _check_flow_field() -> void:
	HordeFlowField.clear_cache()
	var with_rail := HordeFlowField.trace_path(_map, _network, _A, _b)
	HordeFlowField.clear_cache()
	var without_any := HordeFlowField.trace_path(_map, null, _A, _b)
	print("flow field A->B: with railway %s, with no network %s" % [with_rail, without_any])

	if with_rail.has(_c):
		_failures.append("horde flow field %s detours via the railed hex %s" % [with_rail, _c])
	if with_rail != without_any:
		_failures.append("horde flow field changed when a railway was built: %s vs %s"
			% [with_rail, without_any])


## 5. The regression guard. Bridges are passability, not speed: a horde denied
##    the speed bonus must still be able to cross water.
func _check_bridges_still_crossable() -> void:
	var blocked_before := HexPathfinder.is_water_crossing_blocked(_map, _network, _A, _water)
	if not blocked_before:
		_failures.append("water at %s is crossable with no bridge -- the fixture is not testing anything"
			% _water)

	_network.add_supply_line(GameEnums.SupplyLineType.BRIDGE, _A, _water, 0)
	var blocked_after := HexPathfinder.is_water_crossing_blocked(_map, _network, _A, _water)
	print("water crossing at %s: blocked %s without a bridge, blocked %s with one"
		% [_water, blocked_before, blocked_after])
	if blocked_after:
		_failures.append("a bridge does not open the crossing at %s" % _water)

	# The horde's own routing must reach across it, not merely the shared rule.
	HordeFlowField.clear_cache()
	var horde_route := HexPathfinder.find_path(_map, _A, _water, _network, null, false, false)
	if horde_route.is_empty():
		_failures.append("horde cannot route across a bridged crossing -- dropping the logistics network for hordes would do exactly this")

	# ...and it must cross at plain terrain speed, taking no bonus from the
	# bridge's own tier while doing so.
	var horde_speed := HexPathfinder.get_movement_speed_multiplier(_map, _network, _A, _water, false)
	var terrain := HexPathfinder.get_terrain_speed_multiplier(_map.get_cell(_A))
	if absf(horde_speed - terrain) > _EPSILON:
		_failures.append("horde crosses the bridge at %.3fx, expected terrain %.3fx"
			% [horde_speed, terrain])
