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
##
## No WATERWAY entry — Bridge-mandatory-crossing (todo.md, 2026-08-16
## follow-up) removed the old flat 1.4x "fording" penalty this table used
## to carry for it. A WATERWAY-touching edge is now either excluded from
## the graph entirely (is_water_crossing_blocked() below, unbridged) or
## overridden by a real Bridge's own SupplyLineCatalog speed bonus (bridged
## — see get_step_cost()'s own override logic) — no live code path ever
## consults a WATERWAY entry here anymore, so it isn't kept as a stale
## fallback; missing keys already default to the neutral 1.0 baseline.
const _BIOME_COST_MULTIPLIER: Dictionary = {
	GameEnums.BiomeType.HIGHLAND: 1.6,  ## Elevated terrain — Pennine/Chiltern/Cotswold chokepoints.
	GameEnums.BiomeType.WETLAND: 1.8,   ## Boggy going even where it's not outright impassable MARSH/PEAT_BOG.
}

## True if the edge from `from` to `to` crosses WATERWAY (either hex is
## WATERWAY) and no unsevered Bridge segment connects them —
## design_doc.md: "WATERWAY - IMPASSABLE for all ground units & zombies.
## Traversable ONLY via Bridges." Checked per-EDGE via
## LogisticsNetwork.is_bridge_between(), not by making HexCell.is_passable()
## itself reject WATERWAY — mirrors how WallManager's own blocking check is
## an edge-level exclusion, not a hex-level one: a horde/unit can walk
## right up to a riverbank hex from dry land, just can't cross into or
## through the water without a bridge on that SPECIFIC edge (a hex where a
## river bends still needs its own bridge on each edge it's entered/exited
## through, not one bridge anywhere on its boundary).
##
## Shared by find_path() below, HordeFlowField._build_field(), and
## HordeManager._replan_cheap() — three independent neighbor-expansion
## loops that each need the identical exclusion, same "shared source of
## truth" reasoning get_step_cost() already established for
## find_path()/HordeFlowField.
static func is_water_crossing_blocked(hex_grid_map: HexGridMap, logistics_network: LogisticsNetwork, from: Vector2i, to: Vector2i) -> bool:
	var from_cell := hex_grid_map.get_cell(from) if hex_grid_map else null
	var to_cell := hex_grid_map.get_cell(to) if hex_grid_map else null
	var crosses_water := (from_cell and from_cell.biome_type == GameEnums.BiomeType.WATERWAY) or (to_cell and to_cell.biome_type == GameEnums.BiomeType.WATERWAY)
	if not crosses_water:
		return false
	return not (logistics_network and logistics_network.is_bridge_between(from, to))

## True if the real sub-hex terrain along the boundary shared by `from` and
## `to` is impassable end to end, so no mover can cross between them however
## passable the two hexes read at macro level.
##
## The macro graph knows one passability verdict per hex, aggregated from a
## 5x5 sample at generation (RealTerrainSampler.majority_biome()). That misses
## the case the sub-hex layer was built for: two ordinary hexes separated by a
## marsh seam, a peat strip or a coastal inlet lying exactly along their shared
## edge. Both hexes vote passable, the edge between them is not, and before
## this the route crossed anyway — SubHexPortalGraph found the boundary
## impassable, returned no portals, and portal_offset_for_step() quietly fell
## back to the hex centre rather than telling anyone the crossing did not
## exist. That fallback still stands for the case it was written for (a mover
## needing SOME aim point); this is the separate question of whether the edge
## belongs in the graph at all, asked before a route is ever built on it.
##
## Shared by find_path() below, HordeFlowField._build_field(), and
## HordeManager._replan_cheap() — the same three neighbor-expansion loops
## is_water_crossing_blocked() above already had to cover, and for the same
## reason: _replan_cheap() goes through neither real search, so a rule wired
## only into the two searches would silently keep letting far hordes step
## across boundaries nothing can cross.
##
## Asks SubHexPortalGraph.has_any_crossing(), NOT find_portals().is_empty() —
## the two answer the same question but the second builds the whole portal
## list to do it. Measured (scripts/test/bench_portal_blocking.gd): the
## find_portals() form cost 2.18 ms per cold edge and stranded ~178
## SubHexTerrainQuery cache entries per edge, extrapolating to ~25 s and ~2M
## entries over the corridor, paid lazily mid-session as hordes route into new
## ground. has_any_crossing() stops at the first passable sample instead.
##
## Checked LAST in each expansion loop, after the cheap per-hex and per-edge
## rejections, so an edge already excluded never pays for it at all.
static func is_boundary_impassable(hex_grid_map: HexGridMap, from: Vector2i, to: Vector2i) -> bool:
	if not hex_grid_map:
		return false
	return not SubHexPortalGraph.has_any_crossing(hex_grid_map, from, to)

