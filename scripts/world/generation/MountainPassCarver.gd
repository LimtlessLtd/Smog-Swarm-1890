class_name MountainPassCarver
extends RefCounted

## Guarantees that making Level 4 MOUNTAIN impassable (design_doc.md §5)
## never seals off ground that was walkable without it, by lowering the
## lowest saddle of a blocking ridge to a pass.
##
## Measured before this existed (scripts/test/verify_elevation.gd): the
## mountain rule claims ~7.6% of land hexes and, as a side effect, left 28
## perfectly ordinary walkable hexes with no route to them at all — small
## valleys ringed by summits. That is invisible on the map and reads as
## broken pathfinding rather than as terrain, since nothing about a green
## valley says "you can see this but can never walk here".
##
## A pass is a real feature of every mountain range, so the fix is terrain,
## not an exception in the rules: the ridge hex with the LOWEST elevation
## along the cheapest crossing is dropped to just under the mountain
## threshold. It stays Highland — slow going, still a chokepoint worth
## defending, and still visibly a mountain region in the relief overlay —
## it simply is not a wall.
##
## Runs as a generation pass over HexMapGenerator's cells, mutating
## HexCell.elevation itself rather than carrying a separate "is a pass"
## flag. That keeps ElevationLevels the single authority on what a given
## elevation means: nothing downstream needs to learn about passes, because
## after this runs there is nothing special left to know.
##
## Deterministic: components are walked in sorted coordinate order and ties
## in the search are broken by elevation then coordinate, so the same map
## data always produces the same passes.

## What a carved hex's elevation becomes: the highest value that is still
## Level 3 Highland. Just under the threshold rather than well under it —
## the point is to make one hex passable, not to flatten a mountain.
static func pass_elevation() -> float:
	return ElevationLevels.mountain_threshold_elevation() - 0.001


## Lowers ridge hexes until every hex that was walkable ignoring elevation
## can still be reached from every other one in its own landmass. Returns the
## number of hexes carved, for the verifier and for a caller that wants to
## log it.
static func carve(cells: Dictionary) -> int:
	var carved := 0
	for component in _baseline_components(cells):
		carved += _connect_component(cells, component)
	return carved


## Connected components of "walkable ignoring elevation" — i.e. the real
## landmasses. Great Britain and Ireland are separate components with no land
## bridge between them, and nothing here should ever try to build one, which
## is why connectivity is restored WITHIN a component rather than globally.
static func _baseline_components(cells: Dictionary) -> Array:
	var seen: Dictionary = {}
	var components: Array = []
	var coords: Array = cells.keys()
	coords.sort()
	for coord: Vector2i in coords:
		if seen.has(coord) or not _walkable_ignoring_elevation(cells.get(coord)):
			continue
		var component: Dictionary = {}
		var frontier: Array[Vector2i] = [coord]
		seen[coord] = true
		component[coord] = true
		while not frontier.is_empty():
			var current: Vector2i = frontier.pop_back()
			for neighbor in HexCoord.neighbors(current):
				if seen.has(neighbor) or not _walkable_ignoring_elevation(cells.get(neighbor)):
					continue
				seen[neighbor] = true
				component[neighbor] = true
				frontier.append(neighbor)
		components.append(component)
	return components


## Splits one landmass into the pieces the mountain rule leaves behind, then
## joins every piece to the largest one. The largest is chosen as the trunk
## so the carving happens at the edges of the map's small pockets rather than
## through its main body.
static func _connect_component(cells: Dictionary, component: Dictionary) -> int:
	var pieces := _walkable_pieces(cells, component)
	if pieces.size() <= 1:
		return 0
	pieces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.size() > b.size())
	var trunk: Dictionary = pieces[0]
	var carved := 0
	for i in range(1, pieces.size()):
		var route := _cheapest_crossing(cells, component, pieces[i], trunk)
		if route.is_empty():
			continue  ## Nothing but non-mountain blockage between them — not this pass's problem.
		for coord: Vector2i in route:
			var cell: HexCell = cells[coord]
			cell.elevation = minf(cell.elevation, pass_elevation())
			carved += 1
		# The newly joined piece and its pass are part of the trunk now, so a
		# third piece can legitimately connect through them instead of
		# carving a second, parallel route to the same place.
		for coord: Vector2i in pieces[i]:
			trunk[coord] = true
		for coord: Vector2i in route:
			trunk[coord] = true
	return carved


