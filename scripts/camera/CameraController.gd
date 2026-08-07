class_name CameraController
extends Camera2D

## Dual-perspective camera: WASD/arrow pan, mouse-wheel zoom, and a smooth
## tween between TOP_DOWN and a faked 2D ISOMETRIC view. The camera itself
## never moves the world's actual content — it tweens `world_root`'s
## scale/rotation (a classic 2D fake-isometric technique: rotate 45° and
## squash Y) while the camera keeps panning/zooming normally on top of it.
## Swap this projection trick for true isometric art direction later without
## touching pan/zoom or any other system.
##
## Also owns the Strategic <-> Tactical zoom threshold (Phase 2.5): a hard
## cut, Total-War-campaign-map-style, at `tactical_zoom_threshold` — no
## separate "battle map" scene, just this camera's own zoom value crossing a
## line. LocalDetailManager listens to `tactical_mode_changed` rather than
## polling zoom every frame.
##
## Zoom-direction bug fix (found while implementing Phase 2.5.6): Godot's
## Camera2D.zoom is a MAGNIFICATION factor — LARGER zoom.x shows LESS of the
## world (zoomed in/close), SMALLER zoom.x shows MORE of it (zoomed out/wide).
## Verified empirically against a real windowed build via
## Camera2D.get_canvas_transform() (visible_world_width == viewport_width /
## zoom.x, not viewport_width * zoom.x). Every constant/comparison below was
## previously written assuming the opposite, which meant "Tactical" used to
## trigger when zooming OUT past a point (not in), and mouse-wheel-up used to
## zoom out instead of in — mechanically consistent (the threshold-crossing
## itself still worked, LocalDetailManager only cares about that), but
## backwards from how it reads and from normal scroll-to-zoom convention.
## min_zoom/max_zoom's VALUES were fine (0.03 genuinely is the widest, most
## zoomed-out bound; 2.5 genuinely is the closest, most zoomed-in bound) —
## only the wheel-direction mapping and tactical_zoom_threshold's comparison
## + value needed to move to the other side of the default zoom.

@export var world_root_path: NodePath
@export var pan_speed: float = 51200.0  ## Phase 2.5.6: scaled by 8x^2 = 64x alongside HexCoord.HEX_SIZE's 8x increase (800 -> 51,200). Effective world-space pan speed is pan_speed*zoom.x, and since visible width is viewport/zoom.x, the zoom bounds below had to shrink by the same 8x factor HEX_SIZE grew by, which on its own would have made panning feel 8x SLOWER relative to hex size; squaring the correction here (8x for the bigger world, another 8x to cancel the shrunk zoom.x) keeps "seconds to cross one hex while panning" exactly unchanged.
@export var min_zoom: float = 0.00375  ## The most zoomed-OUT allowed value. Phase 2.5.6: scaled by 1/8 alongside HexCoord.HEX_SIZE's 8x increase (0.03 -> 0.00375) — visible world width is viewport/zoom.x, so a bigger world needs a SMALLER zoom value to keep framing the same fraction of it — see tactical_zoom_threshold.
@export var max_zoom: float = 0.3125  ## The most zoomed-IN allowed value. Phase 2.5.6: scaled by 1/8 alongside HexCoord.HEX_SIZE's 8x increase (2.5 -> 0.3125) — same viewport/zoom.x reasoning as min_zoom, so full zoom-in still frames the same fraction of a hex as before the world-space scale-up.
@export var zoom_step: float = 0.0125  ## Phase 2.5.6: scaled by 1/8 alongside HexCoord.HEX_SIZE's 8x increase (0.1 -> 0.0125) so one scroll click still feels like the same proportional zoom change.
@export var tactical_zoom_threshold: float = 0.1875  ## zoom.x at/above this = Tactical view (Camera2D: LARGER zoom = more zoomed in — see the class doc comment). Phase 2.5.6: scaled by 1/8 alongside HexCoord.HEX_SIZE's 8x increase (1.5 -> 0.1875) — the Strategic/Tactical cut still happens at the same relative zoom level.

## Phase 2.5.5: subdivides [tactical_zoom_threshold, max_zoom] into three
## LOW/MEDIUM/HIGH fidelity bands (GameEnums.TacticalFidelity) as the camera
## keeps zooming in past the Strategic/Tactical cut — see get_tactical_fidelity().
## Evenly divides the range into thirds; exact values are a balancing/feel
## pass once this is actually running in-engine, per the design doc, not an
## architecture decision — same framing as tactical_zoom_threshold's own
## position was before 2.5.6 fixed its direction.
@export var medium_fidelity_threshold: float = 0.2292
@export var high_fidelity_threshold: float = 0.2708

