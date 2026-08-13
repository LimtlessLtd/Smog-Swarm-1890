class_name WallPlacementController
extends Node2D

## Turns a wall-tier selection into an actual drawn wall — the missing link
## this project never had at all: WallManager.place_wall_line() (née
## place_segment()) existed but nothing in the UI/input layer ever called
## it. Confirmed directly, not assumed: a project-wide grep found ZERO call
## sites for wall placement anywhere outside WallManager's own
## seed_starting_defenses() — every wall segment a player has ever seen in
## this game was the free starting perimeter, never something they placed
## themselves. Player report ("walls are not free hand to place/draw")
## presupposed a placement mechanism that just didn't exist yet, not
## merely a hex-locked one.
##
## Mirrors BuildPlacementController's own shape (arm a type, ghost preview,
## Tactical-zoom-only, right-click/Esc to cancel).
##
## Click-click chain, replacing an original press-drag-release model:
## left-click sets an anchor point; every subsequent mouse motion updates a
## live preview (rendered with the real tileable wall texture — see
## _update_preview()'s own doc comment — not just a flat color line); the
## next left-click commits that segment via WallManager.place_wall_line()
## AND becomes the anchor for the next one automatically (no re-click/
## Shift-hold needed to keep chaining); only a right-click (or Esc) exits
## placement mode entirely. New endpoints snap to any nearby EXISTING wall
## endpoint (closes accidental sub-pixel gaps a zombie could otherwise
## squeeze through) unless Alt is held, which disables snapping for as
## long as it's held; an on-screen hint reflects the live snap state so
## the player always knows which mode they're in.
##
## Parented as a HexGridMap/BuildPlacementController sibling under
## WorldRoot, same coordinate-space reasoning as that class's own doc
## comment.

signal placement_started(tier: int)
signal placement_ended

const _VALID_COLOR := Color(0.20, 0.75, 0.30, 0.9)
const _BLOCKED_COLOR := Color(0.80, 0.20, 0.15, 0.9)
## Multiplicative tints applied to the preview's `modulate` when a real wall
## texture is in play (default_color stays plain white so the art's own
## colors show through — same reasoning WallVisuals._apply_wall_segment_look()
## already documents) — a green/red boost above 1.0 on the relevant channel,
## same "modulate brightens rather than just recolors" convention
## TacticalHexView._SELECTED_TINT already established, so validity still
## reads at a glance without hiding the texture underneath it.
const _VALID_TINT := Color(0.75, 1.35, 0.75, 0.85)
const _BLOCKED_TINT := Color(1.35, 0.65, 0.6, 0.85)
const _PREVIEW_WIDTH := 6.0
## User request ("building new walls should snap to already existing walls
## so theres no unseen tiny gaps that zombies can get through") — world-unit
## radius a click/preview endpoint snaps to the nearest existing wall
## endpoint within. Roughly one wall piece's own length
## (WallCatalog.MAX_SEGMENT_LENGTH_WORLD_UNITS, ~10.26) — close enough to
## catch "the player meant this same corner" without reaching across an
## unrelated nearby stretch of wall.
const _SNAP_RADIUS: float = 10.0

@export var hex_grid_map_path: NodePath
@export var wall_manager_path: NodePath
@export var camera_path: NodePath  ## Optional — see BuildPlacementController's own doc comment on this same fallback.

var _hex_grid_map: HexGridMap
var _wall_manager: WallManager
var _camera: CameraController

var _is_placing: bool = false
## Precedent kept intact (WallManager.place_segment()'s own old
## doc comment: "Every fresh segment starts at Wooden tier... upgrade_segment()
## is the only way to advance it from there") — fresh placement stays
## Wooden-only, same as before this rework; place_wall_line() itself
## accepts any tier (internal reuse, e.g. a future seeded-at-tier scenario),
## this controller just never arms anything but Wooden from the UI.
var _pending_tier: int = WallCatalog.WOODEN
var _pending_is_gate: bool = false
## True once the first click of a chain has landed and every further click
## commits a segment ending there — see this class's own doc comment for the
## click-click chain model this replaced press-drag-release with.
var _has_anchor: bool = false
var _anchor_point: Vector2 = Vector2.ZERO

var _preview_line: Line2D
var _reject_player: AudioStreamPlayer
var _hint_layer: CanvasLayer
var _hint_label: Label

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

	# User request (item 5 — "make the user aware of this via on screen
	# text"): a CanvasLayer renders in screen space regardless of this node's
	# own 2D world transform, so a simple bottom-centered Label works without
	# routing through MainHUD at all.
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

func _process(_delta: float) -> void:
	if not _is_placing:
		return
	var snap_on := not Input.is_key_pressed(KEY_ALT)
	_hint_label.text = "Placing wall — click to place, right-click (or Esc) to finish.  Snap-to-wall: %s (hold Alt to disable)" % ("ON" if snap_on else "OFF")

func is_placing() -> bool:
	return _is_placing

