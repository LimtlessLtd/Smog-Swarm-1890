class_name VerticalSliceDebrief
extends RefCounted

## Turns what happened into why it mattered. Reads the ConsequenceLog's entries and
## totals, the director's objectives and the managers' current state, and returns
## the debrief as plain data for VerticalSliceHUD to lay out:
##
##   {"title": String, "subtitle": String,
##    "why": Array[String]      — each a cause and its consequence,
##    "timeline": Array[String] — the log, one line per event that a player caused
##                                or would want to know about,
##    "stats": Array[String]}
##
## Every sentence is built from a recorded event or a measured count; the one
## counterfactual ("with the ten you started with...") comes from SiegeForecast
## running the same siege rules with a different defender count, and says so.

const SLICE_HORDE_FRACTION: float = 0.5  ## A logged horde at least this share of HORDE_SIZE is the slice's horde, not an ambient stray.


static func build(outcome: StringName, director: VerticalSliceDirector, log: ConsequenceLog, buildings: BuildingManager, infestation: InfestationManager, units: UnitManager) -> Dictionary:
	# Only what happened while the slice ran: "Keep playing" leaves the world going
	# after the debrief, and a debrief rebuilt later must not claim those events.
	var entries: Array[Dictionary] = []
	for entry in log.get_entries():
		if float(entry["seconds"]) <= director.get_elapsed_seconds() + 1.0:
			entries.append(entry)
	var totals := log.get_totals()
	var why: Array[String] = []

	var attracted := _first(entries, ConsequenceLog.KIND_ATTRACTED, true)
	var lost_switched := _first_with(entries, ConsequenceLog.KIND_LOST, "cause", &"switched_off", true)
	var siege := _first(entries, ConsequenceLog.KIND_SIEGE, true)
	var destroyed := _first(entries, ConsequenceLog.KIND_HORDE_DESTROYED, false)
	var breaches := _all(entries, ConsequenceLog.KIND_BREACH)
	var cleared := _first_with(entries, ConsequenceLog.KIND_CLEARED, "", null, false)
	var powered_down_before_dark := _powered_down_before_nightfall(entries)

	# How the horde found the town, or did not.
	if not attracted.is_empty():
		var data: Dictionary = attracted["data"]
		var light: bool = data["kind"] == NoiseManager.KIND_LIGHT
		why.append("It found you because of your %s. At %s the horde %s it from %d hex%s away — %s" % [
			data["source"], _time(attracted["seconds"]), "saw the light of" if light else "heard", int(data["distance"]), "" if int(data["distance"]) == 1 else "es",
			"lit Watchtowers are seen further the more of them burn together; every one switched off takes a hex off that reach." if light else "machinery is heard only close by, and louder at night."])
	elif director.has_released_horde():
		if not powered_down_before_dark.is_empty():
			why.append("It never found you. You put out %s before dark, so nothing of yours reached it. The price: those buildings stopped producing, and a switched-off Watchtower gives no night vision." % ", ".join(powered_down_before_dark))
		else:
			why.append("It never found you: it wandered out of reach of your lamps before they were lit.")

	if not lost_switched.is_empty():
		var data: Dictionary = lost_switched["data"]
		why.append("Going dark worked. At %s switching off the %s left nothing of yours reaching the horde %d hex%s out, and it turned away." % [_time(lost_switched["seconds"]), data["source"], int(data["distance"]), "" if int(data["distance"]) == 1 else "es"])

	# The wall.
	if not siege.is_empty():
		var data: Dictionary = siege["data"]
		var size := int(data["horde_size"])
		var hp := float(data["segment_hp"])
		var night: bool = data["night"]
		var undefended := SiegeForecast.project(size, hp, 0, 0, night)
		var toxophilite := UnitCatalog.get_definition(GameEnums.UnitType.TOXOPHILITE)
		var kills := SiegeForecast.kills_per_strike(toxophilite, not night)
		var start_count := 0
		for entry in VerticalSliceConfig.STARTING_UNITS:
			start_count += int(entry[1])
		var with_start := SiegeForecast.project(size, hp, start_count, kills, night)
		if not destroyed.is_empty() and int(destroyed["data"]["kills_from_cover"]) > 0 and breaches.is_empty():
			var ddata: Dictionary = destroyed["data"]
			why.append("Holding the wall won it. Up to %d defenders stood within reach of the piece the horde hit and killed %d from behind it without a single loss. Undefended, that %s would have fallen in about %s." % [int(ddata["peak_defenders"]), int(ddata["kills_from_cover"]), "gate" if data["gate"] else "wall piece", _real(undefended["seconds"])])
			if with_start["outcome"] == &"breach" and int(ddata["peak_defenders"]) > start_count:
				why.append("Training more mattered: with only the %d you started with in reach, the same siege breaks the wall after about %s with ~%d still standing (projected with the same rules)." % [start_count, _real(with_start["seconds"]), int(with_start["horde_left"])])
		elif not breaches.is_empty():
			why.append("The wall broke at %s. A %d-strong horde at night brings %d to a breach point; the defenders in reach were not enough to kill it before the piece fell (undefended it lasts about %s). Archers within %d m of the piece it hits, or darkness until dawn, change that." % [_time(breaches[0]["seconds"]), size, HordeManager.wall_contact_frontage(size), _real(undefended["seconds"]), int(WallDefenseController.RANGED_REACH_METRES)])

	var open_losses := 0
	for entry in _all(entries, ConsequenceLog.KIND_UNIT_LOST):
		if not entry["data"].get("from_cover", false):
			open_losses += 1
	if open_losses > 0:
		why.append("%d squad%s died fighting in the open. Against a horde outside a wall every zombie reaches them, not a breach point's worth — a horde in the field is avoided or walled, not met." % [open_losses, "" if open_losses == 1 else "s"])

	# The ground.
	var target_remaining := infestation.zombie_count_at(VerticalSliceConfig.TARGET_HEX)
	if infestation.is_cleared(VerticalSliceConfig.TARGET_HEX):
		var when := _time(cleared["seconds"]) if not cleared.is_empty() else "the end"
		var kills := int(cleared["data"]["kills"]) if not cleared.is_empty() else log.get_contact_kills_at(VerticalSliceConfig.TARGET_HEX)
		why.append("%s is yours: cleared at %s after %d kills there. Cleared ground takes every building the colony can raise — on moorland, farms and coal mines — and stays cleared only while the dead are kept off it." % [VerticalSliceConfig.TARGET_NAME.capitalize(), when, kills])
		for instance in buildings.get_buildings_at(VerticalSliceConfig.TARGET_HEX):
			if instance.definition.soil_fertility_scales_output and not instance.is_under_construction:
				var output := instance.get_effective_output(null)
				why.append("The %s on the moor produces %.0f Food a day — ground that was under %d dead when you started." % [instance.definition.display_name, float(output.get(GameEnums.ResourceType.FOOD, 0.0)), director.get_target_seeded()])
	else:
		why.append("%s still holds %d dead (cleared below %d). Each squad on the hex kills what reaches it every round; more squads, more rounds." % [VerticalSliceConfig.TARGET_NAME.capitalize(), target_remaining, director.get_target_threshold()])

	# One line per event up to the moment the slice ended; repeats of the same line
	# in the same minute fold into one with a count.
	var timeline: Array[String] = []
	var last_line := ""
	var repeats := 1
	for entry in entries:
		if float(entry["seconds"]) > director.get_elapsed_seconds() + 1.0:
			break
		if entry["kind"] in [ConsequenceLog.KIND_ATTRACTED, ConsequenceLog.KIND_LOST] and not _is_slice_horde(entry):
			continue
		var text: String = entry["text"]
		if entry["kind"] == ConsequenceLog.KIND_CLEARED and entry["coord"] == VerticalSliceConfig.TARGET_HEX:
			text = "%s was cleared after %d kills there." % [VerticalSliceConfig.TARGET_NAME.capitalize(), int(entry["data"]["kills"])]
		var line := "%s  %s" % [_time(entry["seconds"]), text]
		if line == last_line:
			repeats += 1
			timeline[-1] = "%s (×%d)" % [line, repeats]
			continue
		last_line = line
		repeats = 1
		timeline.append(line)

	var living := 0
	for instance in units.get_all_units():
		if not instance.is_destroyed():
			living += 1
	var stats: Array[String] = [
		"Length: %s" % _real(director.get_elapsed_seconds()),
		"Killed from behind the wall: %d" % int(totals["kills_from_cover"]),
		"Killed in the field: %d" % int(totals["kills_in_contact"]),
		"Squads lost: %d · standing: %d" % [int(totals["units_lost"]), living],
		"Wall damage taken: %.0f HP" % float(totals["wall_damage_taken"]),
	]

	var title := "The southern edge holds"
	var subtitle := "The moor is cleared and the horde is dealt with."
	if outcome == &"defeat":
		title = "Manchester's southern edge has fallen"
		subtitle = "The Town Hall is lost."
	elif outcome == &"time":
		title = "Twenty minutes gone"
		subtitle = "The slice ends here; the objectives below are where it stood."
	return {"title": title, "subtitle": subtitle, "why": why, "timeline": timeline, "stats": stats}


