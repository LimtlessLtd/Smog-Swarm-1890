class_name ZoneOfControlMarkerRenderer
extends RefCounted

## Zone of Control markers, Strategic world-view surface (TacticalHexView has
## its own copy) — Military coverage as an outline, Civilian as a fill
## (ZoneOfControlVisuals). Rebuilt from scratch on refresh(). No fog-of-war
## gating — a ZoC aura is the player's own projected presence, same as a
## building or wall.

var _layer: Node2D
var _logistics_network: LogisticsNetwork
var _markers: Dictionary = {}  # Vector2i -> Node2D

func _init(layer: Node2D, logistics_network: LogisticsNetwork) -> void:
	_layer = layer
	_logistics_network = logistics_network

func refresh() -> void:
	if not _logistics_network:
		return
	var wanted: Dictionary = {}  # Vector2i -> true
	for coord in _logistics_network.get_covered_hexes():
		wanted[coord] = true

	for coord in _markers.keys():
		if not wanted.has(coord):
			_markers[coord].queue_free()
			_markers.erase(coord)
	for coord in wanted:
		var state := _logistics_network.get_zoc_state(coord)
		if _markers.has(coord):
			_apply_look(_markers[coord], state)
		else:
			var marker := _build_marker(coord, state)
			_layer.add_child(marker)
			_markers[coord] = marker

func _build_marker(coord: Vector2i, state: ZoneOfControlState) -> Node2D:
	var container := Node2D.new()
	container.position = HexCoord.axial_to_world(coord)

	var outline := Line2D.new()
	outline.name = "MilitaryOutline"
	outline.closed = true
	outline.default_color = ZoneOfControlVisuals.MILITARY_OUTLINE_COLOR
	outline.width = ZoneOfControlVisuals.MILITARY_OUTLINE_WIDTH
	outline.points = HexCoord.corner_points(Vector2.ZERO)
	container.add_child(outline)

	var fill := Polygon2D.new()
	fill.name = "CivilianFill"
	fill.color = ZoneOfControlVisuals.CIVILIAN_FILL_COLOR
	fill.polygon = HexCoord.corner_points(Vector2.ZERO)
	container.add_child(fill)

	_apply_look(container, state)
	return container

func _apply_look(marker: Node2D, state: ZoneOfControlState) -> void:
	(marker.get_node("MilitaryOutline") as Line2D).visible = state.has_military_coverage()
	(marker.get_node("CivilianFill") as Polygon2D).visible = state.has_civilian_coverage
