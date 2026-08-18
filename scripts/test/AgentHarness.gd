extends Node

## Remote-control surface for an automated playtester. Off unless the game
## is launched with `--agent-harness`; frees itself immediately otherwise,
## so a normal game never opens a socket.
##
## THE RULE THIS CLASS EXISTS TO ENFORCE: it may expose only what is
## actually rendered on screen, and nothing else. No ResourceManager, no
## HordeManager, no stockpile totals, no fog-hidden state, no NodePath to
## any gameplay system — this script has zero dependencies on purpose, and
## adding one would defeat the point. A playtester that can read the
## simulation directly reviews the DESIGN; one restricted to the screen
## reports the EXPERIENCE, which is the only thing worth measuring here.
## `labels`/`buttons` walk the live Control tree filtered to
## is_visible_in_tree() — that is OCR of the rendered frame, expressed as
## text, not a state query. If a number is not on screen, there is no
## command here that can obtain it.
##
## Input is synthesized through Input.parse_input_event() rather than
## called into any controller directly, so it travels the identical path a
## real mouse/keyboard takes (CameraController._input, TickManager and the
## four placement controllers' _unhandled_input). The game cannot
## distinguish these events from a human's, which is what makes a session
## here a playtest rather than a scripted API call.
##
## Protocol: line-delimited JSON over localhost TCP. One request, one
## response, no streaming — a synchronous request/response loop is what a
## turn-based observe/act agent actually needs, and it avoids the
## read-while-writing race a polled command file would have.

const PORT := 8899
const HOST := "127.0.0.1"
const ENABLE_FLAG := "--agent-harness"

var _server: TCPServer
var _client: StreamPeerTCP
var _buffer := ""

func _ready() -> void:
	if not OS.get_cmdline_args().has(ENABLE_FLAG):
		queue_free()
		return
	_server = TCPServer.new()
	var error := _server.listen(PORT, HOST)
	if error != OK:
		push_error("AgentHarness: could not listen on %s:%d (error %d)" % [HOST, PORT, error])
		queue_free()
		return
	print("[agent-harness] listening on %s:%d" % [HOST, PORT])

func _process(_delta: float) -> void:
	if not _server:
		return
	if _server.is_connection_available():
		_client = _server.take_connection()
		_buffer = ""
	if not _client or _client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var available := _client.get_available_bytes()
	if available > 0:
		_buffer += _client.get_utf8_string(available)
	# Commands are newline-delimited; a single read can deliver a partial
	# line or several whole ones, so drain every complete line and leave any
	# trailing fragment in the buffer.
	while _buffer.contains("\n"):
		var split := _buffer.split("\n", true, 1)
		var line := split[0].strip_edges()
		_buffer = split[1] if split.size() > 1 else ""
		if not line.is_empty():
			await _handle(line)

func _handle(line: String) -> void:
	var parsed: Variant = JSON.parse_string(line)
	if typeof(parsed) != TYPE_DICTIONARY:
		_respond({"ok": false, "error": "malformed JSON"})
		return
	var request: Dictionary = parsed
	var command := String(request.get("cmd", ""))
	match command:
		"screenshot":
			await _cmd_screenshot(request)
		"labels":
			_respond({"ok": true, "labels": _visible_text()})
		"buttons":
			_respond({"ok": true, "buttons": _visible_buttons()})
		"click":
			_cmd_click(request)
		"hover":
			_cmd_hover(request)
		"drag":
			_cmd_drag(request)
		"wheel":
			await _cmd_wheel(request)
		"key":
			_cmd_key(request)
		"wait":
			await get_tree().create_timer(float(request.get("seconds", 1.0)), true, false, true).timeout
			_respond({"ok": true})
		"debug":
			_respond({
				"ok": true,
				"viewport_size": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
				"window_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
				"window_focused": DisplayServer.window_is_focused(),
				"mouse_viewport": [get_viewport().get_mouse_position().x, get_viewport().get_mouse_position().y],
				"stretch_transform": str(get_viewport().get_screen_transform()),
			})
		"quit":
			_respond({"ok": true})
			get_tree().quit()
		_:
			_respond({"ok": false, "error": "unknown cmd '%s'" % command})

func _respond(payload: Dictionary) -> void:
	if _client and _client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_client.put_data((JSON.stringify(payload) + "\n").to_utf8_buffer())

# --- observation -------------------------------------------------------

