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
##
## **max_zoom raised 19.2x (0.3125 -> 6.0), found while playing: the whole
## point of Phase 2.5.4's individual-figure rendering and Phase 2.5.6's
## true-scale in-hex space was to zoom in on a real 5x5-mile hex and see
## individual soldiers/zombies — but the camera's own max_zoom never
## actually got pushed far enough to make that possible. A UnitInstance
## figure (TacticalEntityLayer.FIGURE_RADIUS = 6.0 world units) at the OLD
## max_zoom (0.3125) rendered at a 1.875px screen radius — a sub-pixel
## smear, not a soldier. At the new max_zoom, the same figure renders at a
## 36px screen radius (72px across) — genuinely legible. Chosen by working
## backward from "a 6-unit figure should read as a clear ~70px circle at
## closest zoom", not by proportionally scaling the old value — this is a
## real usability floor, not an aesthetic preference.
##
## **max_zoom doubled again (6.0 -> 12.0), user request ("we should be able
## to zoom in further too").** Screen radius is `world_radius * zoom.x`
## (Camera2D magnification, see the zoom-direction note above) — the same
## 6-unit figure now reads as a 72px radius (144px across) at closest zoom,
## roomier than the original usability floor called for, deliberately (the
## floor above was the MINIMUM needed for legibility, not a ceiling on how
## close the player should ever be able to get). `medium_fidelity_threshold`/
## `high_fidelity_threshold` below are untouched — this only extends how
## much further HIGH fidelity's own range now goes, it doesn't move where
## LOW/MEDIUM/HIGH themselves start.
##
## **zoom_step replaced by zoom_factor_per_step (additive -> multiplicative)**:
## the old flat +/-0.0125 per scroll click would need ~465 clicks to cross
## just the (old) Tactical range, and with max_zoom now 19x further out,
## a flat step is hopeless — either far too slow near the top of the range
## or far too coarse near the bottom. A percentage-per-click step (12%)
## handles a huge dynamic range gracefully (this is why Google Maps/most
## strategy games zoom multiplicatively, not additively) — the full
## min_zoom..max_zoom span takes ~65 clicks, tactical_zoom_threshold..
## max_zoom takes ~31, both reasonable scroll counts regardless of how
## wide the underlying range is.

@export var world_root_path: NodePath
## Phase 2.5.6: scaled by 8x^2 = 64x alongside HexCoord.HEX_SIZE's 8x
## increase (800 -> 51,200 at the time). **Recalibrated again (51,200 ->
## 128) alongside the pan-speed FORMULA change below** (multiply-by-zoom.x
## -> divide-by-zoom.x) — this is now the world-units/sec pan rate AT
## zoom.x == 1.0, not a raw multiplier; picked so panning at the default
## starting Strategic zoom (Main.tscn's zoom = 0.05) feels identical to
## before this change (both formulas agree at that one zoom level by
## construction), while every OTHER zoom level now pans at a genuinely
## constant on-screen (not world-space) rate — see _handle_pan_input()'s
## own comment for why the old formula would have made panning catastrophically
## twitchy at the new, much deeper max_zoom.
@export var pan_speed: float = 220.0
@export var min_zoom: float = 0.00375  ## The most zoomed-OUT allowed value. Phase 2.5.6: scaled by 1/8 alongside HexCoord.HEX_SIZE's 8x increase (0.03 -> 0.00375) — visible world width is viewport/zoom.x, so a bigger world needs a SMALLER zoom value to keep framing the same fraction of it — see tactical_zoom_threshold.
@export var max_zoom: float = 12.0  ## The most zoomed-IN allowed value — see this class's own doc comment for the two separate reasons this has been raised: first 19.2x (0.3125 -> 6.0) so individual figures aren't sub-pixel, then doubled again (6.0 -> 12.0) per direct user request for more zoom headroom.
@export var zoom_factor_per_step: float = 1.12  ## Multiplicative zoom per scroll click (12%) — see this class's own doc comment for why this replaced a flat additive zoom_step.
@export var tactical_zoom_threshold: float = 0.1875  ## zoom.x at/above this = Tactical view (Camera2D: LARGER zoom = more zoomed in — see the class doc comment). Phase 2.5.6: scaled by 1/8 alongside HexCoord.HEX_SIZE's 8x increase (1.5 -> 0.1875) — the Strategic/Tactical cut still happens at the same relative zoom level. Unchanged by the max_zoom increase — this still marks "left the abstract Strategic map", independent of how much further Tactical itself now goes.

