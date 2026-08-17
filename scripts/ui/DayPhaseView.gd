class_name DayPhaseView
extends HBoxContainer

## The day counter + Victorian calendar period (TimeCycleManager) + Day/Night
## phase clock — split out of `TimeControlsView`. "Messages at the top of the
## screen overlap on the date and day/night countdown... move the date and
## day/night countdown to the bottom right please above where the minimap is"
## (user request). `TimeControlsView` keeps the speed buttons in their
## existing top-right spot; this view is everything else it used to show, now
## living bottom-right, stacked directly above `MinimapView` in `MainHUD`'s
## own bottom-right corner instead of sharing the top-right row with the
## mode/recon label strip above the resource bar.
##
## Shows TimeCycleManager.get_hour_string() ("10pm"/"5am") rather than a
## real-time mm:ss countdown to the next phase flip — per user request, the
## exact seconds-remaining figure is never surfaced, only which in-fiction
## hour it currently is.

const CLOCK_REFRESH_SECONDS: float = 1.0  ## No need to update the hour label every single frame.

var _day_label: Label
var _phase_label: Label
var _clock_timer: Timer

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
	_clock_timer = Timer.new()
	_clock_timer.wait_time = CLOCK_REFRESH_SECONDS
	_clock_timer.autostart = true
	add_child(_clock_timer)
	_clock_timer.timeout.connect(_refresh_phase_label)

	_on_day_completed(TickManager.current_day)
	_refresh_phase_label()

func _on_day_completed(day_number: int) -> void:
	_day_label.text = "Day %d — %s" % [day_number, TimeCycleManager.get_calendar_period_string()]

func _on_phase_changed(_phase: GameEnums.DayPhase) -> void:
	_refresh_phase_label()

func _refresh_phase_label() -> void:
	var phase_name := "Day" if TimeCycleManager.is_day() else "Night"
	_phase_label.text = "%s (%s)" % [phase_name, TimeCycleManager.get_hour_string()]
