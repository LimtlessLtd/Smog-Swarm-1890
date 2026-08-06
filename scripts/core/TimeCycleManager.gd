extends Node

## Autoload singleton (see project.godot [autoload]); registered there under
## the name "TimeCycleManager" — no `class_name` here, same reasoning as
## TickManager/BackgroundExecutionManager (an autoload's registered name
## already is its global identifier).
##
## Design doc Phase 5.1's Day/Night simulation layer, built directly on top
## of TickManager's own generic day-length/speed foundation per that
## script's own doc comment ("Phase 5.1 owns the actual Day/Night visual
## phase split within that day and should extend this rather than replace
## it"). Purely derived state: TickManager.current_day/elapsed_in_day is the
## only thing that actually needs saving (already handled by
## TickManager.get_save_state()/SaveLoadManager), so this autoload has no
## save state of its own — same relationship LogisticsNetwork's Zone of
## Control coverage has to the supply lines it's derived from.
##
## The 40-minute day (TickManager.DAY_LENGTH_SECONDS) splits evenly into a
## 20-minute Day phase followed by a 20-minute Night phase, matching the
## design doc's own numbers exactly.
##
## Implemented here now:
##   - GameEnums.DayPhase state + phase_changed/day_phase_started/
##     night_phase_started signals.
##   - get_seconds_until_next_phase()/get_seconds_until_nightfall(), feeding
##     Phase 6.1's "Nightfall in 04:15" HUD countdown.
##   - A Victorian calendar date (campaign day 1 = 1 January 1890), advancing
##     with TickManager.current_day — feeds Phase 6.1's HUD and gives the
##     "how long since Manchester's quarantine ended" framing the design doc
##     asks for a concrete date to hang off.
##   - FogOfWarManager's night vision contraction hook (design doc 2.6.4):
##     phase_changed is what FogOfWarManager listens to and recomputes
##     against; the actual radius math lives there, not here.
##
## Deliberately NOT wired here yet — each blocked on a system that doesn't
## exist, same "not implemented, deliberately" convention as every other
## deferral already in todo.md:
##   - +20% Day construction/resource-gather speed and Night's 2x sewer
##     eruption rate: both need a sub-day production tick.
##     BuildingManager/ResourceManager only tally output once per full day
##     (TickManager.day_completed), not per Day/Night phase within it, and
##     Phase 3's sewer system doesn't exist yet either.
##   - Zombie move-speed/aggression/noise-attraction deltas and military
##     unit move-speed/damage deltas: no zombie (Phase 5.2/5.4) or unit
##     (Phase 5.4) exists yet to apply a modifier to.

signal phase_changed(phase: GameEnums.DayPhase)
signal day_phase_started
signal night_phase_started

## The campaign's own fixed epoch (design doc: "January 1st 1890" — the day
## Manchester lifted its self-imposed quarantine). TickManager.current_day
## is 1-based and starts at 1, so day 1 IS 1 Jan 1890 with no offset needed.
const CAMPAIGN_START_YEAR: int = 1890
const CAMPAIGN_START_MONTH_INDEX: int = 0  # January, 0-based into MONTH_NAMES.
const DAYS_PER_MONTH: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]  # 1890 wasn't a leap year, and no campaign runs anywhere near 4 in-fiction years.
const MONTH_NAMES: Array[String] = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]

var _current_phase: GameEnums.DayPhase = GameEnums.DayPhase.DAY

func _ready() -> void:
	# Same reasoning as TickManager/BackgroundExecutionManager: this is
	# background-simulation infrastructure, not gameplay that should freeze
	# if a future system ever pauses the SceneTree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_current_phase = _phase_for_progress(TickManager.get_day_progress())

func _process(_delta: float) -> void:
	var new_phase := _phase_for_progress(TickManager.get_day_progress())
	if new_phase == _current_phase:
		return
	_current_phase = new_phase
	phase_changed.emit(_current_phase)
	if _current_phase == GameEnums.DayPhase.DAY:
		day_phase_started.emit()
	else:
		night_phase_started.emit()

func _phase_for_progress(progress: float) -> GameEnums.DayPhase:
	return GameEnums.DayPhase.DAY if progress < 0.5 else GameEnums.DayPhase.NIGHT

func get_current_phase() -> GameEnums.DayPhase:
	return _current_phase

func is_day() -> bool:
	return _current_phase == GameEnums.DayPhase.DAY

func is_night() -> bool:
	return _current_phase == GameEnums.DayPhase.NIGHT

## Seconds remaining (already speed-scaled, same as TickManager.elapsed_in_day
## itself — Engine.time_scale affects the delta both accumulate from) until
## the current phase flips. Phase 6.1's countdown clock reads this directly.
func get_seconds_until_next_phase() -> float:
	var half := TickManager.DAY_LENGTH_SECONDS / 2.0
	var elapsed := TickManager.elapsed_in_day
	if elapsed < half:
		return half - elapsed
	return TickManager.DAY_LENGTH_SECONDS - elapsed

## 0 while it's already night — "Nightfall in 04:15" only means something
## during the Day phase counting down to it.
func get_seconds_until_nightfall() -> float:
	return get_seconds_until_next_phase() if is_day() else 0.0

## 0 while it's already day — the dawn counterpart, for symmetry.
func get_seconds_until_dawn() -> float:
	return get_seconds_until_next_phase() if is_night() else 0.0

## "3 February 1890"-style Victorian date. Campaign day N is N-1 whole days
## after 1 January 1890.
func get_calendar_date_string() -> String:
	var days_elapsed := TickManager.current_day - 1
	var year := CAMPAIGN_START_YEAR
	var month_index := CAMPAIGN_START_MONTH_INDEX
	var day := 1 + days_elapsed
	while day > DAYS_PER_MONTH[month_index]:
		day -= DAYS_PER_MONTH[month_index]
		month_index += 1
		if month_index >= MONTH_NAMES.size():
			month_index = 0
			year += 1
	return "%d %s %d" % [day, MONTH_NAMES[month_index], year]
