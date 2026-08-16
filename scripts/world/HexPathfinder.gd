class_name HexPathfinder
extends RefCounted

## Strategic-scale hex pathfinding — a wandering horde and a unit column
## both route several hexes across the map through the same graph. Pure,
## stateless graph-search utility code, same "pure static utility, no
## state" shape as HexCoord itself, just one level up (a path across many
## hexes rather than math about a single one).
##
## A HexGridMap (terrain/passability) and, optionally, a LogisticsNetwork
## (cheaper road/rail/canal edges) are passed in per call rather than held
## — this owns neither, only reads them, the same relationship
## LogisticsNetwork itself has to HexGridMap/BuildingManager.
##
## Tactical-scale LOCAL movement within a single hydrated hex (steering
## around scattered props/buildings) deliberately does NOT share this A*
## graph search — that's MovementStepper.gd (continuous, per-frame,
## geometry-based), a much shorter-range problem that doesn't need a second
## hex-graph search. This class still supplies the STRATEGIC route (which
## hexes to cross) that MovementStepper walks continuously between, and —
## via get_movement_speed_multiplier() below — the same biome/logistics
## numbers that shape that route also shape how fast continuous movement
## crosses each hex, one shared source instead of two independent ones.
##
## Consumers: HordeManager and UnitOrderController both route several hexes
## across the map through this same graph, then hand the resulting hex
## sequence to MovementStepper for the actual continuous walk between them.

const BASE_HEX_COST: float = 1.0  ## Base traversal cost for an ordinary hex-to-hex step — a balancing number, not an architecture one.

## Each biome gets its own movement-cost multiplier instead of every
## passable hex costing the flat BASE_HEX_COST — Highland/Wetland slower
## than Farmland/Moorland. A balancing pass, not an architecture decision;
## a biome with no entry here costs the unmodified baseline. Applied to the
## DESTINATION hex of a step (moving INTO dense terrain is what's slow, not
## leaving it). An edge with a real, unsevered SupplyLineSegment on it does
## NOT stack this multiplier with the segment's own speed bonus — Infrastructure
## rework (todo.md, 2026-08-16): design_doc.md's Infrastructure Velocity
## Modifiers rule is explicit ("completely ignoring underlying biome
## movement speed reductions... while units are actively traversing
## directly on the infrastructure tile itself"), so get_step_cost()/
## get_movement_speed_multiplier() below OVERRIDE this table entirely on a
## segment's edge rather than multiplying against it — a road through a
## highland pass costs exactly what SupplyLineCatalog says that road tier
## costs, full stop, not "road discount times highland penalty" the way an
## un-roaded highland hex still does.
##
## Shapes both scales: the Strategic A* route weighs a step by this
## multiplier as a path-preference cost, and get_terrain_speed_multiplier()
## below inverts the SAME table into a continuous movement speed for
## whichever hex an entity is currently crossing (MovementStepper.gd).
const _BIOME_COST_MULTIPLIER: Dictionary = {
	GameEnums.BiomeType.HIGHLAND: 1.6,  ## Elevated terrain — Pennine/Chiltern/Cotswold chokepoints.
	GameEnums.BiomeType.WETLAND: 1.8,   ## Boggy going even where it's not outright impassable MARSH/PEAT_BOG.
	GameEnums.BiomeType.WATERWAY: 1.4,  ## Fording a river/canal hex rather than bridging it.
}

