class_name BuildPlacementController
extends Node2D

## Turns a build-menu selection (Phase 6.1's BuildMenuView) into an actual
## placed building — the missing link the design doc calls out:
## BuildingManager.place_building_at_world() has existed since Phase 2.5 but
## nothing has ever called it. Owns the "currently arming a building type"
## state and the ghost preview; BuildMenuView/MainHUD know nothing about
## hexes or world positions, they just tell this "the player wants to place
## a Coal Pithead" via begin_placement().
##
## Parented as a HexGridMap/StrategicOverlayManager sibling under WorldRoot
## (same reasoning as StrategicOverlayManager: shares the same coordinate
## space, including whatever rotation/scale CameraController applies for the
## isometric perspective toggle) so the ghost stays aligned with the grid in
## both perspectives without this class needing to know about that trick.
## Added last among WorldRoot's children in Main.tscn so the ghost draws on
## top of buildings/fog/markers by plain sibling order.
##
## **Real building-sized preview (user report: "no indicator showing me
## where the building will be placed or how big it will be... usually in
## RTS games they put the building icon on the mouse and make it like 80%
## transparent").** `_ghost_building` is the actual building box at
## TacticalHexView.BUILDING_HALF_SIZE — same texture where one's authored,
## same fallback category color otherwise — at partial opacity, and it
## tracks the raw cursor position exactly rather than snapping to the hex
## center: place_building_at_world() itself places at the exact clicked
## world position (Phase 2.5's free positioning within a hex), so a
## hex-snapped preview would have been showing the wrong spot. The hex
## outline (`_ghost_outline`) still shows which hex will register the
## placement, now offset to stay aligned with the hex under the cursor
## rather than moving with it.
##
## Accessibility (design doc: "every color-coded state paired with a
## distinct shape/icon, never color alone"): green/red for placeable/
## blocked is carried by the building preview's own tint, but that alone
## would fail anyone who can't distinguish the two tints at low opacity —
## `_ghost_indicator` (small hexagon vs. diamond, unchanged shape pairing
## from before this pass) is a fixed badge near the box's corner so the
## shape signal survives independent of how the color reads.
##
## Phase 2.5.7 (grilling session): placement is restricted to Tactical zoom
## (CameraController.is_tactical_zoom(), the existing hard-cut threshold —
## no separate stricter one). Selecting a building type while zoomed out
## stays armed (_is_placing/_pending_type unchanged, so zooming in mid-
## selection just works) but is inert: no ghost preview, and a click plays
## AlertTones.negative_tone() instead of placing anything. The same tone
## also now backs every pre-existing BuildingManager.placement_rejected
## reason (occupied hex, insufficient resources, etc.) — this is the
## project's first audio of any kind (design doc Phase 6.2 cross-reference).

signal placement_started(building_type: GameEnums.BuildingType)
signal placement_ended

const _VALID_COLOR := Color(0.20, 0.75, 0.30, 0.85)
const _BLOCKED_COLOR := Color(0.80, 0.20, 0.15, 0.85)
const _INDICATOR_RADIUS := 10.0
const _GHOST_BUILDING_ALPHA := 0.55  ## "Like 80% transparent" per the user's own RTS reference — landed on 55% opacity (45% transparent) after actually looking at it: 80%+ transparent made the preview nearly invisible against textured terrain, the exact problem this whole feature exists to fix. Tinted green/red on top (see _update_ghost()), not a neutral white — the color signal needs to read at a glance, not just the shape.

@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath
@export var camera_path: NodePath  ## Optional — omitting it leaves placement always-allowed (e.g. a headless self-test with no camera in the tree), same fallback LocalDetailManager/StrategicOverlayManager already use for this NodePath.

var _hex_grid_map: HexGridMap
var _building_manager: BuildingManager
var _camera: CameraController

var _is_placing: bool = false
var _pending_type: GameEnums.BuildingType = GameEnums.BuildingType.TERRACED_TENEMENT

var _ghost_outline: Line2D
var _ghost_building: Polygon2D  ## The actual building footprint at its real size/texture, semi-transparent, tracking the cursor exactly.
var _ghost_building_outline: Line2D  ## Same reasoning as TacticalHexView's own building outline (see that class's doc comment): a semi-transparent fill alone reads poorly against similarly-toned terrain, an outline doesn't.
var _ghost_indicator: Polygon2D  ## Small hexagon (valid) or diamond (blocked) — the shape half of the color pairing.
var _reject_player: AudioStreamPlayer

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
		_building_manager.placement_rejected.connect(_on_placement_rejected)
	if camera_path != NodePath():
		_camera = get_node(camera_path)
		_camera.tactical_mode_changed.connect(_on_tactical_mode_changed)

	_ghost_outline = Line2D.new()
	_ghost_outline.width = 3.0
	_ghost_outline.closed = true
	add_child(_ghost_outline)

	_ghost_building = Polygon2D.new()
	add_child(_ghost_building)

	_ghost_building_outline = Line2D.new()
	_ghost_building_outline.closed = true
	_ghost_building_outline.width = 3.0
	add_child(_ghost_building_outline)

	_ghost_indicator = Polygon2D.new()
	add_child(_ghost_indicator)

	_reject_player = AudioStreamPlayer.new()
	_reject_player.stream = AlertTones.negative_tone()
	add_child(_reject_player)

	_set_ghost_visible(false)