@export var perspective_tween_duration: float = 0.6
@export var isometric_y_scale: float = 0.577
@export var isometric_rotation_degrees: float = 45.0

signal tactical_mode_changed(is_tactical: bool)
signal tactical_fidelity_changed(fidelity: GameEnums.TacticalFidelity)  ## Phase 2.5.5 — fires on every LOW<->MEDIUM<->HIGH band crossing, independent of tactical_mode_changed (which only fires on the Strategic/Tactical cut itself).

var perspective: GameEnums.CameraPerspective = GameEnums.CameraPerspective.TOP_DOWN

var _world_root: Node2D
var _perspective_tween: Tween

func _ready() -> void:
	InputBindings.register_defaults()
	if world_root_path != NodePath():
		_world_root = get_node(world_root_path)
	make_current()
	tactical_mode_changed.emit(is_tactical_zoom())  ## Sync any listener already wired up to our starting zoom.
	tactical_fidelity_changed.emit(get_tactical_fidelity())  ## Phase 2.5.5 — same "sync on ready" reasoning.

func is_tactical_zoom() -> bool:
	return zoom.x >= tactical_zoom_threshold

## Phase 2.5.5 — see GameEnums.TacticalFidelity's own doc comment for why
## this is meaningless (always reports LOW) while not actually in Tactical
## zoom; every real consumer already checks is_tactical_zoom() first.
func get_tactical_fidelity() -> GameEnums.TacticalFidelity:
	if zoom.x >= high_fidelity_threshold:
		return GameEnums.TacticalFidelity.HIGH
	if zoom.x >= medium_fidelity_threshold:
		return GameEnums.TacticalFidelity.MEDIUM
	return GameEnums.TacticalFidelity.LOW

func _process(delta: float) -> void:
	_handle_pan_input(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_zoom_input(event)
	elif event.is_action_pressed(InputBindings.TOGGLE_PERSPECTIVE):
		toggle_perspective()

func toggle_perspective() -> void:
	var next := GameEnums.CameraPerspective.ISOMETRIC if perspective == GameEnums.CameraPerspective.TOP_DOWN else GameEnums.CameraPerspective.TOP_DOWN
	set_perspective(next)

func set_perspective(p_perspective: GameEnums.CameraPerspective) -> void:
	if perspective == p_perspective:
		return
	perspective = p_perspective

	if not _world_root:
		push_warning("CameraController: world_root_path is not set; perspective toggle has no visual effect.")
		return

	var target_scale := Vector2.ONE
	var target_rotation := 0.0
	if perspective == GameEnums.CameraPerspective.ISOMETRIC:
		target_scale = Vector2(1.0, isometric_y_scale)
		target_rotation = deg_to_rad(isometric_rotation_degrees)

	if _perspective_tween and _perspective_tween.is_valid():
		_perspective_tween.kill()
	_perspective_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_perspective_tween.tween_property(_world_root, "scale", target_scale, perspective_tween_duration)
	_perspective_tween.tween_property(_world_root, "rotation", target_rotation, perspective_tween_duration)

func _handle_pan_input(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_action_pressed(InputBindings.PAN_LEFT):
		direction.x -= 1.0
	if Input.is_action_pressed(InputBindings.PAN_RIGHT):
		direction.x += 1.0
	if Input.is_action_pressed(InputBindings.PAN_UP):
		direction.y -= 1.0
	if Input.is_action_pressed(InputBindings.PAN_DOWN):
		direction.y += 1.0
	if direction != Vector2.ZERO:
		# NOTE: this makes world-space pan speed scale UP with zoom.x, i.e.
		# panning covers MORE world-units/sec the more zoomed in you are —
		# not perfectly zoom-independent screen-space pan speed (that would
		# need pan_speed/zoom.x instead, given visible width is viewport/
		# zoom.x — see the class doc comment on the zoom-direction fix).
		# Left as-is: a feel/balancing nuance, not a broken-direction bug
		# like the two above were; revisit if panning feels off once zoomed
		# in deep during actual playtesting.
		position += direction.normalized() * pan_speed * zoom.x * delta

func _handle_zoom_input(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_apply_zoom_delta(zoom_step)  ## Scroll up = zoom in = larger zoom.x (see class doc comment).
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_apply_zoom_delta(-zoom_step)

func _apply_zoom_delta(delta: float) -> void:
	var was_tactical := is_tactical_zoom()
	var was_fidelity := get_tactical_fidelity()
	var new_zoom := clampf(zoom.x + delta, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)
	if is_tactical_zoom() != was_tactical:
		tactical_mode_changed.emit(is_tactical_zoom())
	if get_tactical_fidelity() != was_fidelity:
		tactical_fidelity_changed.emit(get_tactical_fidelity())