## A* search from `start` to `goal` over `hex_grid_map`'s cells, weighted by
## HexCell.is_passable() (impassable hexes — marsh/peat bog — are never
## entered, not even as a detour) and discounted across
## `logistics_network` segments when one is supplied. Returns an
## Array[Vector2i] path INCLUDING both `start` and `goal`, or an empty
## array if no path exists (goal unreachable, either endpoint off-map, or
## either endpoint itself impassable). `start == goal` returns a single-
## element path rather than searching.
##
## `wall_manager` — optional, same "unset gracefully skips it" convention
## as `logistics_network`. When supplied, any edge crossed by an
## un-breached WallSegment (WallManager.get_blocking_segment(), the SAME
## check HordeManager peeks per hex-crossing before deciding to siege) is
## excluded from the graph entirely, same treatment as an impassable hex —
## a unit route genuinely goes AROUND a wall. HordeManager's siege-on-
## contact behavior is unrelated and unchanged — hordes still want to
## smash through, units want to avoid.
static func find_path(hex_grid_map: HexGridMap, start: Vector2i, goal: Vector2i, logistics_network: LogisticsNetwork = null, wall_manager: WallManager = null) -> Array[Vector2i]:
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
	# NOT strictly admissible once a SupplyLineCatalog speed multiplier
	# (well above 1.0, i.e. a step cost well below BASE_HEX_COST) or the
	# per-biome multipliers (some below 1.0 too, e.g. any future
	# fast-terrain entry) are in play — a long enough
	# discounted route could in principle cost less than the plain
	# hex-count heuristic assumes, which can occasionally steer A* away
	# from the GLOBAL optimum toward "a" reachable, still-perfectly-valid
	# path instead. Accepted, not fixed: same "cheap enough at this scale,
	# no consumer has ever needed provably-optimal routing" call every
	# other recompute in this codebase (LogisticsNetwork, FogOfWarManager)
	# makes over a real performance/precision profile, rather than a
	# binary heap or a corrected heuristic ahead of an actual need.
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
			if wall_manager and wall_manager.get_blocking_segment(current, neighbor, HexCoord.axial_to_world(current), HexCoord.axial_to_world(neighbor)):
				continue
			var tentative_g: float = g_score[current] + get_step_cost(current, neighbor, cell, logistics_network)
			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + float(HexCoord.distance(neighbor, goal))
				open_set[neighbor] = true

	return []  # Frontier exhausted without reaching goal — unreachable (e.g. sealed off by impassable terrain).

## Public (not `_`-prefixed) — HordeFlowField reuses this exact edge-cost
## model to build its Dijkstra integration field, so a flow-field route and
## an A* route never disagree about what a given hex-to-hex step actually
## costs. `from` only matters for the logistics-segment lookup (a segment
## between two hexes isn't directional); the biome/base cost is entirely a
## function of `to_cell`.
static func get_step_cost(from: Vector2i, to: Vector2i, to_cell: HexCell, logistics_network: LogisticsNetwork) -> float:
	if logistics_network:
		var segment := logistics_network.get_segment_between(from, to)
		if segment and not segment.is_severed:
			# Overrides, not stacks with, the biome multiplier below — see
			# _BIOME_COST_MULTIPLIER's own doc comment.
			return BASE_HEX_COST / SupplyLineCatalog.get_speed_multiplier(segment.line_type, segment.tier)
	return BASE_HEX_COST * float(_BIOME_COST_MULTIPLIER.get(to_cell.biome_type, 1.0))

## The exact inverse of _BIOME_COST_MULTIPLIER above, reusing the SAME
## table rather than a second one — terrain that costs more to path
## THROUGH is also slower to actually walk ACROSS once chosen.
static func get_terrain_speed_multiplier(cell: HexCell) -> float:
	if not cell:
		return 1.0
	return 1.0 / float(_BIOME_COST_MULTIPLIER.get(cell.biome_type, 1.0))

## Real continuous-movement speed multiplier for crossing the CURRENT hex
## (`from_coord`) while heading toward `to_coord`. A real, unsevered
## SupplyLineSegment on this edge returns its own tier's
## SupplyLineCatalog.get_speed_multiplier() outright — OVERRIDING the
## terrain multiplier entirely, not stacking with it (see
## _BIOME_COST_MULTIPLIER's own doc comment for why) — otherwise falls back
## to get_terrain_speed_multiplier() for whichever hex the entity is
## currently standing in. Replaces the old two-call stack
## (get_terrain_speed_multiplier() * get_logistics_speed_multiplier(), the
## latter a flat 2x discount for ANY line_type/tier) both
## UnitOrderController and HordeManager used to apply as two separate
## multiplications — this is the one call that decides between them instead.
static func get_movement_speed_multiplier(hex_grid_map: HexGridMap, logistics_network: LogisticsNetwork, from_coord: Vector2i, to_coord: Vector2i) -> float:
	if logistics_network:
		var segment := logistics_network.get_segment_between(from_coord, to_coord)
		if segment and not segment.is_severed:
			return SupplyLineCatalog.get_speed_multiplier(segment.line_type, segment.tier)
	return get_terrain_speed_multiplier(hex_grid_map.get_cell(from_coord) if hex_grid_map else null)

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
