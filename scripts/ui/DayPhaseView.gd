class_name DayPhaseView
extends HBoxContainer

## The day counter + Victorian calendar date (TimeCycleManager) + Day/Night
## phase countdown clock ("Nightfall in 04:15") — split out of
## `TimeControlsView`. "Messages at the top of the screen overlap on the
## date and day/night countdown... move the date and day/night countdown to
## the bottom right please above where the minimap is" (user request).
## `TimeControlsView` keeps the speed buttons in their existing top-right
## spot; this view is everything else it used to show, now living
## bottom-right, stacked directly above `MinimapView` in `MainHUD`'s own
## bottom-right corner instead of sharing the top-right row with the
## mode/recon label strip above the resource bar.

const COUNTDOWN_REFRESH_SECONDS: float = 1.0  ## No need to update a mm:ss label every single frame.

var _day_label: Label
var _phase_label: Label
var _countdown_timer: Timer

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	HUDStyles.style_panel(self)

	_day_label = Label.new()
	HUDStyles.style_label(_day_label, true)
	add_child(_day_label)

	_phase_label = Label.new()
	HUDStyles.style_label(_phase_label)
	add_child(_phase_label)

	TickManager.day_completed.connect(_on_day_completed)
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
	_refresh_phase_label()

func _on_day_completed(day_number: int) -> void:
	_day_label.text = "Day %d — %s" % [day_number, TimeCycleManager.get_calendar_date_string()]

func _on_phase_changed(_phase: GameEnums.DayPhase) -> void:
	_refresh_phase_label()

func _refresh_phase_label() -> void:
	var seconds := TimeCycleManager.get_seconds_until_next_phase()
	var phase_name := "Day" if TimeCycleManager.is_day() else "Night"
	_phase_label.text = "%s (%s)" % [phase_name, _format_countdown(seconds)]

func _format_countdown(seconds: float) -> String:
	var total_seconds := maxi(0, int(ceil(seconds)))
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]
