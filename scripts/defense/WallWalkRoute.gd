class_name WallWalkRoute
extends RefCounted

## A connected wall is a graph of physical endpoints; a patrol visits its edges
## and returns along branches. Breaches and removed pieces break connectivity.
static func perimeter(walls: WallManager, start: WallSegment, from: Vector2) -> PackedVector2Array:
	var graph := AStar2D.new()
	var endpoints: Dictionary = {}
	for segment in walls.get_segments():
		if segment.is_breached():
			continue
		var ids: Array[int] = []
		for point in [segment.point_a, segment.point_b]:
			var key: Vector2 = point.snapped(Vector2.ONE * 0.01)
			if not endpoints.has(key):
				var id := endpoints.size()
				endpoints[key] = id
				graph.add_point(id, point)
			ids.append(endpoints[key])
		graph.connect_points(ids[0], ids[1])
	var entry := start.point_a if from.distance_to(start.point_a) < from.distance_to(start.point_b) else start.point_b
	var root: int = endpoints.get(entry.snapped(Vector2.ONE * 0.01), -1)
	if root < 0:
		return PackedVector2Array()
	var cycle := PackedVector2Array([entry])
	var previous := -1
	var cursor := root
	for i in graph.get_point_count():
		var neighbors := graph.get_point_connections(cursor)
		if neighbors.size() != 2:
			break
		var next := neighbors[0] if neighbors[0] != previous else neighbors[1]
		cycle.append(graph.get_point_position(next))
		if next == root:
			return cycle
		previous = cursor
		cursor = next
	var route := PackedVector2Array([entry])
	var visited: Dictionary = {root: true}
	var stack: Array[int] = [root]
	while not stack.is_empty():
		var current: int = stack.back()
		var next := -1
		for neighbor in graph.get_point_connections(current):
			if not visited.has(neighbor):
				next = neighbor
				break
		if next >= 0:
			visited[next] = true
			stack.append(next)
			route.append(graph.get_point_position(next))
		else:
			stack.pop_back()
			if not stack.is_empty():
				route.append(graph.get_point_position(stack.back()))
	return route

static func segment_at(walls: WallManager, point: Vector2, tolerance: float = 0.15) -> WallSegment:
	if not walls:
		return null
	for segment in walls.get_segments():
		if not segment.is_breached() and point.distance_to(Geometry2D.get_closest_point_to_segment(point, segment.point_a, segment.point_b)) <= tolerance:
			return segment
	return null

static func path_on_wall(walls: WallManager, from: Vector2, to: Vector2) -> PackedVector2Array:
	var start := segment_at(walls, from)
	var goal := segment_at(walls, to)
	if not start or not goal:
		return PackedVector2Array()
	if start == goal:
		return PackedVector2Array([to])
	var graph := AStar2D.new()
	var endpoints: Dictionary = {}
	for segment in walls.get_segments():
		if segment.is_breached():
			continue
		var ids: Array[int] = []
		for point in [segment.point_a, segment.point_b]:
			var key: Vector2 = point.snapped(Vector2.ONE * 0.01)
			if not endpoints.has(key):
				var id := endpoints.size()
				endpoints[key] = id
				graph.add_point(id, point)
			ids.append(endpoints[key])
		graph.connect_points(ids[0], ids[1])
	var start_id := endpoints.size()
	var end_id := start_id + 1
	graph.add_point(start_id, from)
	graph.add_point(end_id, to)
	for point in [start.point_a, start.point_b]:
		graph.connect_points(start_id, endpoints[point.snapped(Vector2.ONE * 0.01)])
	for point in [goal.point_a, goal.point_b]:
		graph.connect_points(end_id, endpoints[point.snapped(Vector2.ONE * 0.01)])
	var route := graph.get_point_path(start_id, end_id)
	if not route.is_empty():
		route.remove_at(0)
	return route
