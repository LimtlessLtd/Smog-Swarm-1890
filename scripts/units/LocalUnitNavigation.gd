class_name LocalUnitNavigation
extends RefCounted

## Routes are computed once per leg and followed without frame-dependent steering.
const CLEARANCE := 0.45
const SAMPLE_STEP := HexCoord.SUB_HEX_CELL_SIZE_WORLD_UNITS
const MAX_GRID_SPAN := 72

var map: HexGridMap
var buildings: BuildingManager
var walls: WallManager
var logistics: LogisticsNetwork
var _obstacles: Array[Vector3] = []
var _segments: Array[WallSegment] = []
var _origin := Vector2.ZERO
var _destination := Vector2.ZERO
var _route_cache: Dictionary = {}
var revision: int = 0
var _network_signature: int = 0

func setup(grid: HexGridMap, building_manager: BuildingManager, wall_manager: WallManager, network: LogisticsNetwork = null) -> void:
	map = grid
	buildings = building_manager
	walls = wall_manager
	logistics = network
	if map:
		map.generation_completed.connect(func(_count: int) -> void: invalidate())
	if logistics:
		logistics.network_recomputed.connect(_on_network_changed)
	if walls:
		walls.walls_restored.connect(invalidate)
		for event in ["wall_segment_placed", "wall_segment_removed", "wall_segment_breached", "wall_segment_repaired"]:
			walls.connect(event, func(_a = null, _b = null) -> void: invalidate())
	if buildings:
		for event in ["building_placed", "building_removed", "building_ruined"]:
			buildings.connect(event, func(_a = null, _b = null) -> void: invalidate())

func find_route(from: Vector2, target: Vector2) -> PackedVector2Array:
	_origin = from
	_destination = target
	var key := Vector4(from.x, from.y, target.x, target.y)
	if _route_cache.has(key):
		return _route_cache[key].duplicate()
	var bounds := Rect2(from, Vector2.ZERO).expand(target).grow(64.0)
	_gather(bounds)
	if not is_ground_passable(target) or _inside_building(target):
		return PackedVector2Array()
	if line_clear(from, target):
		return PackedVector2Array([target])
	var step := maxf(SAMPLE_STEP, maxf(bounds.size.x, bounds.size.y) / float(MAX_GRID_SPAN))
	var count := Vector2i(ceili(bounds.size.x / step) + 1, ceili(bounds.size.y / step) + 1)
	var raw := _grid_route(from, target, bounds.position, step, count)
	var result := PackedVector2Array()
	var anchor := from
	var index := 1
	while index < raw.size():
		var farthest := index
		while farthest + 1 < raw.size() and line_clear(anchor, raw[farthest + 1]):
			farthest += 1
		anchor = raw[farthest]
		result.append(anchor)
		index = farthest + 1
	if _route_cache.size() >= 64:
		_route_cache.clear()
	_route_cache[key] = result.duplicate()
	return result

func is_ground_passable(world: Vector2) -> bool:
	if not map:
		return true
	var coord := HexCoord.world_to_axial(world)
	var cell := map.get_cell(coord)
	if not cell or ElevationLevels.is_impassable(cell.height_level()):
		return false
	if SubHexTerrainQuery.biome_at(coord, world, cell.biome_type) == GameEnums.BiomeType.WATERWAY:
		if not logistics:
			return false
		var on_bridge := false
		for neighbor in HexCoord.neighbors(coord):
			if logistics.is_bridge_between(coord, neighbor):
				var nearest := Geometry2D.get_closest_point_to_segment(world, HexCoord.axial_to_world(coord), HexCoord.axial_to_world(neighbor))
				on_bridge = on_bridge or world.distance_to(nearest) <= SAMPLE_STEP * 2.0
		if not on_bridge:
			return false
	return SubHexTerrainQuery.is_passable_at(coord, world, cell.is_passable())

func _gather(bounds: Rect2) -> void:
	_obstacles.clear()
	_segments.clear()
	if buildings:
		for building in buildings.get_all_buildings():
			var point := HexCoord.axial_to_world(building.hex_coord) + building.local_position
			if bounds.grow(ObstacleRadii.BUILDING_RADIUS).has_point(point):
				_obstacles.append(Vector3(point.x, point.y, TacticalHexView.BUILDING_HALF_SIZE + CLEARANCE))
	if walls:
		for segment in walls.get_segments():
			if segment.is_breached() or segment.is_gate:
				continue
			if bounds.intersects(Rect2(segment.point_a, Vector2.ZERO).expand(segment.point_b).grow(1.0)):
				_segments.append(segment)

