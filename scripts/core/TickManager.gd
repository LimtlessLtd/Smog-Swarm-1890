extends Node

## Autoload singleton (see project.godot [autoload]); registered there under
## the name "TickManager" — no `class_name` here for the same reason as
## BackgroundExecutionManager (an autoload's registered name already is its
## global identifier, and Godot forbids a script class_name from shadowing
## it).
##
## Minimal implementation of the "Global TickManager" promised by the design
## overview: real-time day length plus the 0x/1x/2x/3x/5x speed control
## (applied via Engine.time_scale, as the overview specifies). This exists
## now purely so Phase 2.2's "daily upkeep drains" have a "day" to hang off
## (`day_completed`); Phase 5.1 owns the actual Day/Night visual phase split
## within that day and should extend this rather than replace it.

signal day_completed(day_number: int)
signal speed_changed(multiplier: float)

## 40 real-time minutes per full day at 1x speed (20 min Day / 20 min Night —
## see design overview and Phase 5.1), matching Engine.time_scale directly so
## higher speeds shorten a day's real-time length instead of changing its
## meaning.
const DAY_LENGTH_SECONDS: float = 2400.0
const SPEED_MULTIPLIERS: Array[float] = [0.0, 1.0, 2.0, 3.0, 5.0]  ## 0x, 1x, 2x, 3x, 5x.

var current_day: int = 1
var elapsed_in_day: float = 0.0
var speed_index: int = 1

func _ready() -> void:
	# Keep ticking even if a future system pauses the SceneTree, same as
	# BackgroundExecutionManager — this is background-simulation infrastructure.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_speed_index(speed_index)

func _process(delta: float) -> void:
	elapsed_in_day += delta
	while elapsed_in_day >= DAY_LENGTH_SECONDS:
		elapsed_in_day -= DAY_LENGTH_SECONDS
		current_day += 1
		day_completed.emit(current_day)

func get_day_progress() -> float:
	return elapsed_in_day / DAY_LENGTH_SECONDS

func set_speed_index(index: int) -> void:
	speed_index = clampi(index, 0, SPEED_MULTIPLIERS.size() - 1)
	Engine.time_scale = SPEED_MULTIPLIERS[speed_index]
	speed_changed.emit(SPEED_MULTIPLIERS[speed_index])

func get_speed_multiplier() -> float:
	return SPEED_MULTIPLIERS[speed_index]

## Exposed for SaveLoadManager (Phase 2.8) — day/elapsed-time/speed are the
## only state this autoload owns.
func get_save_state() -> Dictionary:
	return {"current_day": current_day, "elapsed_in_day": elapsed_in_day, "speed_index": speed_index}

func load_save_state(state: Dictionary) -> void:
	current_day = state.get("current_day", 1)
	elapsed_in_day = state.get("elapsed_in_day", 0.0)
	set_speed_index(state.get("speed_index", speed_index))
