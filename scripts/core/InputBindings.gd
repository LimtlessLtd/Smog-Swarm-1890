class_name InputBindings
extends RefCounted

## Central registry for the project's default input actions.
##
## Registered at runtime rather than hand-authored into project.godot's
## [input] section, so bindings stay plain, diffable GDScript instead of
## serialized resource literals. Call register_defaults() once before an
## action is first read; it is idempotent so any number of systems can call
## it defensively during their own _ready().

const PAN_LEFT := "camera_pan_left"
const PAN_RIGHT := "camera_pan_right"
const PAN_UP := "camera_pan_up"
const PAN_DOWN := "camera_pan_down"
const TOGGLE_PERSPECTIVE := "toggle_camera_perspective"
## User request ("the space bar should pause and unpause the game") — see
## TickManager.toggle_pause().
const TOGGLE_PAUSE := "toggle_pause"

static func register_defaults() -> void:
	_bind(PAN_LEFT, [KEY_A, KEY_LEFT])
	_bind(PAN_RIGHT, [KEY_D, KEY_RIGHT])
	_bind(PAN_UP, [KEY_W, KEY_UP])
	_bind(PAN_DOWN, [KEY_S, KEY_DOWN])
	_bind(TOGGLE_PERSPECTIVE, [KEY_TAB])
	_bind(TOGGLE_PAUSE, [KEY_SPACE])

static func _bind(action: StringName, keycodes: Array) -> void:
	if InputMap.has_action(action):
		return  # Already registered — leave existing bindings (possibly rebound by the player) alone.
	InputMap.add_action(action)
	for keycode in keycodes:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		InputMap.action_add_event(action, event)