func _inside_building(point: Vector2) -> bool:
	for obstacle in _obstacles:
		if absf(point.x - obstacle.x) < obstacle.z and absf(point.y - obstacle.y) < obstacle.z:
			return true
	return false

func line_clear(from: Vector2, to: Vector2) -> bool:
	for segment in _segments:
		var hit: Variant = Geometry2D.segment_intersects_segment(from, to, segment.point_a, segment.point_b)
		if hit != null:
			var entering_target := to.distance_to(_destination) < 0.02 and (hit as Vector2).distance_to(to) < 0.02
			var leaving_start := from.distance_to(_origin) < 0.02 and (hit as Vector2).distance_to(from) < 0.02
			if not entering_target and not leaving_start:
				return false
	var steps := maxi(1, ceili(from.distance_to(to) / SAMPLE_STEP))
	var escaping_building := _inside_building(from)
	for i in range(1, steps + 1):
		var point := from.lerp(to, float(i) / steps)
		if not is_ground_passable(point):
			return false
		if _inside_building(point):
			if not escaping_building:
				return false
		else:
			escaping_building = false
	return true

func invalidate() -> void:
	revision += 1
	_route_cache.clear()

func _on_network_changed() -> void:
	var geometry: Array = []
	for segment in logistics.get_save_segments():
		geometry.append([segment.hex_a, segment.hex_b, segment.line_type, segment.is_severed])
	var signature := hash(geometry)
	if signature != _network_signature:
		_network_signature = signature
		invalidate()

func _grid_route(from: Vector2, target: Vector2, origin: Vector2, step: float, count: Vector2i) -> PackedVector2Array:
	var scores: Dictionary = {}
	var parents: Dictionary = {}
	var closed: Dictionary = {}
	var passable: Dictionary = {}
	var heap: Array[Vector2] = []
	var start_cell := Vector2i(((from - origin) / step).round())
	for y in range(start_cell.y - 2, start_cell.y + 3):
		for x in range(start_cell.x - 2, start_cell.x + 3):
			if x < 0 or y < 0 or x >= count.x or y >= count.y:
				continue
			var id := y * count.x + x
			var point := origin + Vector2(x, y) * step
			if is_ground_passable(point) and not _inside_building(point) and line_clear(from, point):
				var cost := from.distance_to(point)
				scores[id] = cost
				parents[id] = -1
				_heap_push(heap, Vector2(cost + point.distance_to(target), id))
	var finish := -1
	while not heap.is_empty():
		var id := _heap_pop(heap)
		if closed.has(id):
			continue
		closed[id] = true
		var cell := Vector2i(id % count.x, id / count.x)
		var point := origin + Vector2(cell) * step
		if point.distance_to(target) <= step * 2.0 and line_clear(point, target):
			finish = id
			break
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var next := cell + Vector2i(dx, dy)
				if next.x < 0 or next.y < 0 or next.x >= count.x or next.y >= count.y:
					continue
				var other := next.y * count.x + next.x
				if closed.has(other):
					continue
				var next_point := origin + Vector2(next) * step
				if not passable.has(other):
					passable[other] = is_ground_passable(next_point) and not _inside_building(next_point)
				if not passable[other]:
					continue
				var cost: float = scores[id] + point.distance_to(next_point)
				if cost >= float(scores.get(other, INF)) or not line_clear(point, next_point):
					continue
				scores[other] = cost
				parents[other] = id
				_heap_push(heap, Vector2(cost + next_point.distance_to(target), other))
	if finish < 0:
		return PackedVector2Array()
	var route := PackedVector2Array([target])
	while finish >= 0:
		route.append(origin + Vector2(finish % count.x, finish / count.x) * step)
		finish = parents[finish]
	route.append(from)
	route.reverse()
	return route

func _heap_push(heap: Array[Vector2], item: Vector2) -> void:
	heap.append(item)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if heap[parent].x <= item.x:
			break
		heap[index] = heap[parent]
		index = parent
	heap[index] = item

func _heap_pop(heap: Array[Vector2]) -> int:
	var id := int(heap[0].y)
	var last: Vector2 = heap.pop_back()
	if heap.is_empty():
		return id
	var index := 0
	while index * 2 + 1 < heap.size():
		var child := index * 2 + 1
		if child + 1 < heap.size() and heap[child + 1].x < heap[child].x:
			child += 1
		if last.x <= heap[child].x:
			break
		heap[index] = heap[child]
		index = child
	heap[index] = last
	return id
