class_name HordeFlowField
extends RefCounted

## Sub-Hex Mechanical Layer Phase 2b (todo.md, [[sub-hex-mechanical-layer-epic]]
## memory) — "regional flow-field movement for hordes" half of the old
## Phase 2 bullet (Phase 2a already covered "hierarchical long-range
## routing" via SubHexPortalGraph).
##
## HexPathfinder.find_path() runs a fresh A* search per CALL — fine for a
## single unit column, but HordeManager's own doc comment already flags the
## real cost at horde-scale: "hundreds-to-thousands of Horde instances",
## each re-searching independently in _replan() every time its drift path
## empties, even when many of them are converging on the exact same target
## (an ATTRACTED horde swarm all pathing to the same noise source; several
## WANDERING hordes near each other picking overlapping drift targets).
##
## This class computes ONE shared Dijkstra integration field per distinct
## goal hex instead — cost-to-goal for every REACHABLE hex within
## REGION_RADIUS of that goal, built once and cached, then reused by every
## horde asking for a route to that same goal regardless of where each one
## currently stands. "Regional" (not whole-map): a wandering/attracted
## horde's target is always within DRIFT_TARGET_RADIUS(5)/
## ATTRACTION_AWARENESS_RADIUS(6) hexes of where it was picked from, so
## REGION_RADIUS(12) covers the real query range with margin, at a fraction
## of a full-map Dijkstra's cost.
##
## Reuses HexPathfinder.get_step_cost() for the same per-edge cost model the
## A* router uses, with ONE deliberate difference: it costs every edge with
## `uses_infrastructure = false`, so a horde's route is decided on biome alone
## and a road is worth exactly the ground it is built on (D6). A player's A*
## route over the same hexes will legitimately differ, and should.
##
## Cache staleness, an accepted trade-off, not a bug to chase: a field built
## before a marsh hex is drained by ReclamationManager won't reflect that change
## until its cache entry is
## evicted (MAX_CACHED_FIELDS FIFO) or the requesting horde's goal moves on.
## SubHexPortalGraph/SubHexTerrainQuery already accept the identical
## trade-off for the same reason — no consumer in this codebase has ever
## needed a route that's provably fresh to the current frame, only cheap
## and directionally correct (same call HexPathfinder.find_path()'s own
## doc comment already makes about its non-heap A* not being strictly
## optimal under logistics discounts).

const REGION_RADIUS: int = 12  ## Generous margin over the largest real caller radius (ATTRACTION_AWARENESS_RADIUS = 6) — see this file's own header doc comment.
const MAX_CACHED_FIELDS: int = 64  ## FIFO cap — goal hexes drift continuously (WANDERING re-picks, ATTRACTED tracks a moving noise source), so the key space is unbounded over a long session; this bounds memory while still capturing the real win (many hordes sharing one goal's field).

static var _cache: Dictionary = {}        # "<q>_<r>" goal key -> Dictionary(Vector2i -> Vector2i), the next-hop field
static var _cache_order: Array[String] = []  # FIFO eviction order, parallel to _cache's keys

## The immediate next hop from `from_hex` toward `goal`, or `from_hex`
## itself (a no-op sentinel, same convention HordeManager._pick_drift_target()/
## _pick_attraction_target() already use) if `from_hex` has no known route
## to `goal` within this field (goal unreachable, or outside REGION_RADIUS).
static func get_next_hex(hex_grid_map: HexGridMap, logistics_network: LogisticsNetwork, goal: Vector2i, from_hex: Vector2i) -> Vector2i:
	if from_hex == goal:
		return goal
	var field := _get_or_build_field(hex_grid_map, logistics_network, goal)
	return field.get(from_hex, from_hex)