## A* search from `start` to `goal` over `hex_grid_map`'s cells, weighted by
## HexCell.is_passable() (impassable hexes — marsh/peat bog — are never
## entered, not even as a detour), excluded across any WATERWAY-touching
## edge with no Bridge on it (is_water_crossing_blocked() above — same
## treatment as an impassable hex, a route genuinely goes AROUND unbridged
## water or fails if there's no way around), and discounted/overridden
## across `logistics_network` segments when one is supplied. Returns an
## Array[Vector2i] path INCLUDING both `start` and `goal`, or an empty
## array if no path exists (goal unreachable, either endpoint off-map,
## either endpoint itself impassable, or every route to it crosses
## unbridged water). `start == goal` returns a single-element path rather
## than searching.
##
## `wall_manager` — optional, same "unset gracefully skips it" convention
## as `logistics_network`. When supplied, any edge crossed by an
## un-breached WallSegment (WallManager.get_blocking_segment(), the SAME
## check HordeManager peeks per hex-crossing before deciding to siege) is
## excluded from the graph entirely, same treatment as an impassable hex —
## a unit route genuinely goes AROUND a wall. HordeManager's siege-on-
## contact behavior is unrelated and unchanged — hordes still want to
## smash through, units want to avoid.
##
## `gates_are_passable` routes THROUGH Gate segments instead of around them
## — true for the player's own units, false (the default) for a horde. See
## WallManager.get_blocking_segment()'s own `ignore_gates` doc comment.
static func find_path(hex_grid_map: HexGridMap, start: Vector2i, goal: Vector2i, logistics_network: LogisticsNetwork = null, wall_manager: WallManager = null, gates_are_passable: bool = false, uses_infrastructure: bool = true) -> Array[Vector2i]:
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
			if is_water_crossing_blocked(hex_grid_map, logistics_network, current, neighbor):
				continue
			if wall_manager and wall_manager.get_blocking_segment(current, neighbor, HexCoord.axial_to_world(current), HexCoord.axial_to_world(neighbor), gates_are_passable):
				continue
			if is_boundary_impassable(hex_grid_map, current, neighbor):
				continue
			var tentative_g: float = g_score[current] + get_step_cost(current, neighbor, cell, logistics_network, uses_infrastructure)
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
##
## `uses_infrastructure` false makes this cost the edge as if no road, rail or
## canal were there at all — for zombies, who do not use them (D6, verbatim:
## "zombies shouldn't travel faster over roads or rails or canals because they
## can't drive or take the train lol").
##
## Passing false is NOT the same as passing a null `logistics_network`, and the
## two must not be conflated: the network is also what
## is_water_crossing_blocked() consults for BRIDGES, and a bridge is physical
## ground a zombie walks over like any other. Dropping the network to remove the
## speed bonus would silently make every river uncrossable for hordes.
static func get_step_cost(from: Vector2i, to: Vector2i, to_cell: HexCell, logistics_network: LogisticsNetwork, uses_infrastructure: bool = true) -> float:
	if logistics_network and uses_infrastructure:
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
##
## `uses_infrastructure` false returns the terrain multiplier for this hex and
## nothing else, however good the road on it is (D6). This is the site that
## decides how fast something actually MOVES, as against get_step_cost() which
## only decides which way it goes — a horde denied the routing discount but not
## this one would still sprint down every road it happened to cross.
static func get_movement_speed_multiplier(hex_grid_map: HexGridMap, logistics_network: LogisticsNetwork, from_coord: Vector2i, to_coord: Vector2i, uses_infrastructure: bool = true) -> float:
	if logistics_network and uses_infrastructure:
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
