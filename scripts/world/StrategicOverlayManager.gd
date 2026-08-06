class_name StrategicOverlayManager
extends Node2D

## Strategic-zoom (Phase 2.5) map markers: a small icon over every placed
## building, and a frontier indicator over hexes where secured and contested
## ground meet. Hides itself entirely while the camera is in Tactical zoom,
## since Tactical view already shows the real buildings/terrain directly
## instead of an abstract icon standing in for them.
##
## This is the "buildable now" slice of the Phase 2.7 plan (todo.md) — wall
## markers, unit markers, under-attack alerts and spotted-horde markers all
## wait on systems that don't exist yet (Phase 4/5) and are documented there
## rather than built here. Whichever of those systems eventually needs to
## raise a marker should follow this class's pattern (a Dictionary of live
## marker nodes keyed by whatever uniquely identifies the source, added/
## removed off that source's own placed/removed-style signals) rather than
## invent a second overlay system.
##
## Parented as a HexGridMap sibling under WorldRoot, same reasoning as
## LocalDetailManager: shares its coordinate space, and — added after both
## HexGridMap and LocalDetailManager in Main.tscn — draws its icons on top
## by plain sibling order.

@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath
@export var camera_path: NodePath

var _hex_grid_map: HexGridMap
var _building_manager: BuildingManager
var _camera: CameraController

var _building_icons: Dictionary = {}    # int (BuildingInstance.id) -> Node2D
var _frontier_markers: Dictionary = {}  # Vector2i -> Node2D

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
		_building_manager.building_placed.connect(_on_building_placed)
		_building_manager.building_removed.connect(_on_building_removed)
		for instance in _building_manager.get_all_buildings():
			_on_building_placed(instance)
	if camera_path != NodePath():
		_camera = get_node(camera_path)
		_camera.tactical_mode_changed.connect(_on_tactical_mode_changed)
		visible = not _camera.is_tactical_zoom()
	_refresh_frontier_markers()

func _on_tactical_mode_changed(is_tactical: bool) -> void:
	visible = not is_tactical

func _on_building_placed(instance: BuildingInstance) -> void:
	var icon := _build_building_icon(instance)
	add_child(icon)
	_building_icons[instance.id] = icon
	_refresh_frontier_markers()  # a new building can flip a hex's safe/contested mix

func _on_building_removed(instance: BuildingInstance) -> void:
	var icon: Node2D = _building_icons.get(instance.id)
	if icon:
		icon.queue_free()
	_building_icons.erase(instance.id)
	_refresh_frontier_markers()

func _build_building_icon(instance: BuildingInstance) -> Node2D:
	var icon := Polygon2D.new()
	icon.color = BuildingVisuals.category_color(instance.definition.category)
	var r := 16.0  # Bigger than TacticalHexView's building boxes — needs to read at zoomed-out scale.
	icon.polygon = PackedVector2Array([Vector2(0, -r), Vector2(r, r * 0.6), Vector2(-r, r * 0.6)])
	icon.position = HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
	return icon

func _refresh_frontier_markers() -> void:
	if not _hex_grid_map:
		return
	var wanted: Dictionary = {}  # Vector2i -> true
	for cell: HexCell in _hex_grid_map.get_all_cells():
		if _is_frontier_hex(cell):
			wanted[cell.coord] = true

	for coord in _frontier_markers.keys():
		if not wanted.has(coord):
			_frontier_markers[coord].queue_free()
			_frontier_markers.erase(coord)
	for coord in wanted:
		if not _frontier_markers.has(coord):
			var marker := _build_frontier_marker(coord)
			add_child(marker)
			_frontier_markers[coord] = marker

## A hex counts as an active frontier once it has BOTH secured ground and a
## contested fringe — a fully wild hex is just unclaimed territory, not a
## line worth marking, and a fully secured hex has nothing contesting it.
func _is_frontier_hex(cell: HexCell) -> bool:
	return cell.is_frontier() and not cell.get_safe_districts().is_empty()

func _build_frontier_marker(coord: Vector2i) -> Node2D:
	var marker := Line2D.new()
	marker.width = 4.0
	marker.default_color = Color(0.85, 0.25, 0.15, 0.85)
	marker.closed = true
	marker.position = HexCoord.axial_to_world(coord)
	marker.points = HexCoord.corner_points(Vector2.ZERO)
	return marker