## Phase 2.5.5: subdivides [tactical_zoom_threshold, max_zoom] into three
## LOW/MEDIUM/HIGH fidelity bands (GameEnums.TacticalFidelity) as the camera
## keeps zooming in past the Strategic/Tactical cut — see get_tactical_fidelity().
## **Re-tuned alongside the max_zoom increase above** (were 0.2292/0.2708,
## an even three-way split of the OLD, much narrower Tactical range) —
## HIGH specifically now starts where individual figures are already a
## legible ~18px screen radius (FIGURE_RADIUS 6.0 * 2.0) and only gets
## clearer approaching max_zoom, rather than starting the instant Tactical
## mode itself does. Still a balancing/feel pass, not an architecture
## decision, same framing as before.
@export var medium_fidelity_threshold: float = 0.5
@export var high_fidelity_threshold: float = 2.0

@export var perspective_tween_duration: float = 0.6
@export var isometric_y_scale: float = 0.577
@export var isometric_rotation_degrees: float = 45.0

signal tactical_mode_changed(is_tactical: bool)
signal tactical_fidelity_changed(fidelity: GameEnums.TacticalFidelity)  ## Phase 2.5.5 — fires on every LOW<->MEDIUM<->HIGH band crossing, independent of tactical_mode_changed (which only fires on the Strategic/Tactical cut itself).

var perspective: GameEnums.CameraPerspective = GameEnums.CameraPerspective.TOP_DOWN

var _world_root: Node2D
var _perspective_tween: Tween
var _middle_dragging: bool = false

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
	var pan_delta := delta
	if Engine.time_scale != 0.0:
		pan_delta = delta / Engine.time_scale
	_handle_pan_input(pan_delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_handle_middle_mouse(event)
	elif event is InputEventMouseMotion:
		_handle_middle_drag(event)

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
		# Constant SCREEN-space pan speed, independent of zoom level: visible
		# world width is viewport/zoom.x (see the class doc comment on the
		# zoom-direction fix), so dividing by zoom.x here means the fraction
		# of the visible view crossed per second stays the same at any zoom.
		# The OLD formula (pan_speed*zoom.x) made world-space speed scale UP
		# with zoom — harmless at the old, narrow max_zoom, but with
		# max_zoom now 19x further in (see this class's own doc comment),
		# that formula would have made panning ~369x more twitchy at max
		# zoom than at the default view — exactly the fine control close-up
		# unit inspection needs. pan_speed itself was recalibrated (see its
		# own doc comment) so this reads identically to the old formula at
		# the default starting Strategic zoom.
		position += direction.normalized() * (pan_speed / zoom.x) * delta

func _handle_middle_mouse(event: InputEventMouseButton) -> void:
	_middle_dragging = event.pressed

func _handle_middle_drag(event: InputEventMouseMotion) -> void:
	if not _middle_dragging:
		return
	# Dragging the world by the middle mouse button should feel direct and
	# screen-space consistent across zoom levels.
	position -= event.relative / zoom.x

func _handle_zoom_input(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_apply_zoom_factor(zoom_factor_per_step)  ## Scroll up = zoom in = larger zoom.x (see class doc comment).
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_apply_zoom_factor(1.0 / zoom_factor_per_step)

## Multiplicative, not additive — see this class's own doc comment on
## zoom_factor_per_step for why a flat step doesn't work across a range
## this wide.
func _apply_zoom_factor(factor: float) -> void:
	var was_tactical := is_tactical_zoom()
	var was_fidelity := get_tactical_fidelity()
	var new_zoom := clampf(zoom.x * factor, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)
	if is_tactical_zoom() != was_tactical:
		tactical_mode_changed.emit(is_tactical_zoom())
	if get_tactical_fidelity() != was_fidelity:
		tactical_fidelity_changed.emit(get_tactical_fidelity())
