class_name BuildingPowerController
extends RefCounted

## design_doc.md §2.1's "Going dark: buildings can be switched off" (D11).
## Owns one thing: whether a placed building is running, and the restart
## countdown when the player brings it back up. A fourth collaborator
## alongside BuildingConstructionController/BuildingHealthController/
## BuildingSustenanceController rather than more state on BuildingManager,
## same split and same reasons — see BuildingManager's own doc comment.
##
## Shape is deliberately BuildingConstructionController's, not a new one: a
## flag on the instance (BuildingInstance.is_powered_down) plus a pending job
## list here, ticked once per day_completed, mutating the instance on
## completion. That is what makes the state save/load-able through the same
## seam construction already uses (BuildingSaveEntry).
##
## What "off" costs and gives, verbatim from the spec: "An off building
## produces nothing, consumes no upkeep, emits no noise and no light.
## Restarting costs a delay proportional to building tier."
##
##   * produces/consumes nothing — BuildingSustenanceController skips its
##     daily_upkeep and daily_output, and CapacityAllocator.refund() below
##     releases the one-time Energy/Population entries at the same moment.
##   * no noise, no light — NoiseManager skips it (both the noise_output term
##     and the night lit_at_night attraction add-on), FogOfWarManager stops
##     treating it as lit, CombatCoordinator stops counting it as a
##     Searchlight, TacticalHexView drops its smoke/fire/light effects.
##
## Switching OFF is instant and free. It is the emergency move a horde is
## already walking toward; a delay on the way down would make it useless for
## the one job it exists to do. The whole cost is on the way back up.

signal powered_down(instance: BuildingInstance)
signal power_down_rejected(instance: BuildingInstance, reason: String)
signal restart_started(instance: BuildingInstance, days: int)
signal restart_rejected(instance: BuildingInstance, reason: String)
signal restart_cancelled(instance: BuildingInstance)
signal powered_up(instance: BuildingInstance)

## "Restarting costs a delay proportional to building tier" — read directly
## off BuildingDefinition.tier rather than through
## BuildingConstructionController.days_for()'s cost proxy, because the spec
## names tier and because the two are not the same ordering: a Tier 5
## Ordnance Complex and a Tier 1 Brickworks can land on the same clamped 1-4
## construction days, and "banking a Victorian furnace and bringing it back
## up is a real operation" has to bite hardest at the top of the tree.
## Tier 0 costs 1 day, Tier 5 costs 6. Placeholder balancing numbers, not an
## architecture decision.
const RESTART_DAYS_BASE: int = 1
const RESTART_DAYS_PER_TIER: int = 1

var _capacity: CapacityAllocator
var _pending: Array[Dictionary] = []  # {instance: BuildingInstance, days_remaining: int}

func _init(capacity: CapacityAllocator) -> void:
	_capacity = capacity

func restart_days_for(definition: BuildingDefinition) -> int:
	return RESTART_DAYS_BASE + definition.tier * RESTART_DAYS_PER_TIER

## Days left on this instance's restart, or 0 if it isn't restarting. Same
## shape (and same "0 means no job") contract as
## BuildingConstructionController.days_remaining_for().
func days_remaining_for(instance: BuildingInstance) -> int:
	for job in _pending:
		if job["instance"] == instance:
			return job["days_remaining"]
	return 0

## Off AND already coming back up, as opposed to off and staying off. The
## flag alone cannot tell them apart — see BuildingInstance.is_powered_down.
func is_restarting(instance: BuildingInstance) -> bool:
	return days_remaining_for(instance) > 0

## "" when `instance` can be switched off right now. A ruin has nothing left
## running and a construction site has not started yet, so both are refused
## rather than silently accepted into a state neither can be brought back out
## of meaningfully.
##
## An instance that is already dark AND mid-restart is ACCEPTED: power_down()
## reads that as "cancel the restart, stay dark". Without it the player is
## locked into coming back online — the countdown cannot be stopped, so a
## horde that turns toward the district on day 2 of a 5-day restart is met by
## a foundry that lights up on schedule. That is precisely the situation the
## mechanic exists for, so refusing here would break the feature at the one
## moment it matters.
func get_power_down_error(instance: BuildingInstance) -> String:
	if not instance:
		return "No such building."
	if instance.definition.always_powered:
		return "%s cannot be switched off." % instance.definition.display_name
	if instance.is_powered_down and not is_restarting(instance):
		return "%s is already switched off." % instance.definition.display_name
	if instance.is_ruined:
		return "%s is a ruin — there is nothing left to switch off." % instance.definition.display_name
	if instance.is_under_construction:
		return "%s is still under construction." % instance.definition.display_name
	return ""

func can_power_down(instance: BuildingInstance) -> bool:
	return get_power_down_error(instance).is_empty()

## Instant. Releases the Energy/Population capacity this building was holding
## (CapacityAllocator.refund(), the same call ruin makes) — an idle foundry
## is not drawing off the grid, and its labour is free again.
##
## Unlike ruin, current_population is left alone: see
## BuildingInstance.is_powered_down for why the people inside stay.
##
## Called on an already-dark, mid-restart instance it CANCELS the restart
## instead: the building never stopped being off, and restart() took no
## capacity (D53), so there is nothing to release and nothing to reverse —
## dropping the queued job is the whole operation.
func power_down(instance: BuildingInstance) -> bool:
	var error := get_power_down_error(instance)
	if not error.is_empty():
		power_down_rejected.emit(instance, error)
		return false
	if instance.is_powered_down:
		remove_pending(instance)
		restart_cancelled.emit(instance)
		return true
	instance.is_powered_down = true
	if _capacity:
		_capacity.refund(instance.definition)
	powered_down.emit(instance)
	return true

