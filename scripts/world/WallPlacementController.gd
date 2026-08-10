class_name WallPlacementController
extends Node2D

## Turns a wall-tier selection into an actual drawn wall — the missing link
## this project never had at all: WallManager.place_wall_line() (née
## place_segment()) has existed since Phase 4.1 but nothing in the UI/input
## layer ever called it. Confirmed directly this pass, not assumed: a
## project-wide grep found ZERO call sites for wall placement anywhere
## outside WallManager's own seed_starting_defenses() — every wall segment
## a player has ever seen in this game was the free starting perimeter,
## never something they placed themselves. Player report ("walls are not
## free hand to place/draw") presupposed a placement mechanism that just
## didn't exist yet, not merely a hex-locked one.
##
## Mirrors BuildPlacementController's own shape (arm a type, ghost preview,
## Tactical-zoom-only, Shift-to-chain, right-click/Esc to cancel) with one
## real difference: a building places at a single point on click, a wall
## places along a DRAWN LINE — press-drag-release, not click. Left mouse
## down starts recording a line from the cursor's current world position;
## every subsequent motion event updates a live preview line to the
## cursor's CURRENT position (not a record of the whole mouse path — a
## straight drawn line end-to-end, matching *They Are Billions*' own
## click-drag model per direct research, not a freehand squiggle); left
## mouse up commits it via WallManager.place_wall_line(), which does the
## actual <=100m-piece chopping (WallCatalog.MAX_SEGMENT_LENGTH_WORLD_UNITS).
##
## Parented as a HexGridMap/BuildPlacementController sibling under
## WorldRoot, same coordinate-space reasoning as that class's own doc
## comment.

signal placement_started(tier: int)
signal placement_ended

const _VALID_COLOR := Color(0.20, 0.75, 0.30, 0.9)
const _BLOCKED_COLOR := Color(0.80, 0.20, 0.15, 0.9)
const _PREVIEW_WIDTH := 6.0

@export var hex_grid_map_path: NodePath
@export var wall_manager_path: NodePath
@export var camera_path: NodePath  ## Optional — see BuildPlacementController's own doc comment on this same fallback.

var _hex_grid_map: HexGridMap
var _wall_manager: WallManager
var _camera: CameraController

var _is_placing: bool = false
## Design doc precedent kept intact (WallManager.place_segment()'s own old
## doc comment: "Every fresh segment starts at Wooden tier... upgrade_segment()
## is the only way to advance it from there") — fresh placement stays
## Wooden-only, same as before this rework; place_wall_line() itself
## accepts any tier (internal reuse, e.g. a future seeded-at-tier scenario),
## this controller just never arms anything but Wooden from the UI.
var _pending_tier: int = WallCatalog.WOODEN
var _pending_is_gate: bool = false
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO

var _preview_line: Line2D
var _reject_player: AudioStreamPlayer

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if wall_manager_path != NodePath():
		_wall_manager = get_node(wall_manager_path)
		_wall_manager.placement_rejected.connect(_on_placement_rejected)
	if camera_path != NodePath():
		_camera = get_node(camera_path)
		_camera.tactical_mode_changed.connect(_on_tactical_mode_changed)

	_preview_line = Line2D.new()
	_preview_line.width = _PREVIEW_WIDTH
	_preview_line.visible = false
	add_child(_preview_line)

	_reject_player = AudioStreamPlayer.new()
	_reject_player.stream = AlertTones.negative_tone()
	add_child(_reject_player)

func is_placing() -> bool:
	return _is_placing

func begin_placement(is_gate: bool = false) -> void:
	_is_placing = true
	_pending_tier = WallCatalog.WOODEN
	_pending_is_gate = is_gate
	_is_dragging = false
	_preview_line.visible = false
	placement_started.emit(_pending_tier)

func cancel_placement() -> void:
	if not _is_placing:
		return
	_is_placing = false
	_is_dragging = false
	_preview_line.visible = false
	placement_ended.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_placing:
		return
	if event is InputEventMouseMotion and _is_dragging:
		_update_preview(get_global_mouse_position())
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_drag(get_global_mouse_position())
			else:
				_end_drag(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_placement()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		cancel_placement()

func _begin_drag(world_pos: Vector2) -> void:
	if not _is_tactical_zoom():
		_reject_player.play()  # Same "inert, not silently ignored" convention as BuildPlacementController's own zoom gate.
		return
	_is_dragging = true
	_drag_start = world_pos
	_preview_line.visible = true
	_update_preview(world_pos)

## Public so a headless self-test can drive placement directly without
## fighting Godot's input-event simulation pipeline — same precedent
## BuildPlacementController._attempt_placement() already sets.
func _end_drag(world_pos: Vector2) -> void:
	if not _is_dragging:
		return
	_is_dragging = false
	_preview_line.visible = false
	if not _wall_manager:
		return
	var placed := _wall_manager.place_wall_line(_drag_start, world_pos, _pending_tier, _pending_is_gate)
	if placed.is_empty():
		_reject_player.play()  # WallManager already emitted placement_rejected per failed piece, which _on_placement_rejected also plays this for — harmless double-play, avoids a silent "nothing happened" when EVERY piece failed (e.g. the whole drag landed on impassable ground).
	# Shift-drag stays in placement mode for drawing another run immediately
	# — same "hold Shift to keep going" convention BuildPlacementController's
	# own Shift-click chaining already established for buildings.
	if not Input.is_key_pressed(KEY_SHIFT):
		cancel_placement()

func _update_preview(world_pos: Vector2) -> void:
	_preview_line.points = PackedVector2Array([_drag_start, world_pos])
	var can_place := _wall_manager != null and _wall_manager.can_place_wall_piece(_drag_start, world_pos, _pending_tier)
	_preview_line.default_color = _VALID_COLOR if can_place else _BLOCKED_COLOR

func _on_placement_rejected(_hex_a: Vector2i, _hex_b: Vector2i, _reason: String) -> void:
	_reject_player.play()

func _on_tactical_mode_changed(_is_tactical: bool) -> void:
	pass  ## Nothing to re-evaluate mid-drag the way BuildPlacementController's ghost does — a drag started in Tactical simply can't begin outside it (_begin_drag's own gate), and zooming out mid-drag is an edge case not worth special-casing for a first pass.

func _is_tactical_zoom() -> bool:
	return _camera == null or _camera.is_tactical_zoom()