## Full step-by-step route from `from_hex` to `goal` (EXCLUDING `from_hex`
## itself, same "path[0] is the next hex to step into" contract
## HexPathfinder.find_path() callers already unwrap by hand) built by
## walking this field's next-hop chain — replaces a per-horde
## HexPathfinder.find_path() call with a lookup against the shared cached
## field. Empty array if `from_hex == goal`, or no route exists within the
## field's own region (mirrors find_path()'s empty-array-on-unreachable
## contract; HordeManager's _replan() already handles an empty path
## gracefully — no valid target found this cycle, try again next replan).
static func trace_path(hex_grid_map: HexGridMap, logistics_network: LogisticsNetwork, from_hex: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if from_hex == goal:
		return []
	var path: Array[Vector2i] = []
	var current := from_hex
	var guard := REGION_RADIUS * 2  ## A real route within this field's own region can't need more hops than this; cheap insurance against ever spinning on a corrupt/cyclic field, same "bounded loop, not trusted to self-terminate" caution UnitOrderController._advance_patrol()'s own `guard` already applies.
	while current != goal and guard > 0:
		var next_hex := get_next_hex(hex_grid_map, logistics_network, goal, current)
		if next_hex == current:
			return []  ## No route to goal from here within this field's region.
		path.append(next_hex)
		current = next_hex
		guard -= 1
	return path if current == goal else []

static func _get_or_build_field(hex_grid_map: HexGridMap, logistics_network: LogisticsNetwork, goal: Vector2i) -> Dictionary:
	var key := "%d_%d" % [goal.x, goal.y]
	if _cache.has(key):
		return _cache[key]
	var field := _build_field(hex_grid_map, logistics_network, goal)
	if _cache.size() >= MAX_CACHED_FIELDS:
		var oldest: String = _cache_order.pop_front()
		_cache.erase(oldest)
	_cache[key] = field
	_cache_order.append(key)
	return field

## Dijkstra rooted at `goal`, propagated OUTWARD along reversed edges: when
## relaxing from an already-finalized `current` out to `neighbor`, the step
## costed is the forward step neighbor -> current (HexPathfinder.get_step_cost()
## with `to_cell` = current's cell) — the real cost of walking FROM neighbor
## INTO current, which is what actually makes cost[neighbor] a true
## "cost from neighbor to goal" value. Bounded to HexCoord.distance(goal, *)
## <= REGION_RADIUS so this never grows into a full-map search (see this
## file's own header doc comment for why that's a safe bound for every real
## caller). Same "cheap enough at this scale" plain-Dictionary frontier
## HexPathfinder.find_path()'s own A* already uses, no binary heap — a
## region of at most ~470 hexes (radius 12) doesn't need one.
static func _build_field(hex_grid_map: HexGridMap, logistics_network: LogisticsNetwork, goal: Vector2i) -> Dictionary:
	var next: Dictionary = {}  # Vector2i -> Vector2i
	if not hex_grid_map or not hex_grid_map.has_cell(goal):
		return next
	var goal_cell := hex_grid_map.get_cell(goal)
	if not goal_cell.is_passable():
		return next

	var cost: Dictionary = {goal: 0.0}  # Vector2i -> float
	var frontier: Dictionary = {goal: true}
	while not frontier.is_empty():
		var current := _lowest_cost(frontier, cost)
		frontier.erase(current)
		for neighbor in HexCoord.neighbors(current):
			if HexCoord.distance(goal, neighbor) > REGION_RADIUS:
				continue
			var neighbor_cell := hex_grid_map.get_cell(neighbor)
			if not neighbor_cell or not neighbor_cell.is_passable():
				continue
			if HexPathfinder.is_water_crossing_blocked(hex_grid_map, logistics_network, current, neighbor):
				continue
			if HexPathfinder.is_boundary_impassable(hex_grid_map, current, neighbor):
				continue
			## uses_infrastructure = false, hardcoded rather than a parameter: this
			## class exists only to move hordes, and hordes never use roads (D6).
			## Making it a parameter would also make the field cache above wrong,
			## since its key is the goal hex alone — two callers wanting different
			## answers for one goal would silently share the first one's field.
			##
			## `logistics_network` is still passed to is_water_crossing_blocked()
			## above, and must be: that is bridges, not speed.
			var step_cost := HexPathfinder.get_step_cost(neighbor, current, hex_grid_map.get_cell(current), logistics_network, false)
			var candidate: float = cost[current] + step_cost
			if candidate < cost.get(neighbor, INF):
				cost[neighbor] = candidate
				next[neighbor] = current
				frontier[neighbor] = true
	return next

static func _lowest_cost(frontier: Dictionary, cost: Dictionary) -> Vector2i:
	var best: Vector2i
	var best_cost := INF
	var first := true
	for coord in frontier:
		var c: float = cost.get(coord, INF)
		if first or c < best_cost:
			best = coord
			best_cost = c
			first = false
	return best

## Clears the cache — tests/tooling only, same rationale
## SubHexTerrainQuery.clear_cache()/SubHexPortalGraph.clear_cache() already
## document.
static func clear_cache() -> void:
	_cache.clear()
	_cache_order.clear()
