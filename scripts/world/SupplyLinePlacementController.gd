class_name SupplyLinePlacementController
extends Node2D

## Turns an Infrastructure card selection into an actual placed
## SupplyLineSegment — LogisticsNetwork.place_segment() had no caller until
## this class existed, the same "mechanism exists, nothing in the UI/input
## layer ever called it" gap WallPlacementController's own doc comment
## already found and fixed for wall placement (Infrastructure rework,
## todo.md, 2026-08-16).
##
## Click-click chain, mirroring WallPlacementController's own model but
## HEX-SNAPPED instead of freehand: a SupplyLineSegment is exactly one
## hex-to-hex edge by construction (LogisticsNetwork.get_segment_between()),
## not a chain of independently-placed <=100m pieces the way a wall is — so
## there's no sub-hex geometry to draw freehand. Left-click a hex to set the
## anchor; every subsequent left-click on an ADJACENT hex commits a segment
## from the anchor to that hex AND re-anchors there (chaining continues
## automatically, same as walls); a click on a non-adjacent hex (or the
## anchor's own hex) is rejected — same tone as any other placement
## rejection — rather than silently re-anchoring, keeping the interaction
## model to exactly two outcomes (commit-and-advance, or retry) instead of
## a third implicit "just move the anchor" behavior. Right-click/Esc exits
## placement mode entirely.
##
## Parented as a HexGridMap/BuildPlacementController/WallPlacementController
## sibling under WorldRoot, same coordinate-space reasoning those classes'
## own doc comments already give.
##
## Only arms tier 0 of whichever line_type was selected — mirrors
## WallPlacementController's own "fresh placement stays Wooden-only,
## upgrade_segment() is the only way to advance it" precedent exactly
## (LogisticsNetwork.upgrade_segment() exists for the same reason
## WallManager.upgrade_segment() does, with the same "no UI caller yet"
## gap — not a new gap introduced here, an existing one this class doesn't
## attempt to close).

signal placement_started(line_type: GameEnums.SupplyLineType, tier: int)
signal placement_ended

const _VALID_COLOR := Color(0.20, 0.75, 0.30, 0.9)
const _BLOCKED_COLOR := Color(0.80, 0.20, 0.15, 0.9)
const _PREVIEW_WIDTH := 6.0
const _ANCHOR_RADIUS := 12.0

@export var hex_grid_map_path: NodePath
@export var logistics_network_path: NodePath
@export var camera_path: NodePath  ## Optional — see BuildPlacementController's own doc comment on this same fallback.

var _hex_grid_map: HexGridMap
var _logistics_network: LogisticsNetwork
var _camera: CameraController

var _is_placing: bool = false
var _pending_line_type: GameEnums.SupplyLineType = GameEnums.SupplyLineType.ROAD
var _has_anchor: bool = false
var _anchor_hex: Vector2i = Vector2i.ZERO

var _preview_line: Line2D
var _anchor_marker: Polygon2D
var _reject_player: AudioStreamPlayer
var _hint_layer: CanvasLayer
var _hint_label: Label

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if logistics_network_path != NodePath():
		_logistics_network = get_node(logistics_network_path)
		_logistics_network.placement_rejected.connect(_on_placement_rejected)
	if camera_path != NodePath():
		_camera = get_node(camera_path)
		_camera.tactical_mode_changed.connect(_on_tactical_mode_changed)

	_preview_line = Line2D.new()
	_preview_line.width = _PREVIEW_WIDTH
	_preview_line.visible = false
	add_child(_preview_line)

	_anchor_marker = Polygon2D.new()
	_anchor_marker.polygon = HexCoord.corner_points(Vector2.ZERO)
	_anchor_marker.visible = false
	add_child(_anchor_marker)

	_reject_player = AudioStreamPlayer.new()
	_reject_player.stream = AlertTones.negative_tone()
	add_child(_reject_player)

	_hint_layer = CanvasLayer.new()
	add_child(_hint_layer)
	_hint_label = Label.new()
	HUDStyles.style_label(_hint_label)
	_hint_label.visible = false
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_KEEP_SIZE)
	_hint_label.offset_top -= 80.0
	_hint_label.offset_bottom -= 80.0
	_hint_layer.add_child(_hint_label)

