extends Node

## Autoload singleton (see project.godot [autoload]); registered there under
## the name "TickManager" — no `class_name` here for the same reason as
## BackgroundExecutionManager (an autoload's registered name already is its
## global identifier, and Godot forbids a script class_name from shadowing
## it).
##
## Minimal implementation of the "Global TickManager" promised by the design
## overview: real-time day length plus the 0x/5x/20x/50x/100x/1000x speed control
## (applied via Engine.time_scale, as the overview specifies). This exists
## now purely so Phase 2.2's "daily upkeep drains" have a "day" to hang off
## (`day_completed`); Phase 5.1 owns the actual Day/Night visual phase split
## within that day and should extend this rather than replace it.
##
## Re-tuned per user request ("quite long even with 5x") — replaced the
## original 0x/1x/2x/3x/5x ladder with a fast-forward-focused one that keeps
## 0x (pause) and 5x (new default, index 1) but otherwise climbs steeply —
## 20x/50x/100x/1000x — rather than adding finer-grained low-end steps.
## Every consumer of speed here (day length, unit/horde movement, resource
## drains, the countdown timer) is already plain delta-based and scales via
## Engine.time_scale, so a bigger multiplier needs no extra wiring — see
## this array and TimeControlsView.SPEED_LABELS, the only two places a speed
## step is defined, kept index-parallel.

signal day_completed(day_number: int)
signal speed_changed(multiplier: float)

## 40 real-time minutes per full day at 1x speed (20 min Day / 20 min Night —
## see design overview and Phase 5.1), matching Engine.time_scale directly so
## higher speeds shorten a day's real-time length instead of changing its
## meaning.
const DAY_LENGTH_SECONDS: float = 2400.0
const SPEED_MULTIPLIERS: Array[float] = [0.0, 5.0, 20.0, 50.0, 100.0, 1000.0]

var current_day: int = 1
var elapsed_in_day: float = 0.0
var speed_index: int = 1
## User request ("the space bar should pause and unpause the game. return
## the user to the speed they last used") — updated centrally inside
## set_speed_index() itself (not just from toggle_pause()) so it tracks
## correctly no matter WHAT paused the game: the spacebar, or AlertManager's
## own existing auto-pause-on-CRITICAL-alert (set_speed_index(0) directly) —
## either way, whatever nonzero speed was actually running right before the
## game went to 0 is what a later toggle_pause() restores. Defaults to
## speed_index's own default (1 = 5x) so pausing before ever unpausing has a
## sane fallback rather than restoring to a meaningless sentinel.
var _last_nonzero_speed_index: int = 1

## Real bug fix (playtest round 4, #11: "when the game is already paused and
## you press the space button, it quickly flashes on '5x' then flashes back
## to '0x'... looks like theres a toggle bug"). AlertManager.set_speed_index(0)
## is the only OTHER caller (besides this class's own toggle_pause()) able to
## force speed back to 0 — it auto-pauses on any WARNING/CRITICAL
## EventManager event. A player who paused because of an active threat (a
## wall under siege, a resource shortfall) and then presses Space to resume
## can have that exact same still-unfolding situation cross another real
## threshold within the very next tick or two, re-triggering AlertManager
## before the player even sees the game move — a real, code-driven "unpause,
## then immediately re-paused for a legitimate reason" sequence that reads
## exactly like a broken toggle. `_MANUAL_UNPAUSE_GRACE_MS` gives a manual
## Space-triggered unpause a short real-time (Time.get_ticks_msec(), same
## "unaffected by Engine.time_scale" reasoning AlertManager's own chime
## cooldown already uses) window immune to being paused again — long enough
## to be visibly, unambiguously "it actually resumed," short enough
## (well under a second) that it never meaningfully delays a genuinely new
## alert the player needs to see.
const _MANUAL_UNPAUSE_GRACE_MS: int = 400
var _manual_unpause_at_ms: int = -_MANUAL_UNPAUSE_GRACE_MS

func _ready() -> void:
	# Keep ticking even if a future system pauses the SceneTree, same as
	# BackgroundExecutionManager — this is background-simulation infrastructure.
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputBindings.register_defaults()
	set_speed_index(speed_index)

func _process(delta: float) -> void:
	elapsed_in_day += delta
	while elapsed_in_day >= DAY_LENGTH_SECONDS:
		elapsed_in_day -= DAY_LENGTH_SECONDS
		current_day += 1
		day_completed.emit(current_day)

## Spacebar (InputBindings.TOGGLE_PAUSE) — _unhandled_input so a focused UI
## Control's own keyboard handling (if any) still gets first refusal, same
## convention every other input controller in this project already follows.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputBindings.TOGGLE_PAUSE):
		toggle_pause()
		get_viewport().set_input_as_handled()

## Pauses (speed_index -> 0) if currently running, or restores
## _last_nonzero_speed_index if currently paused — see that var's own doc
## comment for why it's tracked centrally rather than just here.
func toggle_pause() -> void:
	var was_paused := speed_index == 0
	set_speed_index(_last_nonzero_speed_index if was_paused else 0)
	if was_paused:
		_manual_unpause_at_ms = Time.get_ticks_msec()  ## Starts this unpause's own grace window — see _MANUAL_UNPAUSE_GRACE_MS's own doc comment.

func get_day_progress() -> float:
	return elapsed_in_day / DAY_LENGTH_SECONDS

## `is_automatic_pause` — true ONLY for AlertManager's own auto-pause-on-alert
## call. A deliberate player action (a speed button click, toggle_pause()'s
## own unpause, a save load) always takes effect immediately and is never
## subject to _MANUAL_UNPAUSE_GRACE_MS below — only an automatic system-driven
## pause request arriving inside a just-issued manual unpause's own grace
## window gets silently dropped (see that constant's own doc comment for the
## exact bug this prevents). Everything genuinely NEW still gets through: the
## grace window is real-time-bounded and short, so a fresh alert even a
## fraction of a second later still pauses normally.
func set_speed_index(index: int, is_automatic_pause: bool = false) -> void:
	if is_automatic_pause and index == 0 and Time.get_ticks_msec() - _manual_unpause_at_ms < _MANUAL_UNPAUSE_GRACE_MS:
		return
	if speed_index != 0:
		_last_nonzero_speed_index = speed_index
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
