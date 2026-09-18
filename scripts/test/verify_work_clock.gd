extends Node

## Locks down D98's work clock: jobs count in-game hours and production settles
## hourly at a day's rate. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless scenes/test/verify_work_clock.tscn
##
## A scene rather than a `-s` script because it drives the TickManager autoload.
##
## 1. **Every hour of every day, in order, before the day.** One large-delta
##    TickManager._process() call spanning two days emits 48 hour_completed in
##    order and each day's 24th hour before its day_completed — the catch-up case
##    the hourly jobs rely on.
## 2. **A job takes its hours, not its days.** A construction job of N hours is
##    still pending after N-1 process_hour() calls and done after the Nth.
## 3. **Hourly production sums to a day's.** Twenty-four apply_share_of_day()
##    calls bank what compute_daily_totals() says a day produces, so moving
##    production to the hour changed its timing and not its amount.

const _EPSILON: float = 0.01

var _failures: Array[String] = []
var _events: Array[String] = []

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)


func _ready() -> void:
	_check_speed_ladder()
	_check_hours_then_day()
	_check_job_takes_its_hours()
	_check_hourly_production_sums_to_a_day()
	print()
	if _failures.is_empty():
		print("All work-clock checks passed.")
		get_tree().quit(0)
	else:
		print("FAILED (%d):" % _failures.size())
		for failure in _failures:
			print("  " + failure)
		get_tree().quit(1)

func _check_speed_ladder() -> void:
	var expected: Array[float] = [0.0, 1.0, 2.0, 3.0]
	_check(TickManager.SPEED_MULTIPLIERS == expected, "speed controls are %s, want %s" % [TickManager.SPEED_MULTIPLIERS, expected])
	for i in range(expected.size()):
		TickManager.set_speed_index(i)
		_check(is_equal_approx(TickManager.get_speed_multiplier(), expected[i]), "speed index %d resolved to %sx" % [i, TickManager.get_speed_multiplier()])
	TickManager.set_speed_index(0)


func _check_hours_then_day() -> void:
	TickManager.load_save_state({"current_day": 1, "elapsed_in_day": 0.0, "speed_index": 0})
	TickManager.hour_completed.connect(_on_hour)
	TickManager.day_completed.connect(_on_day)
	TickManager._process(TickManager.DAY_LENGTH_SECONDS * 2.0 + 1.0)
	TickManager.hour_completed.disconnect(_on_hour)
	TickManager.day_completed.disconnect(_on_day)
	var hours := _events.filter(func(e: String) -> bool: return e.begins_with("h"))
	print("1. one 2-day delta: %d hours, %d days; around the first day: %s" % [hours.size(), _events.size() - hours.size(), _events.slice(22, 27)])
	if hours.size() != 2 * TickManager.HOURS_PER_DAY:
		_failures.append("a two-day delta emitted %d hour_completed, want %d" % [hours.size(), 2 * TickManager.HOURS_PER_DAY])
	var expected: Array[String] = []
	for day in [1, 2]:
		for hour in range(1, TickManager.HOURS_PER_DAY + 1):
			expected.append("h%d.%d" % [day, hour])
		expected.append("d%d" % (day + 1))
	if _events != expected:
		_failures.append("hours and days arrived out of order: %s" % str(_events))


func _on_hour(day: int, hour: int) -> void:
	_events.append("h%d.%d" % [day, hour])


func _on_day(day: int) -> void:
	_events.append("d%d" % day)


func _check_job_takes_its_hours() -> void:
	var controller := BuildingConstructionController.new()
	var definition := BuildingCatalog.get_definition(GameEnums.BuildingType.WATCHTOWER)
	var hours := controller.hours_for(definition)
	var instance := BuildingInstance.new(definition, Vector2i.ZERO, 1, Vector2.ZERO, -1, -1.0, false, true)
	controller.queue(instance, hours)
	for i in range(hours - 1):
		controller.process_hour()
	var pending_before_last := instance.is_under_construction
	controller.process_hour()
	print("2. Watchtower construction %d hours: under construction after %d = %s, after %d = %s" % [hours, hours - 1, pending_before_last, hours, instance.is_under_construction])
	if hours < 1:
		_failures.append("hours_for() gave a Watchtower %d hours" % hours)
	if hours > 1 and not pending_before_last:
		_failures.append("a %d-hour job finished early" % hours)
	if instance.is_under_construction:
		_failures.append("a %d-hour job was still under construction after %d hours" % [hours, hours])


func _check_hourly_production_sums_to_a_day() -> void:
	var resources: ResourceManager = load("res://scenes/economy/ResourceManager.tscn").instantiate()
	add_child(resources)
	var sustenance := BuildingSustenanceController.new(resources, null, null)
	var definition := BuildingCatalog.get_definition(GameEnums.BuildingType.LUMBER_YARD)
	var instances: Array[BuildingInstance] = [BuildingInstance.new(definition, Vector2i.ZERO, 1, Vector2.ZERO)]
	var daily: Dictionary = sustenance.compute_daily_totals(instances)["produced"]
	var expected := float(daily.get(GameEnums.ResourceType.WOOD, 0.0))
	var before := resources.get_amount(GameEnums.ResourceType.WOOD)
	for i in range(TickManager.HOURS_PER_DAY):
		sustenance.apply_share_of_day(instances, 1.0 / float(TickManager.HOURS_PER_DAY))
	var banked := resources.get_amount(GameEnums.ResourceType.WOOD) - before
	print("3. Lumber Yard: a day's totals say %.2f Wood; 24 hourly shares banked %.2f" % [expected, banked])
	if expected <= 0.0:
		_failures.append("the Lumber Yard fixture produces no Wood, so check 3 measures nothing")
	if absf(banked - expected) > _EPSILON:
		_failures.append("24 hourly shares banked %.2f Wood where one day's totals are %.2f" % [banked, expected])