## Optional "rect": [x, y, w, h] crops before saving. Cropping is the normal
## case, not an optimization — a full frame costs far more per observation
## than a HUD strip, and most reads only need one region.
func _cmd_screenshot(request: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var rect: Variant = request.get("rect")
	if rect is Array and (rect as Array).size() == 4:
		var r: Array = rect
		var clamped := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])).intersection(
			Rect2i(0, 0, image.get_width(), image.get_height()))
		if clamped.size.x <= 0 or clamped.size.y <= 0:
			_respond({"ok": false, "error": "rect is outside the viewport"})
			return
		image = image.get_region(clamped)
	var path := String(request.get("path", ""))
	if path.is_empty():
		_respond({"ok": false, "error": "screenshot needs a path"})
		return
	var error := image.save_png(path)
	if error != OK:
		_respond({"ok": false, "error": "save_png failed (%d)" % error})
		return
	# viewport_size is reported alongside the image size because they differ
	# (the image is window pixels, click coordinates are viewport space).
	# Dividing an image pixel by `scale` converts it into a clickable point —
	# needed for map clicks, which are the one case with no `buttons` rect to
	# read the coordinate off instead.
	var viewport_size := get_viewport().get_visible_rect().size
	_respond({
		"ok": true,
		"path": path,
		"size": [image.get_width(), image.get_height()],
		"viewport_size": [viewport_size.x, viewport_size.y],
		"scale": get_viewport().get_screen_transform().get_scale().x,
	})

## Every rendered Label/RichTextLabel, with where it sits. This is what the
## player reads off the screen, delivered as text so an observation cycle
## costs a few hundred tokens instead of a full frame — the screenshot
## command stays for spatial and aesthetic judgment, which text can't carry.
func _visible_text() -> Array:
	var out: Array = []
	_walk(get_tree().root, func(control: Control) -> void:
		var text := ""
		if control is Label:
			text = (control as Label).text
		elif control is RichTextLabel:
			text = (control as RichTextLabel).get_parsed_text()
		if not text.strip_edges().is_empty():
			out.append({"text": text, "rect": _rect_of(control)}))
	return out

## Buttons carry `disabled` because a greyed-out button is visually obvious.
## They deliberately do NOT carry tooltip_text: a tooltip is only visible
## after hovering, so reading it without hovering would be information the
## player doesn't have. Use `hover` then `screenshot` to read one honestly.
func _visible_buttons() -> Array:
	var out: Array = []
	_walk(get_tree().root, func(control: Control) -> void:
		if control is BaseButton:
			var button: BaseButton = control
			var text := (button as Button).text if button is Button else ""
			out.append({
				"text": text,
				"rect": _rect_of(button),
				"disabled": button.disabled,
			}))
	return out

## Skips whole subtrees that aren't visible — an invisible parent's children
## are equally off-screen, and TechTreeView/SaveLoadView/InGameMenuView all
## sit in the tree permanently with visible=false, so descending into them
## would report panels the player isn't looking at.
func _walk(node: Node, collect: Callable) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Control and _on_screen(node as Control):
		collect.call(node as Control)
	for child in node.get_children():
		_walk(child, collect)

func _on_screen(control: Control) -> bool:
	var rect := control.get_global_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	return rect.intersects(get_viewport().get_visible_rect())

func _rect_of(control: Control) -> Array:
	var rect := control.get_global_rect()
	return [int(rect.position.x), int(rect.position.y), int(rect.size.x), int(rect.size.y)]

# --- input -------------------------------------------------------------

## COORDINATE CONVENTION: every x/y accepted by the input commands below is
## in VIEWPORT space, the same space `labels`/`buttons` report rects in, so a
## rect from `buttons` can be clicked without conversion.
##
## Injected events have to carry WINDOW-space positions instead: the root
## viewport applies the inverse of its stretch transform to every incoming
## event, so an event built in viewport space arrives divided by the stretch
## scale and lands somewhere else entirely. project.godot stretches a
## 1280x720 viewport over a 1920x1080 window (scale 1.5), which is exactly
## far enough off to miss every button. Viewport.warp_mouse(), by contrast,
## already takes viewport coordinates — the two need opposite treatment,
## which is why the conversion lives here rather than at the call sites.
func _to_window(at: Vector2) -> Vector2:
	return get_viewport().get_screen_transform() * at

const _BUTTON_INDICES := {
	"left": MOUSE_BUTTON_LEFT,
	"right": MOUSE_BUTTON_RIGHT,
	"middle": MOUSE_BUTTON_MIDDLE,
	"wheel_up": MOUSE_BUTTON_WHEEL_UP,
	"wheel_down": MOUSE_BUTTON_WHEEL_DOWN,
}

