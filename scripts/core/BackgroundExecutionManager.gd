extends Node

## Autoload singleton (see project.godot [autoload]); registered there under
## the name "BackgroundExecutionManager", which is also how the rest of the
## game should reference it globally — no `class_name` here since autoload
## singletons already provide a global identifier and Godot forbids a script
## class_name from shadowing it.
##
## "The Smog & The Swarm" is designed to keep simulating while the player
## has tabbed away — this throttles the render framerate while the window
## is unfocused/minimized, and deliberately touches nothing else (no
## `get_tree().paused`, no bus muting), so simulation ticks and audio keep
## running exactly as they would in the foreground.

@export var focused_fps_limit: int = 0     ## 0 = uncapped (governed by VSync/monitor refresh).
@export var unfocused_fps_limit: int = 15  ## Low enough to noticeably cut idle CPU/GPU draw.

func _ready() -> void:
	# Keep throttling active even if a future system pauses the SceneTree.
	process_mode = Node.PROCESS_MODE_ALWAYS

	var root_window := get_tree().root
	root_window.focus_exited.connect(_on_focus_exited)
	root_window.focus_entered.connect(_on_focus_entered)

func _on_focus_exited() -> void:
	Engine.max_fps = unfocused_fps_limit

func _on_focus_entered() -> void:
	Engine.max_fps = focused_fps_limit