func is_placing() -> bool:
	return _is_placing

func begin_placement(building_type: GameEnums.BuildingType) -> void:
	_is_placing = true
	_pending_type = building_type
	_set_ghost_visible(true)
	placement_started.emit(building_type)

func cancel_placement() -> void:
	if not _is_placing:
		return
	_is_placing = false
	_set_ghost_visible(false)
	placement_ended.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_placing:
		return
	if event is InputEventMouseMotion:
		_update_ghost(get_global_mouse_position())
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_attempt_placement(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		cancel_placement()

## Public so a headless self-test can drive placement directly without
## fighting Godot's input-event simulation pipeline — this is the exact same
## call the real mouse-click path above makes.
func _attempt_placement(world_pos: Vector2) -> void:
	if not _building_manager:
		return
	if not _is_tactical_zoom():
		_reject_player.play()  # 2.5.7: zoomed out — inert by design, no BuildingManager call at all.
		return
	var accepted := _building_manager.place_building_at_world(_pending_type, world_pos)
	if not accepted:
		return  # BuildingManager already emitted placement_rejected, which _on_placement_rejected plays the tone for.
	# Shift-click stays in placement mode for rapid multi-placement of the
	# same building type; a plain click places one and exits placement mode.
	if Input.is_key_pressed(KEY_SHIFT):
		_update_ghost(world_pos)
	else:
		cancel_placement()

func _on_placement_rejected(_building_type: GameEnums.BuildingType, _coord: Vector2i, _reason: String) -> void:
	_reject_player.play()

func _on_tactical_mode_changed(_is_tactical: bool) -> void:
	if _is_placing:
		_set_ghost_visible(true)  ## Re-evaluates against the new zoom state — shows/hides the ghost live as the player crosses the threshold mid-selection.

func _is_tactical_zoom() -> bool:
	return _camera == null or _camera.is_tactical_zoom()

func _update_ghost(world_pos: Vector2) -> void:
	if not _hex_grid_map:
		return
	var coord := _hex_grid_map.world_to_coord(world_pos)
	# Follow the cursor exactly — matches place_building_at_world()'s own
	# free (non-hex-snapped) positioning, so the preview shows exactly
	# where the building will land, not just which hex it'll belong to.
	position = world_pos
	var can_place := _building_manager != null and _building_manager.can_place_building(_pending_type, coord)
	var color: Color = _VALID_COLOR if can_place else _BLOCKED_COLOR

	# The hex outline is drawn around the HEX's center, which is no longer
	# this node's own origin now that `position` tracks the cursor — offset
	# its points by the hex-center-minus-cursor delta instead of moving the
	# whole node there, so it still traces the correct hex's boundary.
	var hex_offset := HexCoord.axial_to_world(coord) - world_pos
	_ghost_outline.points = _offset_polygon(HexCoord.corner_points(Vector2.ZERO), hex_offset)
	_ghost_outline.default_color = color

	var half := TacticalHexView.BUILDING_HALF_SIZE
	var box_points := PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	_ghost_building.polygon = box_points
	var texture := BuildingVisuals.building_texture(_pending_type)
	if texture:
		_ghost_building.texture = texture
		# Real bug fixed (see TacticalHexView.quad_uv()'s own doc comment):
		# Polygon2D.uv is texture-PIXEL-space, not normalized 0..1 - this
		# unit-square array only ever sampled a 1x1-pixel transparent
		# corner, rendering the ghost preview invisible exactly like the
		# real building box was. Reuse the same shared fix.
		_ghost_building.uv = TacticalHexView.quad_uv(texture)
		_ghost_building.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	else:
		_ghost_building.texture = null
	_ghost_building.color = Color(color.r, color.g, color.b, _GHOST_BUILDING_ALPHA)
	_ghost_building_outline.points = box_points
	_ghost_building_outline.default_color = color  ## Full opacity, unlike the fill — same "outline makes the shape legible regardless of fill/terrain color" reasoning as TacticalHexView's real building outline, doubly true here since the fill is deliberately translucent.

	# Badge sits just outside the box's own corner rather than on top of it,
	# so it stays legible against the (semi-transparent, art-covered) box
	# instead of getting lost inside it.
	_ghost_indicator.position = Vector2(half + _INDICATOR_RADIUS + 6.0, half + _INDICATOR_RADIUS + 6.0)
	_ghost_indicator.color = color
	_ghost_indicator.polygon = _hexagon_points(_INDICATOR_RADIUS) if can_place else _diamond_points(_INDICATOR_RADIUS)

func _set_ghost_visible(is_visible: bool) -> void:
	var actually_visible := is_visible and _is_tactical_zoom()
	_ghost_outline.visible = actually_visible
	_ghost_building.visible = actually_visible
	_ghost_building_outline.visible = actually_visible
	_ghost_indicator.visible = actually_visible
	if actually_visible:
		_update_ghost(get_global_mouse_position())

func _offset_polygon(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(points.size())
	for i in range(points.size()):
		result[i] = points[i] + offset
	return result

func _hexagon_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(6):
		var angle := deg_to_rad(60.0 * i - 30.0)
		points.append(Vector2(radius * cos(angle), radius * sin(angle)))
	return points

func _diamond_points(radius: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, -radius), Vector2(radius, 0), Vector2(0, radius), Vector2(-radius, 0)])