## Moves the cursor and emits a motion event before pressing, because a real
## mouse always arrives somewhere before it clicks. Measured, not assumed: a
## press+release with no preceding motion at the same coordinates does not
## activate a Button, while hover-then-click at those identical coordinates
## does. Two separate reasons to keep it, either sufficient on its own —
## CameraController's edge-pan and every placement controller's hover
## preview read the live cursor position, so warp_mouse() has to happen
## regardless.
##
## The frame between press and release is required too: both events are
## queued and flushed at frame start, so emitting them back-to-back can
## deliver them in a single flush, which is not a click any Button will
## report.
func _cmd_click(request: Dictionary) -> void:
	var at := Vector2(float(request.get("x", 0.0)), float(request.get("y", 0.0)))
	var index: int = _BUTTON_INDICES.get(String(request.get("button", "left")), MOUSE_BUTTON_LEFT)
	get_viewport().warp_mouse(at)
	var motion := InputEventMouseMotion.new()
	motion.position = _to_window(at)
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await get_tree().process_frame
	_emit_mouse(at, index, true)
	await get_tree().process_frame
	_emit_mouse(at, index, false)
	await get_tree().process_frame
	_respond({"ok": true})

func _cmd_hover(request: Dictionary) -> void:
	var at := Vector2(float(request.get("x", 0.0)), float(request.get("y", 0.0)))
	get_viewport().warp_mouse(at)
	var motion := InputEventMouseMotion.new()
	motion.position = _to_window(at)
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	_respond({"ok": true})

## Press, move, release as three separate events — a drag that teleports
## between press and release would miss any controller that tracks motion
## while held (wall/supply-line placement both drag out a run of segments).
func _cmd_drag(request: Dictionary) -> void:
	var from_raw: Array = request.get("from", [0, 0])
	var to_raw: Array = request.get("to", [0, 0])
	var from := Vector2(float(from_raw[0]), float(from_raw[1]))
	var to := Vector2(float(to_raw[0]), float(to_raw[1]))
	get_viewport().warp_mouse(from)
	_emit_mouse(from, MOUSE_BUTTON_LEFT, true)
	await get_tree().process_frame
	var steps := 8
	for step in range(1, steps + 1):
		var point := from.lerp(to, float(step) / float(steps))
		get_viewport().warp_mouse(point)
		var motion := InputEventMouseMotion.new()
		motion.position = _to_window(point)
		motion.global_position = motion.position
		motion.relative = _to_window(point) - _to_window(from.lerp(to, float(step - 1) / float(steps)))
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		await get_tree().process_frame
	_emit_mouse(to, MOUSE_BUTTON_LEFT, false)
	_respond({"ok": true})

## Zoom is mouse-wheel only — CameraController._handle_zoom_input() reads
## MOUSE_BUTTON_WHEEL_UP/DOWN and no input action is bound to it, so without
## this command an agent cannot reach Tactical view at all.
##
## `steps` matters: zoom is multiplicative per click
## (CameraController.zoom_factor_per_step), so crossing
## tactical_zoom_threshold takes tens of clicks, not one. Each is emitted as
## its own press/release pair a frame apart for the same reason _cmd_click
## separates them.
func _cmd_wheel(request: Dictionary) -> void:
	var at := Vector2(float(request.get("x", 0.0)), float(request.get("y", 0.0)))
	var up := bool(request.get("up", true))
	var steps := maxi(1, int(request.get("steps", 1)))
	var index := MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	get_viewport().warp_mouse(at)
	for _i in steps:
		_emit_mouse(at, index, true)
		_emit_mouse(at, index, false)
		await get_tree().process_frame
	_respond({"ok": true})

func _emit_mouse(at: Vector2, index: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	var window_at := _to_window(at)
	event.position = window_at
	event.global_position = window_at
	event.button_index = index
	event.pressed = pressed
	event.button_mask = (1 << (index - 1)) if pressed else 0
	Input.parse_input_event(event)

## Accepts Godot key names ("Space", "Tab", "A") via find_keycode_from_string,
## so the caller names keys the way InputBindings does rather than passing
## raw integers.
##
## `hold` (seconds, real time) exists because the two kinds of key input here
## need opposite treatment. TickManager's pause reads a one-shot
## `is_action_pressed(event)` off the event itself, so a tap is enough.
## CameraController._handle_pan_input() instead polls the global
## Input.is_action_pressed() every _process frame and integrates against
## delta — a tap holds the key for a single frame and pans by one frame's
## worth of movement, which is invisible. Panning has to be asked for with a
## duration or it will read as "the camera does not move", which is what
## happened before this parameter existed.
func _cmd_key(request: Dictionary) -> void:
	var name := String(request.get("key", ""))
	var keycode := OS.find_keycode_from_string(name)
	if keycode == KEY_NONE:
		_respond({"ok": false, "error": "unrecognized key '%s'" % name})
		return
	var hold := float(request.get("hold", 0.0))
	_emit_key(keycode, true)
	if hold > 0.0:
		await get_tree().create_timer(hold, true, false, true).timeout
	else:
		await get_tree().process_frame
	_emit_key(keycode, false)
	await get_tree().process_frame
	_respond({"ok": true})

func _emit_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
