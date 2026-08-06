class_name TimeControlsView
extends HBoxContainer

## Top-right HUD strip (design doc Phase 6.1): day counter + Victorian
## calendar date (TimeCycleManager, Phase 5.1) + Day/Night phase countdown
## clock ("Nightfall in 04:15" — the design doc's own example, shown here as
## the more compact "Night (04:15)"/"Day (04:15)") + 0x/1x/2x/3x/5x speed
## buttons. Pure UI over TickManager/TimeCycleManager (autoloads, globally
## accessible — no NodePath needed) with no simulation logic of its own.
## Widened from its original day-counter-only footprint to fit the new text;
## still a code-drawn placeholder like the rest of the HUD, not a final
## art/layout pass — see MainHUD's own doc comment on that convention.

const SPEED_LABELS: Array[String] = ["0x", "1x", "2x", "3x", "5x"]
const COUNTDOWN_REFRESH_SECONDS: float = 1.0  ## No need to update a mm:ss label every single frame.

var _day_label: Label
var _phase_label: Label
var _speed_buttons: Array[Button] = []
var _countdown_timer: Timer

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	_day_label = Label.new()
	add_child(_day_label)

	_phase_label = Label.new()
	add_child(_phase_label)

	for i in range(SPEED_LABELS.size()):
		var button := Button.new()
		button.text = SPEED_LABELS[i]
		button.toggle_mode = true
		button.pressed.connect(_on_speed_button_pressed.bind(i))
		add_child(button)
		_speed_buttons.append(button)

	TickManager.day_completed.connect(_on_day_completed)
	TickManager.speed_changed.connect(_on_speed_changed)
	TimeCycleManager.phase_changed.connect(_on_phase_changed)

	# Ticks in real seconds scaled by Engine.time_scale same as everything
	# else this reads from (TickManager.elapsed_in_day) — refreshes faster
	# at higher game speeds, which is exactly the behavior wanted here.
	_countdown_timer = Timer.new()
	_countdown_timer.wait_time = COUNTDOWN_REFRESH_SECONDS
	_countdown_timer.autostart = true
	add_child(_countdown_timer)
	_countdown_timer.timeout.connect(_refresh_phase_label)

	_on_day_completed(TickManager.current_day)
	_refresh_speed_buttons(TickManager.speed_index)
	_refresh_phase_label()

func _on_speed_button_pressed(index: int) -> void:
	TickManager.set_speed_index(index)

func _on_day_completed(day_number: int) -> void:
	_day_label.text = "Day %d — %s" % [day_number, TimeCycleManager.get_calendar_date_string()]

func _on_speed_changed(_multiplier: float) -> void:
	_refresh_speed_buttons(TickManager.speed_index)

func _on_phase_changed(_phase: GameEnums.DayPhase) -> void:
	_refresh_phase_label()

func _refresh_phase_label() -> void:
	var seconds := TimeCycleManager.get_seconds_until_next_phase()
	var phase_name := "Day" if TimeCycleManager.is_day() else "Night"
	_phase_label.text = "%s (%s)" % [phase_name, _format_countdown(seconds)]

func _format_countdown(seconds: float) -> String:
	var total_seconds := maxi(0, int(ceil(seconds)))
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]

## Setting `button_pressed` directly (rather than via user interaction)
## deliberately does NOT re-fire the `pressed` signal we connected above, so
## this can't recurse into _on_speed_button_pressed().
func _refresh_speed_buttons(active_index: int) -> void:
	for i in range(_speed_buttons.size()):
		_speed_buttons[i].button_pressed = (i == active_index)
