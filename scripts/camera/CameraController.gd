class_name CameraController
extends Camera2D

## Top-down camera: WASD/arrow pan, mouse-wheel zoom, middle-drag, edge pan.
##
## Had a second perspective until 2026-09-15: a Tab-toggled fake isometric
## view that rotated `world_root` 45° and squashed Y. Removed on the user's
## decision to go "entirely top down" — the art is now authored for a
## straight-down camera (render_common.CATEGORY_ELEVATION_DEG is 90 for every
## category drawn on the map), so rotating the world under it would shear
## sprites that already contain their own projection. There is no world_root
## NodePath any more for the same reason: nothing transforms the world.
##
## Also owns the Strategic <-> Tactical zoom threshold: a hard cut, at
## `tactical_zoom_threshold` — no separate "battle map" scene, just this
## camera's own zoom value crossing a line. LocalDetailManager listens to
## `tactical_mode_changed` rather than polling zoom every frame.
##
## Godot's Camera2D.zoom is a MAGNIFICATION factor — LARGER zoom.x shows
## LESS of the world (zoomed in/close), SMALLER zoom.x shows MORE of it
## (zoomed out/wide): Camera2D.get_canvas_transform() confirms
## visible_world_width == viewport_width / zoom.x, not viewport_width *
## zoom.x. min_zoom/max_zoom's VALUES (0.03/2.5 originally) were correct on
## the axis they describe — only the wheel-direction mapping and
## tactical_zoom_threshold's comparison needed to move to the other side of
## the default zoom.
##
## `max_zoom` was raised twice from its original 0.3125: first 19.2x to
## 6.0 so a UnitInstance figure (TacticalEntityLayer.FIGURE_RADIUS = 6.0
## world units), which rendered at a 1.875px sub-pixel smear at the old
## value, reads at a legible ~36px screen radius at closest zoom — chosen
## by working backward from "a 6-unit figure should read as a clear ~70px
## circle at closest zoom," a usability floor, not an aesthetic preference.
## Then doubled again to 12.0 per user feedback ("we should be able to zoom
## in further too") — screen radius is world_radius * zoom.x, so the same
## figure now reads at a 72px radius, roomier than the floor called for,
## deliberately. medium_fidelity_threshold/high_fidelity_threshold below
## are untouched by this second change — it only extends how much further
## HIGH fidelity's own range goes.
##
## `zoom_step` was replaced by `zoom_factor_per_step` (additive ->
## multiplicative): the old flat +/-0.0125 per scroll click needed ~465
## clicks to cross the original Tactical range, and with max_zoom now 19x
## further out a flat step is either too slow near the top of the range or
## too coarse near the bottom. A percentage-per-click step (12%) handles a
## wide dynamic range gracefully (the same reason Google Maps/most
## strategy games zoom multiplicatively) — the full min_zoom..max_zoom span
## takes ~65 clicks, tactical_zoom_threshold..max_zoom takes ~31.

## This is the world-units/sec pan rate AT zoom.x == 1.0, not a raw
## multiplier — picked so panning at the default starting Strategic zoom
## (Main.tscn's zoom = 0.05) feels identical to before the pan-speed
## formula changed from multiply-by-zoom.x to divide-by-zoom.x (see
## _handle_pan_input()'s own comment for why the old formula would have
## made panning catastrophically twitchy at the deeper max_zoom).
@export var pan_speed: float = 220.0
@export var min_zoom: float = 0.00375  ## The most zoomed-OUT allowed value. Visible world width is viewport/zoom.x, so a bigger world needs a SMALLER zoom value to keep framing the same fraction of it — see tactical_zoom_threshold.
@export var max_zoom: float = 12.0  ## The most zoomed-IN allowed value — see this class's own doc comment for the two raises that got it here.
@export var zoom_factor_per_step: float = 1.12  ## Multiplicative zoom per scroll click (12%) — see this class's own doc comment for why this replaced a flat additive zoom_step.
@export var tactical_zoom_threshold: float = 0.1875  ## zoom.x at/above this = Tactical view (LARGER zoom = more zoomed in). Unchanged by the max_zoom increases — this still marks "left the abstract Strategic map", independent of how much further Tactical itself now goes.

## Subdivides [tactical_zoom_threshold, max_zoom] into three LOW/MEDIUM/HIGH
## fidelity bands (GameEnums.TacticalFidelity) as the camera zooms in past
## the Strategic/Tactical cut — see get_tactical_fidelity(). HIGH starts
## where individual figures are already a legible ~18px screen radius
## (FIGURE_RADIUS 6.0 * 2.0) and only gets clearer approaching max_zoom,
## rather than starting the instant Tactical mode itself does. A
## balancing/feel pass, not an architecture decision.
@export var medium_fidelity_threshold: float = 0.5
@export var high_fidelity_threshold: float = 2.0

## Pan the camera when the mouse sits at/near the screen edge, RTS-
## convention style, on top of (not instead of) keyboard pan and
## middle-mouse drag. Only the outer edge_pan_margin_px strip actually pans.
@export var edge_pan_enabled: bool = true
@export var edge_pan_margin_px: float = 10.0  ## Screen pixels from the viewport edge before edge-pan kicks in.

