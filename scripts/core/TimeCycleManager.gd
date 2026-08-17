extends Node

## Autoload singleton (see project.godot [autoload]); registered there under
## the name "TimeCycleManager" — no class_name here, same reasoning as
## TickManager/BackgroundExecutionManager (an autoload's registered name
## already is its global identifier).
##
## The Day/Night simulation layer, built directly on top of TickManager's
## own generic day-length/speed foundation. Purely derived state:
## TickManager.current_day/elapsed_in_day is the only thing that actually
## needs saving (already handled by TickManager.get_save_state()/
## SaveLoadManager), so this autoload has no save state of its own — same
## relationship LogisticsNetwork's Zone of Control coverage has to the
## supply lines it's derived from.
##
## The 40-minute day (TickManager.DAY_LENGTH_SECONDS) splits evenly into a
## 20-minute Day phase followed by a 20-minute Night phase.
##
## Implemented here:
##   - GameEnums.DayPhase state + phase_changed/day_phase_started/
##     night_phase_started signals.
##   - get_seconds_until_next_phase()/get_seconds_until_nightfall(), feeding
##     the HUD's "Nightfall in 04:15" countdown.
##   - A Victorian calendar period (campaign day 1 = 1 January 1890), advancing
##     with TickManager.current_day. Never shows the exact day-of-month —
##     "Early/Mid/Late <Month>" per user request, months fixed at 15 days each.
##   - get_hour_string(), an in-fiction clock ("10pm"/"5am") derived from
##     TickManager.get_day_progress() rather than a real-time countdown —
##     "instead of the 20 minute timer it should say which hour of the day we
##     are in" (user request). The Day phase (progress 0.0-0.5) spans 7am-7pm;
##     Night (0.5-1.0) spans 7pm-7am, symmetric with it.
##   - FogOfWarManager's night vision contraction hook: phase_changed is
##     what FogOfWarManager listens to and recomputes against; the actual
##     radius math lives there, not here.
##
## Not wired here: night's 2x sewer eruption rate — the sewer system
## doesn't exist yet.
##
## Every other Day/Night multiplier lives in the manager that owns the
## thing it modifies (managers own their own balancing constants; this
## class only owns deriving the phase itself, not applying it):
##   - "+20% Day construction/resource-gather speed" — BuildingManager.
##     DAY_NIGHT_AVERAGE_PRODUCTION_MULTIPLIER (a flat +10% once-daily
##     average, mathematically identical to a true +20%-Day/+0%-Night split
##     given this class's own exact 50/50 Day/Night division — see that
##     constant's own doc comment for the derivation, and for why it isn't
##     built as literal phase-triggered sub-day ticks).
##   - Zombie move-speed — HordeManager.DAY_MOVE_SPEED_MULTIPLIER/
##     NIGHT_MOVE_SPEED_MULTIPLIER. Aggression +100% — HordeManager.
##     NIGHT_AGGRESSION_MULTIPLIER. Double noise-attraction — NoiseManager.
##     NIGHT_NOISE_MULTIPLIER. Military unit move-speed/damage —
##     UnitOrderController.DAY_MOVE_SPEED_MULTIPLIER / CombatCoordinator.
##     DAY_DAMAGE_MULTIPLIER.

signal phase_changed(phase: GameEnums.DayPhase)
signal day_phase_started
signal night_phase_started

## The campaign's own fixed epoch — 1 January 1890, the day Manchester
## lifted its self-imposed quarantine. TickManager.current_day is 1-based
## and starts at 1, so day 1 IS 1 Jan 1890 with no offset needed.
const CAMPAIGN_START_YEAR: int = 1890
const CAMPAIGN_START_MONTH_INDEX: int = 0  # January, 0-based into MONTH_NAMES.
const DAYS_PER_MONTH: int = 15  ## Fixed per user request ("each month has only 15 days") — no real-calendar variation to track.
const MONTH_NAMES: Array[String] = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]

## Start-of-day/end-of-day clock hours — the Day phase (7am-7pm) is 12
## in-fiction hours mapped across the first half of TickManager's day
## progress, Night (7pm-7am) the second half, symmetric with it.
const DAY_START_HOUR: int = 7

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
## the current phase flips. The HUD's countdown clock reads this directly.
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

## "Early February 1890"-style Victorian calendar period. Campaign day N is
## N-1 whole days after 1 January 1890. The exact day-of-month is never
## surfaced — per user request, only which third of the (fixed 15-day) month
## it falls in.
func get_calendar_period_string() -> String:
	var days_elapsed := TickManager.current_day - 1
	var month_count := MONTH_NAMES.size()
	var months_elapsed := days_elapsed / DAYS_PER_MONTH
	var year := CAMPAIGN_START_YEAR + (CAMPAIGN_START_MONTH_INDEX + months_elapsed) / month_count
	var month_index := (CAMPAIGN_START_MONTH_INDEX + months_elapsed) % month_count
	var day_in_month := (days_elapsed % DAYS_PER_MONTH) + 1  # 1-based.
	return "%s %s %d" % [_period_name(day_in_month), MONTH_NAMES[month_index], year]

## Thirds of the 15-day month: days 1-5 Early, 6-10 Mid, 11-15 Late.
func _period_name(day_in_month: int) -> String:
	var third := DAYS_PER_MONTH / 3
	if day_in_month <= third:
		return "Early"
	elif day_in_month <= third * 2:
		return "Mid"
	return "Late"

## "10pm"/"5am"-style in-fiction clock, replacing the old real-time mm:ss
## countdown per user request. Day progress 0.0 is 7am (DAY_START_HOUR),
## wrapping through a full 24 in-fiction hours by progress 1.0 — the Day
## phase (progress < 0.5) lands entirely within 7am-7pm this way, matching
## "days start at 7am and end at 7pm" exactly (progress 0.5 == 7pm).
func get_hour_string() -> String:
	var hour_24 := int(floor(DAY_START_HOUR + TickManager.get_day_progress() * 24.0)) % 24
	var hour_12 := hour_24 % 12
	if hour_12 == 0:
		hour_12 = 12
	var suffix := "am" if hour_24 < 12 else "pm"
	return "%d%s" % [hour_12, suffix]