func is_placing() -> bool:
	return _is_placing

func begin_placement(line_type: GameEnums.SupplyLineType) -> void:
	_is_placing = true
	_pending_line_type = line_type
	_has_anchor = false
	_preview_line.visible = false
	_anchor_marker.visible = false
	_hint_label.visible = true
	_hint_label.text = "Placing %s — click a hex to start, then an adjacent hex to connect it.  Right-click (or Esc) to finish." % SupplyLineCatalog.get_display_name(line_type, 0)
	placement_started.emit(line_type, 0)

func cancel_placement() -> void:
	if not _is_placing:
		return
	_is_placing = false
	_has_anchor = false
	_preview_line.visible = false
	_anchor_marker.visible = false
	_hint_label.visible = false
	placement_ended.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_placing:
		return
	if event is InputEventMouseMotion:
		if _has_anchor:
			_update_preview(get_global_mouse_position())
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		cancel_placement()

func _on_left_click(world_pos: Vector2) -> void:
	if not _hex_grid_map:
		return
	if not _is_tactical_zoom():
		_reject_player.play()  # Same "inert, not silently ignored" convention as BuildPlacementController/WallPlacementController's own zoom gate.
		return
	var coord := _hex_grid_map.world_to_coord(world_pos)
	if not _has_anchor:
		_anchor_hex = coord
		_has_anchor = true
		_anchor_marker.position = HexCoord.axial_to_world(coord)
		_anchor_marker.visible = true
		_preview_line.visible = true
		_update_preview(world_pos)
		return
	if not _logistics_network:
		return
	if HexCoord.distance(_anchor_hex, coord) != 1:
		_reject_player.play()  # Not adjacent to the current anchor — retry, same anchor (this class's own doc comment: two outcomes only, no implicit re-anchor).
		return
	var segment := _logistics_network.place_segment(_pending_line_type, 0, _anchor_hex, coord)
	if not segment:
		return  # LogisticsNetwork already emitted placement_rejected, which _on_placement_rejected plays the tone for.
	_anchor_hex = coord
	_anchor_marker.position = HexCoord.axial_to_world(coord)
	_update_preview(world_pos)

## Straight line between the anchor hex's center and the hovered hex's
## center — infrastructure IS the hex edge, no sub-hex geometry to trace
## the way a wall's freehand line has.
func _update_preview(raw_world_pos: Vector2) -> void:
	if not _hex_grid_map:
		return
	var hovered := _hex_grid_map.world_to_coord(raw_world_pos)
	var anchor_center := HexCoord.axial_to_world(_anchor_hex)
	var hovered_center := HexCoord.axial_to_world(hovered)
	var can_place := _logistics_network != null and HexCoord.distance(_anchor_hex, hovered) == 1 and _logistics_network.can_place_segment(_pending_line_type, 0, _anchor_hex, hovered)
	var color: Color = _VALID_COLOR if can_place else _BLOCKED_COLOR
	_preview_line.points = PackedVector2Array([anchor_center, hovered_center])
	_preview_line.default_color = color
	_anchor_marker.color = Color(color.r, color.g, color.b, 0.35)

func _on_placement_rejected(_hex_a: Vector2i, _hex_b: Vector2i, _reason: String) -> void:
	_reject_player.play()

func _on_tactical_mode_changed(_is_tactical: bool) -> void:
	pass  ## Same "not worth special-casing" call WallPlacementController's own handler makes.

func _is_tactical_zoom() -> bool:
	return _camera == null or _camera.is_tactical_zoom()
