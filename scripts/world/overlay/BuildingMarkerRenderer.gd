class_name BuildingMarkerRenderer
extends RefCounted

## Strategic-zoom building icons: one triangle Polygon2D per placed
## BuildingInstance, tinted by construction/ruin/category state. Depends only
## on the layer it draws into and the data it's handed — StrategicOverlayManager
## wires BuildingManager.building_placed/removed to this AND to
## FrontierMarkerRenderer.refresh() as two separate connections, so this
## class has no dependency on frontier state.

var _layer: Node2D
var _icons: Dictionary = {}  # int (BuildingInstance.id) -> Node2D

func _init(layer: Node2D) -> void:
	_layer = layer

func seed(instances: Array[BuildingInstance]) -> void:
	for instance in instances:
		on_placed(instance)

func on_placed(instance: BuildingInstance) -> void:
	var icon := _build_icon(instance)
	_layer.add_child(icon)
	_icons[instance.id] = icon

func on_removed(instance: BuildingInstance) -> void:
	var icon: Node2D = _icons.get(instance.id)
	if icon:
		icon.queue_free()
	_icons.erase(instance.id)

## Recolors the existing icon in place — the building stays on the map as a
## ruin, it doesn't vanish, so on_removed()'s queue_free() path isn't right here.
func on_ruined(instance: BuildingInstance, _lost_population: int) -> void:
	var icon: Polygon2D = _icons.get(instance.id)
	if icon:
		icon.color = BuildingVisuals.ruin_color()

## on_placed() already added this icon (construction-tinted) the moment
## construction started; this recolors it in place once finished rather than
## re-adding it.
func on_construction_completed(instance: BuildingInstance) -> void:
	_recolor(instance)

## design_doc.md §2.1's "Going dark" — StrategicOverlayManager wires this to
## BuildingManager.building_powered_down AND building_powered_up, so one hook
## covers both directions: _icon_color() reads the instance's current state
## rather than the signal deciding the color.
func on_power_changed(instance: BuildingInstance) -> void:
	_recolor(instance)

func _recolor(instance: BuildingInstance) -> void:
	var icon: Polygon2D = _icons.get(instance.id)
	if icon:
		icon.color = _icon_color(instance)

## Construction beats powered-down beats ruin-vs-category, matching
## TacticalHexView._building_base_modulate()'s ordering so the same building
## never reads as two different states at the two zoom levels.
func _icon_color(instance: BuildingInstance) -> Color:
	if instance.is_under_construction:
		return BuildingVisuals.construction_color()
	if instance.is_ruined:
		return BuildingVisuals.ruin_color()
	if instance.is_powered_down:
		return BuildingVisuals.powered_down_color()
	return BuildingVisuals.category_color(instance.definition.category)

func _build_icon(instance: BuildingInstance) -> Node2D:
	var icon := Polygon2D.new()
	icon.color = _icon_color(instance)
	var r := 16.0  # Bigger than TacticalHexView's building boxes — needs to read at zoomed-out scale.
	icon.polygon = PackedVector2Array([Vector2(0, -r), Vector2(r, r * 0.6), Vector2(-r, r * 0.6)])
	icon.position = HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
	return icon
