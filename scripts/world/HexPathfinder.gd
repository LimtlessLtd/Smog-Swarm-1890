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
## Tactical-scale local pathfinding within a single hydrated hex (Phase 2.5)
## is deliberately NOT here — the design doc calls that out as a separate,
## much shorter-range problem (scattered props/buildings within one hex)
## that doesn't need to share this algorithm.
##
## No consumer exists yet (Phase 5.2's HordeManager and Phase 5.4/5.6's unit
## movement/orders don't exist yet), so this can't be exercised in-game
## until then — same "built ahead of its first caller" position TickManager
## was in before Phase 5.1's TimeCycleManager arrived to extend it.

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
	# hex, f_score is g_score plus the hex-distance heuristic to `goal` (an
	# admissible heuristic here — HexCoord.distance is the true minimum step
	# count ignoring cost multipliers, which are all <= BASE_HEX_COST, so it
	# never overestimates). A linear scan for the lowest f_score each
	# iteration (_lowest_f_score) rather than a binary heap — no consumer
	# exists yet to have a real performance profile against, and every other
	# recompute in this codebase (LogisticsNetwork, FogOfWarManager) makes
	# the same "cheap enough at this scale" call rather than optimizing
	# ahead of an actual need.
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
			var tentative_g: float = g_score[current] + _step_cost(current, neighbor, logistics_network)
			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + float(HexCoord.distance(neighbor, goal))
				open_set[neighbor] = true

	return []  # Frontier exhausted without reaching goal — unreachable (e.g. sealed off by impassable terrain).

static func _step_cost(from: Vector2i, to: Vector2i, logistics_network: LogisticsNetwork) -> float:
	if logistics_network:
		var segment := logistics_network.get_segment_between(from, to)
		if segment and not segment.is_severed:
			return BASE_HEX_COST * LOGISTICS_EDGE_COST_MULTIPLIER
	return BASE_HEX_COST

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