signal tactical_mode_changed(is_tactical: bool)
signal tactical_fidelity_changed(fidelity: GameEnums.TacticalFidelity)  ## Fires on every LOW<->MEDIUM<->HIGH band crossing, independent of tactical_mode_changed (which only fires on the Strategic/Tactical cut itself).

var _middle_dragging: bool = false

func _ready() -> void:
	InputBindings.register_defaults()
	make_current()
	tactical_mode_changed.emit(is_tactical_zoom())  ## Sync any listener already wired up to our starting zoom.
	tactical_fidelity_changed.emit(get_tactical_fidelity())  ## Same "sync on ready" reasoning.

func is_tactical_zoom() -> bool:
	return zoom.x >= tactical_zoom_threshold

## See GameEnums.TacticalFidelity's own doc comment for why this is
## meaningless (always reports LOW) while not actually in Tactical zoom;
## every real consumer already checks is_tactical_zoom() first.
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
	_handle_edge_pan_input(pan_delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_handle_middle_mouse(event)
	elif event is InputEventMouseMotion:
		_handle_middle_drag(event)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_zoom_input(event)

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
		# Constant SCREEN-space pan speed, independent of zoom level:
		# visible world width is viewport/zoom.x, so dividing by zoom.x
		# here means the fraction of the visible view crossed per second
		# stays the same at any zoom. The OLD formula (pan_speed*zoom.x)
		# made world-space speed scale UP with zoom — harmless at the old,
		# narrow max_zoom, but with max_zoom now 19x further in, that
		# formula would make panning ~369x more twitchy at max zoom than
		# at the default view — exactly the fine control close-up unit
		# inspection needs. pan_speed itself was recalibrated so this
		# reads identically to the old formula at the default starting
		# Strategic zoom.
		position += direction.normalized() * (pan_speed / zoom.x) * delta

## Pans toward whichever edge(s) the mouse is within edge_pan_margin_px of.
## Uses the same screen-space-constant pan_speed/zoom.x formula
## _handle_pan_input() uses, so it feels identical in speed to keyboard
## panning at any zoom level. Skipped entirely while middle-mouse-dragging
## (that gesture already IS an explicit "move the camera" input) or while
## the game window doesn't have focus (Godot keeps reporting the last
## known mouse position after alt-tab/focus-loss, which would otherwise
## silently keep panning the camera in the background).
func _handle_edge_pan_input(delta: float) -> void:
	if not edge_pan_enabled or _middle_dragging:
		return
	var window := get_window()
	if window and not window.has_focus():
		return
	var viewport := get_viewport()
	var mouse_pos := viewport.get_mouse_position()
	var size := viewport.get_visible_rect().size
	# Mouse has actually left the window (can happen mid-drag on some
	# platforms) — don't treat that as "at the edge".
	if mouse_pos.x < 0.0 or mouse_pos.y < 0.0 or mouse_pos.x > size.x or mouse_pos.y > size.y:
		return
	var direction := Vector2.ZERO
	if mouse_pos.x <= edge_pan_margin_px:
		direction.x -= 1.0
	elif mouse_pos.x >= size.x - edge_pan_margin_px:
		direction.x += 1.0
	if mouse_pos.y <= edge_pan_margin_px:
		direction.y -= 1.0
	elif mouse_pos.y >= size.y - edge_pan_margin_px:
		direction.y += 1.0
	if direction != Vector2.ZERO:
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
		_apply_zoom_factor(zoom_factor_per_step)  ## Scroll up = zoom in = larger zoom.x.
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_apply_zoom_factor(1.0 / zoom_factor_per_step)

## Multiplicative, not additive — see this class's own doc comment on
## zoom_factor_per_step for why a flat step doesn't work across a range
## this wide.
func _apply_zoom_factor(factor: float) -> void:
	set_zoom_level(zoom.x * factor)

## The single place a zoom change is applied: clamps to [min_zoom, max_zoom]
## and emits tactical_mode_changed/tactical_fidelity_changed on a threshold
## crossing.
##
## Public, because assigning `zoom` directly does NEITHER of those, and until
## this existed the only route to a zoom change was a real mouse-wheel event.
## Anything driving the camera without a wheel — the preview/screenshot
## harnesses in scripts/test/, AgentHarness — therefore had to either
## synthesise scroll events (AgentHarness does, which is why crossing
## tactical_zoom_threshold there takes tens of simulated clicks) or poke
## `zoom` and silently skip the signals. Skipping them is not cosmetic:
## LocalDetailManager hydrates a hex's props/buildings off
## tactical_mode_changed and TacticalEntityLayer swaps figure fidelity off
## tactical_fidelity_changed, so a harness that set `zoom` by hand
## photographed terrain with neither applied and no error anywhere.
func set_zoom_level(value: float) -> void:
	var was_tactical := is_tactical_zoom()
	var was_fidelity := get_tactical_fidelity()
	var new_zoom := clampf(value, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)
	if is_tactical_zoom() != was_tactical:
		tactical_mode_changed.emit(is_tactical_zoom())
	if get_tactical_fidelity() != was_fidelity:
		tactical_fidelity_changed.emit(get_tactical_fidelity())
