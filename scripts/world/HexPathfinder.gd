class_name HexPathfinder
extends RefCounted

## Design doc Phase 5.5: strategic-scale hex pathfinding foundation —
## "documented once here rather than solved twice", since both a wandering
## horde (Phase 5.2/5.10) and a unit column (Phase 5.4/5.6) will eventually
## route several hexes across the map through the same graph. Neither system
## exists yet; this is pure, stateless graph-search utility code with no
## dependency on either — same "pure static utility, no state" shape as
## HexCoord itself, just one level up (a path across many hexes rather than
## math about a single one).
##
## A HexGridMap (terrain/passability) and, optionally, a LogisticsNetwork
## (cheaper road/rail/canal edges) are passed in per call rather than held —
## this owns neither, only reads them, the same relationship LogisticsNetwork
## itself has to HexGridMap/BuildingManager.
##
## Tactical-scale LOCAL movement within a single hydrated hex (steering
## around scattered props/buildings, user request) deliberately does NOT
## share this A* graph search — that's `MovementStepper.gd` (continuous,
## per-frame, geometry-based), a much shorter-range problem that doesn't
## need a second hex-graph search. This class still supplies the STRATEGIC
## route (which hexes to cross) that `MovementStepper` walks continuously
## between, and — via `get_terrain_speed_multiplier()`/
## `get_logistics_speed_multiplier()` below — the same biome/logistics
## numbers that shape that route also shape how fast continuous movement
## crosses each hex, one shared table instead of two.
##
## Consumers: `HordeManager` (Phase 5.2/5.10) and `UnitOrderController`
## (Phase 5.4/5.6) both route several hexes across the map through this
## same graph, then hand the resulting hex sequence to `MovementStepper`
## for the actual continuous walk between them.

## Base traversal cost for an ordinary hex-to-hex step — a balancing number,
## not an architecture one, same framing as every other placeholder constant
## table in this project.
const BASE_HEX_COST: float = 1.0

## Cost multiplier applied to a step when an unsevered supply line segment
## (Phase 2.3 — any of ROAD/RAILWAY/CANAL) connects the two hexes: "existing
## roads/rail/canal (LogisticsNetwork segments as cheaper edges)" per the
## design doc. A severed segment doesn't count — a horde or column can't
## lean on a supply line the player's own network no longer considers
## usable.
const LOGISTICS_EDGE_COST_MULTIPLIER: float = 0.5

## Design doc Phase 2.12.1: each biome gets its own movement-cost multiplier
## instead of every passable hex costing the flat BASE_HEX_COST — "Highland/
## Wetland slower than Farmland/Moorland" (design doc's own worked example).
## A balancing pass, not an architecture decision, same framing as
## LOGISTICS_EDGE_COST_MULTIPLIER above; a biome with no entry here costs the
## unmodified baseline. Applied to the DESTINATION hex of a step (moving
## INTO dense terrain is what's slow, not leaving it) and stacks
## multiplicatively with the logistics discount — a road through a highland
## pass is still cheaper than the bare hillside beside it, just not as cheap
## as a road through open farmland.
##
## Shapes both scales now: the Strategic A* route above weighs a step by
## this multiplier as a path-preference cost, and `get_terrain_speed_multiplier()`
## below inverts the SAME table into a continuous movement speed for
## whichever hex an entity is currently crossing (`MovementStepper.gd`) —
## the design doc's own "applies at both scales" aspiration, closed now
## that Tactical local movement exists to apply it to.
const _BIOME_COST_MULTIPLIER: Dictionary = {
	GameEnums.BiomeType.HIGHLAND: 1.6,  ## Elevated terrain — Pennine/Chiltern/Cotswold chokepoints.
	GameEnums.BiomeType.WETLAND: 1.8,   ## Boggy going even where it's not outright impassable MARSH/PEAT_BOG.
	GameEnums.BiomeType.WATERWAY: 1.4,  ## Fording a river/canal hex rather than bridging it.
}