static func _is_slice_horde(entry: Dictionary) -> bool:
	return int(entry["data"].get("horde_size", 0)) >= int(float(VerticalSliceConfig.HORDE_SIZE) * SLICE_HORDE_FRACTION) or entry["data"].get("horde_size", -1) == -1


static func _first(entries: Array[Dictionary], kind: StringName, slice_horde_only: bool) -> Dictionary:
	for entry in entries:
		if entry["kind"] == kind and (not slice_horde_only or _is_slice_horde(entry)):
			return entry
	return {}


static func _first_with(entries: Array[Dictionary], kind: StringName, key: String, value: Variant, slice_horde_only: bool) -> Dictionary:
	for entry in entries:
		if entry["kind"] != kind:
			continue
		if slice_horde_only and not _is_slice_horde(entry):
			continue
		if key.is_empty() or entry["data"].get(key) == value:
			if kind != ConsequenceLog.KIND_CLEARED or entry["coord"] == VerticalSliceConfig.TARGET_HEX:
				return entry
	return {}


static func _all(entries: Array[Dictionary], kind: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in entries:
		if entry["kind"] == kind:
			result.append(entry)
	return result


static func _powered_down_before_nightfall(entries: Array[Dictionary]) -> Array[String]:
	var names: Array[String] = []
	for entry in entries:
		if entry["kind"] == ConsequenceLog.KIND_NIGHTFALL:
			break
		if entry["kind"] == ConsequenceLog.KIND_POWER_DOWN and not names.has(entry["data"]["building"]):
			names.append(entry["data"]["building"])
	return names


## Slice time as real minutes at the default speed, the clock the player lived.
static func _time(game_seconds: float) -> String:
	return _real(game_seconds)


static func _real(game_seconds: float) -> String:
	var real := int(round(game_seconds / TickManager.SPEED_MULTIPLIERS[1]))
	return "%d:%02d" % [real / 60, real % 60]
