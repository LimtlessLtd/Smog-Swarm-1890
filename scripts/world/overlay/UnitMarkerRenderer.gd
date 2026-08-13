class_name UnitMarkerRenderer
extends RefCounted

## Strategic-zoom unit icons: one circle Polygon2D per trained UnitInstance.
## Color/shape distinct from building markers (accessibility — never color alone).

const UNIT_MARKER_COLOR := Color(0.3, 0.55, 0.85)
const UNIT_MARKER_RADIUS := 10.0  ## Smaller than a building icon's 16 — reads as a token, not a structure.

var _layer: Node2D
var _icons: Dictionary = {}  # int (UnitInstance.id) -> Node2D

func _init(layer: Node2D) -> void:
	_layer = layer

func seed(instances: Array[UnitInstance]) -> void:
	for instance in instances:
		on_trained(instance)

func on_trained(instance: UnitInstance) -> void:
	var icon := _build_icon(instance)
	_layer.add_child(icon)
	_icons[instance.id] = icon

func on_removed(instance: UnitInstance) -> void:
	var icon: Node2D = _icons.get(instance.id)
	if icon:
		icon.queue_free()
	_icons.erase(instance.id)

func on_moved(instance: UnitInstance, _from_coord: Vector2i, to_coord: Vector2i) -> void:
	var icon: Node2D = _icons.get(instance.id)
	if icon:
		icon.position = HexCoord.axial_to_world(to_coord)

func _build_icon(instance: UnitInstance) -> Node2D:
	var icon := Polygon2D.new()
	icon.color = UNIT_MARKER_COLOR
	icon.polygon = StrategicMarkerShapes.circle_points(UNIT_MARKER_RADIUS)
	icon.position = HexCoord.axial_to_world(instance.hex_coord)
	return icon