## Connected pieces of `component` under the REAL passability rule.
static func _walkable_pieces(cells: Dictionary, component: Dictionary) -> Array:
	var seen: Dictionary = {}
	var pieces: Array = []
	var coords: Array = component.keys()
	coords.sort()
	for coord: Vector2i in coords:
		var cell: HexCell = cells[coord]
		if seen.has(coord) or not cell.is_passable():
			continue
		var piece: Dictionary = {}
		var frontier: Array[Vector2i] = [coord]
		seen[coord] = true
		piece[coord] = true
		while not frontier.is_empty():
			var current: Vector2i = frontier.pop_back()
			for neighbor in HexCoord.neighbors(current):
				if seen.has(neighbor) or not component.has(neighbor):
					continue
				var other: HexCell = cells[neighbor]
				if not other.is_passable():
					continue
				seen[neighbor] = true
				piece[neighbor] = true
				frontier.append(neighbor)
		pieces.append(piece)
	return pieces


## The run of mountain hexes to lower, as the cheapest crossing from `from_piece`
## to `to_piece`. Returns [] if they are not separated by mountain at all.
##
## The search only ever walks MOUNTAIN hexes. Leaving a piece requires
## crossing one — any other walkable hex reachable without crossing mountain
## would already be part of the same piece by construction — so the first
## walkable hex the frontier touches outside the source is the far side, and
## everything between is exactly the ridge to cut. That collapses what would
## otherwise be a whole-landmass Dijkstra into a search over a few hundred
## summit hexes.
##
## Cost is the hex's own elevation, so of two crossings the one over the
## lower saddle wins, and a two-hex crossing at 620 m is preferred to a
## one-hex crossing at a 900 m summit — which is what a real pass looks like.
static func _cheapest_crossing(cells: Dictionary, component: Dictionary, from_piece: Dictionary, to_piece: Dictionary) -> Array:
	var cost: Dictionary = {}       ## Vector2i -> float, cheapest known cost to enter this mountain hex.
	var came_from: Dictionary = {}  ## Vector2i -> Vector2i, previous mountain hex (absent for a first step).
	var open: Dictionary = {}       ## Vector2i -> true.
	var sources: Array = from_piece.keys()
	sources.sort()
	for coord: Vector2i in sources:
		for neighbor in HexCoord.neighbors(coord):
			if not component.has(neighbor) or not _is_mountain(cells.get(neighbor)):
				continue
			var entry: float = cells[neighbor].elevation
			if entry < float(cost.get(neighbor, INF)):
				cost[neighbor] = entry
				open[neighbor] = true

	while not open.is_empty():
		var current := _cheapest(open, cost)
		open.erase(current)
		for neighbor in HexCoord.neighbors(current):
			if not component.has(neighbor):
				continue
			var cell: HexCell = cells[neighbor]
			if _is_mountain(cell):
				var next_cost: float = float(cost[current]) + cell.elevation
				if next_cost < float(cost.get(neighbor, INF)):
					cost[neighbor] = next_cost
					came_from[neighbor] = current
					open[neighbor] = true
				continue
			if not cell.is_passable() or from_piece.has(neighbor):
				continue
			if not to_piece.has(neighbor):
				continue  ## A third piece — let it connect on its own turn rather than routing this one through it.
			return _trace(came_from, current)
	return []


static func _trace(came_from: Dictionary, end: Vector2i) -> Array:
	var route: Array = [end]
	var current := end
	while came_from.has(current):
		current = came_from[current]
		route.append(current)
	return route


## Linear scan rather than a binary heap, same call HexPathfinder documents
## for its own open set: the frontier here is a subset of the map's few
## hundred mountain hexes.
static func _cheapest(open: Dictionary, cost: Dictionary) -> Vector2i:
	var best := Vector2i.ZERO
	var best_cost := INF
	var first := true
	for coord: Vector2i in open:
		var value: float = float(cost.get(coord, INF))
		if first or value < best_cost or (value == best_cost and coord < best):
			best = coord
			best_cost = value
			first = false
	return best


static func _is_mountain(cell: HexCell) -> bool:
	return cell != null and cell.height_level() == ElevationLevels.MOUNTAIN


## Deliberately a restatement of HexCell.is_passable()'s non-elevation
## clauses: this pass exists to measure and repair the difference between
## the two rules, so it needs the one that predates it. Kept in step with
## that method by hand — the same trade scripts/test/verify_elevation.gd
## makes for the same reason.
static func _walkable_ignoring_elevation(cell: HexCell) -> bool:
	if cell == null:
		return false
	return cell.terrain_feature != GameEnums.TerrainFeature.MARSH \
		and cell.terrain_feature != GameEnums.TerrainFeature.PEAT_BOG \
		and cell.biome_type != GameEnums.BiomeType.OCEAN