## A* search from `start` to `goal` over `hex_grid_map`'s cells, weighted by
## HexCell.is_passable() (impassable hexes — marsh/peat bog, see Phase 4.2's
## reclamation — are never entered, not even as a detour) and discounted
## across `logistics_network` segments when one is supplied. Returns an
## Array[Vector2i] path INCLUDING both `start` and `goal`, or an empty array
## if no path exists (goal unreachable, either endpoint off-map, or either
## endpoint itself impassable). `start == goal` returns a single-element
## path rather than searching.
static func find_path(hex_grid_map: HexGridMap, start: Vector2i, goal: Vector2i, logistics_network: LogisticsNetwork = null) -> Array[Vector2i]:
	if not hex_grid_map or not hex_grid_map.has_cell(start) or not hex_grid_map.has_cell(goal):
		return []
	var start_cell := hex_grid_map.get_cell(start)
	var goal_cell := hex_grid_map.get_cell(goal)
	if not start_cell.is_passable() or not goal_cell.is_passable():
		return []
	if start == goal:
		return [start]

	# Standard A*: open_set is a cheap Vector2i -> true membership map (the
	# frontier), g_score is the cheapest known cost from `start` to a given
	# hex, f_score is g_score plus the hex-distance heuristic to `goal`.
	# NOT strictly admissible once LOGISTICS_EDGE_COST_MULTIPLIER (0.5, below
	# BASE_HEX_COST) or Phase 2.12.1's per-biome multipliers (some below 1.0
	# too, e.g. any future fast-terrain entry) are in play — a long enough
	# discounted route could in principle cost less than the plain hex-count
	# heuristic assumes, which can occasionally steer A* away from the
	# GLOBAL optimum toward "a" reachable, still-perfectly-valid path
	# instead. Accepted, not fixed: same "cheap enough at this scale, no
	# consumer has ever needed provably-optimal routing" call every other
	# recompute in this codebase (LogisticsNetwork, FogOfWarManager) already
	# makes over a real performance/precision profile, rather than a binary
	# heap or a corrected heuristic ahead of an actual need.
	var open_set: Dictionary = {start: true}
	var came_from: Dictionary = {}          # Vector2i -> Vector2i
	var g_score: Dictionary = {start: 0.0}  # Vector2i -> float
	var f_score: Dictionary = {start: float(HexCoord.distance(start, goal))}  # Vector2i -> float

	while not open_set.is_empty():
		var current := _lowest_f_score(open_set, f_score)
		if current == goal:
			return _reconstruct_path(came_from, current)
		open_set.erase(current)

		for neighbor in HexCoord.neighbors(current):
			var cell := hex_grid_map.get_cell(neighbor)
			if not cell or not cell.is_passable():
				continue
			var tentative_g: float = g_score[current] + _step_cost(current, neighbor, cell, logistics_network)
			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + float(HexCoord.distance(neighbor, goal))
				open_set[neighbor] = true

	return []  # Frontier exhausted without reaching goal — unreachable (e.g. sealed off by impassable terrain).

static func _step_cost(from: Vector2i, to: Vector2i, to_cell: HexCell, logistics_network: LogisticsNetwork) -> float:
	var cost := BASE_HEX_COST * float(_BIOME_COST_MULTIPLIER.get(to_cell.biome_type, 1.0))
	if logistics_network:
		var segment := logistics_network.get_segment_between(from, to)
		if segment and not segment.is_severed:
			return cost * LOGISTICS_EDGE_COST_MULTIPLIER
	return cost

## Design doc, user request (continuous local movement, replacing the old
## hex-stepping): the exact inverse of `_BIOME_COST_MULTIPLIER` above,
## reusing the SAME table rather than a second one — terrain that costs
## more to path THROUGH is also slower to actually walk ACROSS once chosen.
## Consumed by `MovementStepper.advance_toward_hex()` to scale continuous
## travel speed by whichever hex the entity is currently crossing. Closes
## Phase 2.12.1's own flagged gap ("Tactical-scale local movement costs...
## blocked on Phase 5.5's unbuilt in-hex pathfinding") now that continuous
## local movement exists to apply it to.
static func get_terrain_speed_multiplier(cell: HexCell) -> float:
	if not cell:
		return 1.0
	return 1.0 / float(_BIOME_COST_MULTIPLIER.get(cell.biome_type, 1.0))

## Same inversion for the logistics discount — a road/rail/canal edge is
## FASTER to walk, not just cheaper to path through. `to` isn't required to
## already be the entity's next hex specifically; any adjacent pair works,
## same as `LogisticsNetwork.get_segment_between()` itself.
static func get_logistics_speed_multiplier(logistics_network: LogisticsNetwork, from: Vector2i, to: Vector2i) -> float:
	if not logistics_network:
		return 1.0
	var segment := logistics_network.get_segment_between(from, to)
	if segment and not segment.is_severed:
		return 1.0 / LOGISTICS_EDGE_COST_MULTIPLIER
	return 1.0

static func _lowest_f_score(open_set: Dictionary, f_score: Dictionary) -> Vector2i:
	var best: Vector2i
	var best_score := INF
	var first := true
	for coord in open_set:
		var score: float = f_score.get(coord, INF)
		if first or score < best_score:
			best = coord
			best_score = score
			first = false
	return best

static func _reconstruct_path(came_from: Dictionary, end: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [end]
	var current := end
	while came_from.has(current):
		current = came_from[current]
		path.append(current)
	path.reverse()
	return path