## Rubble is not "switched off" — it is rubble. Called by BuildingManager when
## BuildingHealthController ruins an instance, BEFORE the ruin is announced, so
## every listener sees one state rather than two overlapping ones.
##
## Both halves are load-bearing. Dropping the queued restart stops
## process_day() bringing a RUIN back online days later — it would draw the
## full Energy/Population allocation for a building that no longer exists and
## clear is_powered_down on it, and demolish() would then refuse to refund
## that allocation because the instance reads as a ruin. Clearing the flag
## keeps D53's invariant true in the other direction: repair() applies the
## allocation when the repair is ordered, so a ruin that repaired while still
## flagged off would come back holding capacity the flag says it does not
## hold, and the restart the UI would offer would apply it a second time.
##
## Deliberately emits neither powered_up nor restart_cancelled: nothing came
## back online and the player did not cancel anything. BuildingManager's
## building_ruined, which fires immediately after this, is the event.
func on_ruined(instance: BuildingInstance) -> void:
	remove_pending(instance)
	instance.is_powered_down = false

## "" when `instance` can start coming back up. The capacity check is
## BuildingHealthController.get_repair_error()'s, for the same reason: a
## restart re-connects the full operational power draw, and letting it
## proceed while the grid is short would create capacity from nothing.
func get_restart_error(instance: BuildingInstance) -> String:
	if not instance:
		return "No such building."
	if not instance.is_powered_down:
		return "%s is already running." % instance.definition.display_name
	if is_restarting(instance):
		return "%s is already restarting (%d days)." % [instance.definition.display_name, days_remaining_for(instance)]
	if instance.is_ruined:
		return "%s must be repaired before it can be restarted." % instance.definition.display_name
	if _capacity and not _capacity.can_afford_cost(instance.definition):
		return "Not enough Energy/Population capacity to restart %s." % instance.definition.display_name
	return ""

func can_restart(instance: BuildingInstance) -> bool:
	return get_restart_error(instance).is_empty()

## Queues the delay and takes NO capacity yet — the draw is made by
## process_day() at the moment is_powered_down flips back to false.
##
## This is deliberately NOT BuildingHealthController.repair()'s ordering,
## which applies capacity when the job is queued. Settling capacity on the
## flag instead of around it buys one invariant that has to hold for the
## whole feature: **an instance holds its Energy/Population allocation
## exactly when `not is_ruined and not is_powered_down`.** Every other site
## that has to reason about the allocation — most importantly
## BuildingHealthController.demolish(), which tops the draw back up on the
## way out — can then answer the question from the instance alone, with no
## reference to this controller's pending list.
##
## Repair's ordering shows what the alternative costs: an instance mid-repair
## has already had capacity applied but still reads is_ruined, so demolishing
## it silently leaks the allocation. That is a real pre-existing defect,
## noted rather than fixed here (it needs its own test and its own change).
##
## is_powered_down stays true for the whole countdown: the building is dark
## until process_day() says otherwise, which is the point of the delay.
func restart(instance: BuildingInstance) -> bool:
	var error := get_restart_error(instance)
	if not error.is_empty():
		restart_rejected.emit(instance, error)
		return false
	var days := restart_days_for(instance.definition)
	_pending.append({"instance": instance, "days_remaining": days})
	restart_started.emit(instance, days)
	return true

## Re-queues a restart read back out of a save. No capacity handling needed
## in either direction — restart() takes none, and the saved building is
## still flagged off, so the saved stockpile already excludes its allocation.
## Mirrors BuildingManager.load_save_entries()' construction re-queue,
## including its maxi(1, ...) guard against a corrupt 0-or-negative saved
## value stalling the job forever.
func load_pending_restart(instance: BuildingInstance, days_remaining: int) -> void:
	_pending.append({"instance": instance, "days_remaining": maxi(1, days_remaining)})

## Drops any queued restart for `instance` — BuildingManager calls this from
## remove_building(), same as it does for the construction and repair queues,
## so a demolished building leaves no job holding a dangling reference.
func remove_pending(instance: BuildingInstance) -> void:
	_pending = _pending.filter(func(job: Dictionary) -> bool: return job["instance"] != instance)

## The capacity draw is re-checked here, not just at restart() time: days
## passed, and whatever Energy or Population was free when the order was
## given may have been spent on something else since. A restart that can no
## longer be paid for is CANCELLED (the job is dropped, the building stays
## dark) and reported through restart_rejected, rather than either silently
## completing for free — CapacityAllocator.apply() discards spend()'s bool,
## so an unaffordable apply() takes the grant without the draw — or sitting
## in the queue forever as an invisible job. The player re-orders it once the
## grid recovers.
func process_day() -> void:
	var still_pending: Array[Dictionary] = []
	for job in _pending:
		job["days_remaining"] -= 1
		var instance: BuildingInstance = job["instance"]
		if job["days_remaining"] > 0:
			still_pending.append(job)
			continue
		if instance.is_ruined:
			# Belt and braces behind on_ruined(), which already drops the job:
			# completing a restart onto a ruin would apply the allocation to a
			# building that no longer stands.
			restart_rejected.emit(instance, "%s was destroyed before it could restart." % instance.definition.display_name)
			continue
		if _capacity and not _capacity.can_afford_cost(instance.definition):
			restart_rejected.emit(instance, "Not enough Energy/Population capacity to bring %s back online." % instance.definition.display_name)
			continue
		if _capacity:
			_capacity.apply(instance.definition)
		instance.is_powered_down = false
		powered_up.emit(instance)
	_pending = still_pending
