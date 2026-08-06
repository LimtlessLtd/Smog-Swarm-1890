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

@export var world_root_path: NodePath
@export var pan_speed: float = 800.0
@export var min_zoom: float = 0.03  ## Low enough to fill the screen with roughly one hex's ~5x5 mile footprint — see tactical_zoom_threshold.
@export var max_zoom: float = 2.5
@export var zoom_step: float = 0.1
@export var tactical_zoom_threshold: float = 0.12  ## zoom.x at/below this = Tactical view (Camera2D: smaller zoom = more zoomed in).
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
	return zoom.x <= tactical_zoom_threshold

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
		position += direction.normalized() * pan_speed * zoom.x * delta

func _handle_zoom_input(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_apply_zoom_delta(-zoom_step)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_apply_zoom_delta(zoom_step)

func _apply_zoom_delta(delta: float) -> void:
	var was_tactical := is_tactical_zoom()
	var new_zoom := clampf(zoom.x + delta, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)
	if is_tactical_zoom() != was_tactical:
		tactical_mode_changed.emit(is_tactical_zoom())