func begin_placement(is_gate: bool = false) -> void:
	_is_placing = true
	_pending_tier = WallCatalog.WOODEN
	_pending_is_gate = is_gate
	_has_anchor = false
	_preview_line.visible = false
	_hint_label.visible = true
	placement_started.emit(_pending_tier)

func cancel_placement() -> void:
	if not _is_placing:
		return
	_is_placing = false
	_has_anchor = false
	_preview_line.visible = false
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
			# User request (item 4): right-click always exits placement mode
			# entirely, whether or not a chain is in progress — no separate
			# "cancel this segment but stay armed" step.
			cancel_placement()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		cancel_placement()

## First click of a chain sets the anchor; every click after that commits a
## segment from the current anchor to this (snapped) point and re-anchors
## there — see this class's own doc comment for the full click-click chain
## model (items 4/5 of the playtest report this rework addresses).
func _on_left_click(world_pos: Vector2) -> void:
	if not _is_tactical_zoom():
		_reject_player.play()  # Same "inert, not silently ignored" convention as BuildPlacementController's own zoom gate.
		return
	var snapped_pos := _apply_snap(world_pos)
	if not _has_anchor:
		_anchor_point = snapped_pos
		_has_anchor = true
		_preview_line.visible = true
		_update_preview(snapped_pos)
		return
	if not _wall_manager:
		return
	var placed := _wall_manager.place_wall_line(_anchor_point, snapped_pos, _pending_tier, _pending_is_gate)
	if placed.is_empty():
		_reject_player.play()  # WallManager already emitted placement_rejected per failed piece, which _on_placement_rejected also plays this for — harmless double-play, avoids a silent "nothing happened" when EVERY piece failed (e.g. the whole segment landed on impassable ground).
		return  # Keep the same anchor — let the player retry a different endpoint rather than silently advancing past a rejected placement.
	_anchor_point = snapped_pos
	_update_preview(snapped_pos)

## User request (item 3 — "you should be able to see the wall texture and
## what it will look like while dragging the mouse around"): the preview now
## renders with WallVisuals.tier_texture()/apply_line_geometry(), the exact
## same real-art path a placed wall uses (see WallVisuals.UV_SCALE's own doc
## comment for why that geometry helper exists at all), tinted green/red via
## `modulate` on top rather than replacing the texture with a flat color —
## the player sees the actual material AND whether this placement is valid
## in one glance. Falls back to the old flat color line (no art authored/
## found) exactly as before.
func _update_preview(raw_end_pos: Vector2) -> void:
	var end_pos := _apply_snap(raw_end_pos)
	var can_place := _wall_manager != null and _wall_manager.can_place_wall_piece(_anchor_point, end_pos, _pending_tier)
	var texture := WallVisuals.tier_texture(_pending_tier)
	_preview_line.texture = texture
	_preview_line.texture_mode = Line2D.LINE_TEXTURE_TILE
	_preview_line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	WallVisuals.apply_line_geometry(_preview_line, _anchor_point, end_pos, WallVisuals.line_width(_pending_tier, false) * WallVisuals.TACTICAL_WIDTH_SCALE)
	if texture:
		_preview_line.default_color = Color.WHITE
		_preview_line.modulate = _VALID_TINT if can_place else _BLOCKED_TINT
	else:
		_preview_line.default_color = _VALID_COLOR if can_place else _BLOCKED_COLOR
		_preview_line.modulate = Color(1.0, 1.0, 1.0, 1.0)

## User request (item 5): snaps to the nearest existing wall segment
## ENDPOINT within _SNAP_RADIUS, unless Alt is currently held (checked live,
## not latched — matches "holding alt should disable the snap mechanic only
## while the user is holding the alt key"). Linear scan over every placed
## segment's two endpoints — cheap enough at this project's wall-piece
## counts (each piece capped at ~10 world units, so even a long perimeter is
## a few hundred segments, not thousands) to run every mouse-motion event
## without needing a spatial index.
func _apply_snap(pos: Vector2) -> Vector2:
	if Input.is_key_pressed(KEY_ALT) or not _wall_manager:
		return pos
	var closest := pos
	var closest_dist := _SNAP_RADIUS
	for segment in _wall_manager.get_segments():
		for endpoint in [segment.point_a, segment.point_b]:
			var dist: float = pos.distance_to(endpoint)
			if dist < closest_dist:
				closest_dist = dist
				closest = endpoint
	return closest

func _on_placement_rejected(_hex_a: Vector2i, _hex_b: Vector2i, _reason: String) -> void:
	_reject_player.play()

func _on_tactical_mode_changed(_is_tactical: bool) -> void:
	pass  ## Nothing to re-evaluate mid-chain the way BuildPlacementController's ghost does — a chain started in Tactical simply can't continue outside it (_on_left_click's own gate re-checks every click, not just the first), and zooming out mid-chain is an edge case not worth special-casing for a first pass.

func _is_tactical_zoom() -> bool:
	return _camera == null or _camera.is_tactical_zoom()
