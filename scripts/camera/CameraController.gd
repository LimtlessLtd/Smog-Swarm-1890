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
@export var pan_speed: float = 800.0
@export var min_zoom: float = 0.03  ## The most zoomed-OUT allowed value (smallest zoom.x = largest visible area) — see tactical_zoom_threshold.
@export var max_zoom: float = 2.5  ## The most zoomed-IN allowed value — low enough to fill the screen with roughly one hex's ~5x5 mile footprint at HEX_SIZE's original placeholder scale.
@export var zoom_step: float = 0.1
@export var tactical_zoom_threshold: float = 1.5  ## zoom.x at/above this = Tactical view (Camera2D: LARGER zoom = more zoomed in — see the class doc comment).
@export var perspective_tween_duration: float = 0.6
@export var isometric_y_scale: float = 0.577
@export var isometric_rotation_degrees: float = 45.0

signal tactical_mode_changed(is_tactical: bool)

var perspective: GameEnums.CameraPerspective = GameEnums.CameraPerspective.TOP_DOWN

var _world_root: Node2D
var _perspective_tween: Tween

func _ready() -> void:
	InputBindings.register_defaults()
	if world_root_path != NodePath():
		_world_root = get_node(world_root_path)
	make_current()
	tactical_mode_changed.emit(is_tactical_zoom())  ## Sync any listener already wired up to our starting zoom.

func is_tactical_zoom() -> bool:
	return zoom.x >= tactical_zoom_threshold

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
	var new_zoom := clampf(zoom.x + delta, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)
	if is_tactical_zoom() != was_tactical:
		tactical_mode_changed.emit(is_tactical_zoom())
