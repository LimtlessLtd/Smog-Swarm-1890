class_name FrontierMarkerRenderer
extends RefCounted

## Frontier line: a hex counts as an active frontier once it has BOTH secured
## ground and a contested fringe — a fully wild hex is unclaimed territory,
## not a line worth marking; a fully secured hex has nothing contesting it.
## Rebuilt from scratch on refresh() — dozens of hexes at most, not thousands.

var _layer: Node2D
var _hex_grid_map: HexGridMap
var _markers: Dictionary = {}  # Vector2i -> Node2D

func _init(layer: Node2D, hex_grid_map: HexGridMap) -> void:
	_layer = layer
	_hex_grid_map = hex_grid_map

func refresh() -> void:
	if not _hex_grid_map:
		return
	var wanted: Dictionary = {}  # Vector2i -> true
	for cell: HexCell in _hex_grid_map.get_all_cells():
		if _is_frontier_hex(cell):
			wanted[cell.coord] = true

	for coord in _markers.keys():
		if not wanted.has(coord):
			_markers[coord].queue_free()
			_markers.erase(coord)
	for coord in wanted:
		if not _markers.has(coord):
			var marker := _build_marker(coord)
			_layer.add_child(marker)
			_markers[coord] = marker

func _is_frontier_hex(cell: HexCell) -> bool:
	return cell.is_frontier() and not cell.get_safe_districts().is_empty()

func _build_marker(coord: Vector2i) -> Node2D:
	var marker := Line2D.new()
	marker.width = 4.0
	marker.default_color = Color(0.85, 0.25, 0.15, 0.85)
	marker.closed = true
	marker.position = HexCoord.axial_to_world(coord)
	marker.points = HexCoord.corner_points(Vector2.ZERO)
	return marker
