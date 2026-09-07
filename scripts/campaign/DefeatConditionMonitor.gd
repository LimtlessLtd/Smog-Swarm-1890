class_name DefeatConditionMonitor
extends Node

## vision.md P4 ("Losing is real"): the campaign-level defeat check. Until this
## existed the only loss concept in the game was
## TerritoryController.is_lost(coord), which is one hex flipping contested —
## not a campaign ending. Nothing could end a run.
##
## **Defeat is economic/capability elimination, not territorial.** That call is
## already settled (backlog.md 7.6, quoted in vision.md P4) and this class does
## not re-open it: losing every district but one is a crisis, not a loss.
## The game ends only when all three hold at once:
##
##   (a) the stockpile cannot afford a single unit in UnitCatalog OR a single
##       building in BuildingCatalog — no way to make an army or retake ground;
##   (b) nothing still standing produces anything daily; and
##   (c) no standing building can train a unit.
##
## Any one of the three failing means the player still has a thread to pull,
## and the campaign continues.
##
## **Two readings this had to settle, recorded so they are not silently
## re-derived.** 7.6's clause (c) is "no remaining building capable of
## recruiting a unit *or expanding onto a new hex*". Nothing in the game gates
## expansion on a building — placement is checked against resources, build
## rights and terrain (BuildingManager.get_placement_error()), never against
## owning some particular structure — so that half of (c) is exactly (a)'s
## "cannot afford any building" and is not checked twice. And (a) is read
## against the FULL catalogues rather than what tech has unlocked: a player who
## cannot afford the cheapest thing they have researched but could afford
## something cheaper they have not is still, correctly, not eliminated.
##
## Evaluated once per day off TickManager.day_completed, not per frame. Every
## input moves on the daily tick (production is banked there, and a stockpile
## only changes on a player action or that tick), and the check iterates both
## catalogues, so a per-frame version would burn the cost hundreds of times for
## an answer that cannot have changed.
##
## **Nothing here is saved, deliberately.** All three conditions are derived from
## BuildingManager and ResourceManager, both of which SaveLoadManager already
## round-trips, so a loaded game re-derives the same verdict on its next daily
## tick rather than restoring a second copy that could drift from the world it
## describes — the same "derived, never stored" rule D1/D2 apply to
## infestation and is_cleared. The one consequence, accepted: loading a save
## taken after the campaign ended re-raises the loss up to a day later rather
## than immediately, and a player who was at risk is warned again on load.
##
## Raises no player-facing event itself. It emits signals and EventManager
## connects to them, matching how territory loss, wall breaches and food
## bands already reach the player — the alert layer subscribes to simulation,
## simulation never reaches into the alert layer. A CRITICAL event is what
## stops the clock, via AlertManager's existing auto-pause-above-INFO rule,
## so nothing here touches TickManager either.

## Emitted once, the first time all three conditions hold. Latched — see
## _defeated. A campaign that has ended does not un-end.
signal campaign_lost(reasons: Array[String])

## Emitted whenever the number of satisfied conditions crosses into or out of
## AT_RISK_CONDITIONS. P4 asks for "clear warning before the point of no
## return"; this is that warning's data source.
signal defeat_risk_changed(is_at_risk: bool, reasons: Array[String])

@export var building_manager_path: NodePath
@export var resource_manager_path: NodePath

## How many of the three conditions must hold before the player is warned.
## 2 means the warning fires with exactly one thread left to pull, which is
## the last moment it is still actionable.
const AT_RISK_CONDITIONS: int = 2

var _building_manager: BuildingManager
var _resource_manager: ResourceManager

## Latched at the first evaluation that sees a standing building, and never
## cleared. Without it a defeat check is trivially satisfied during the frames
## between _ready() and BuildingManager.seed_starting_buildings() — no
## buildings means no production, no trainer, and every campaign would end
## before it started. "Has the colony ever existed" is the precondition for
## "has the colony been eliminated".
var _armed: bool = false
var _defeated: bool = false
var _at_risk: bool = false

func _ready() -> void:
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
	if resource_manager_path != NodePath():
		_resource_manager = get_node(resource_manager_path)
	TickManager.day_completed.connect(_on_day_completed)

func is_defeated() -> bool:
	return _defeated

func is_at_risk() -> bool:
	return _at_risk

## The three conditions as a plain Dictionary, so a verification can assert
## each one independently instead of only observing the combined verdict:
## {"no_affordable_expansion": bool, "no_production": bool, "no_trainer": bool,
##  "reasons": Array[String]}.
##
## Pure — evaluating does not latch anything. evaluate_now() is the caller
## that acts on it.
func evaluate() -> Dictionary:
	var no_affordable_expansion := _nothing_affordable()
	var no_production := _nothing_produced()
	var no_trainer := _no_standing_trainer()
	var reasons: Array[String] = []
	if no_affordable_expansion:
		reasons.append("cannot afford any unit or any building")
	if no_production:
		reasons.append("nothing standing produces anything")
	if no_trainer:
		reasons.append("no standing building can train a unit")
	return {
		"no_affordable_expansion": no_affordable_expansion,
		"no_production": no_production,
		"no_trainer": no_trainer,
		"reasons": reasons,
	}

## Runs the check and emits whatever it implies. Public so a verification can
## drive it without waiting for a day to roll over, matching
## InfestationManager.run_daily_tick()'s own reason for being public.
func evaluate_now() -> void:
	if _defeated:
		return  ## Latched — see _defeated.
	if not _armed:
		if _standing_buildings().is_empty():
			return
		_armed = true

	var result := evaluate()
	var satisfied := 0
	for key in ["no_affordable_expansion", "no_production", "no_trainer"]:
		if bool(result[key]):
			satisfied += 1
	var reasons: Array[String] = result["reasons"]

	if satisfied >= 3:
		_defeated = true
		_at_risk = true
		campaign_lost.emit(reasons)
		return

	var at_risk := satisfied >= AT_RISK_CONDITIONS
	if at_risk != _at_risk:
		_at_risk = at_risk
		defeat_risk_changed.emit(at_risk, reasons)

func _on_day_completed(_day_number: int) -> void:
	evaluate_now()

## (a). True when the stockpile covers neither the cheapest unit nor the
## cheapest building. Asks ResourceManager.can_afford() rather than comparing
## totals by hand so multi-resource costs are judged by the same rule that
## actually gates a purchase.
func _nothing_affordable() -> bool:
	if not _resource_manager:
		return false  ## No stockpile wired means no way to tell — never eliminate on missing information.
	for definition in UnitCatalog.get_all_definitions():
		if _resource_manager.can_afford(definition.training_cost):
			return false
	for definition in BuildingCatalog.get_all_definitions():
		if _resource_manager.can_afford(definition.construction_cost):
			return false
	return true

## (b). Reuses BuildingManager.get_projected_daily_flow(), which is the same
## math apply_day() banks — a second "what counts as producing" rule here
## would drift from the one the economy actually runs on. That flow already
## excludes ruined, under-construction and powered-down buildings, and
## excludes ENERGY/POPULATION as capacity grants rather than daily flow.
##
## Note what this means for going dark (design_doc.md §2.1): a player who
## switches off every building to hide from a horde reads as producing
## nothing. That is correct and not a trap — they keep their stockpile and
## their trainers, so (a) and (c) both fail and the campaign continues.
func _nothing_produced() -> bool:
	if not _building_manager:
		return false
	var produced: Dictionary = _building_manager.get_projected_daily_flow().get("produced", {})
	for resource_type in produced:
		if float(produced[resource_type]) > 0.0:
			return false
	return true

## (c). A standing building is one that is neither ruined nor still under
## construction. Powered-down deliberately still counts: the player can switch
## a barracks back on, so owning one is not elimination — it is a delay of
## BuildingPowerController.restart_days_for() days.
func _no_standing_trainer() -> bool:
	if not _building_manager:
		return false
	for instance in _standing_buildings():
		if instance.definition.can_train_units:
			return false
	return true

func _standing_buildings() -> Array[BuildingInstance]:
	var result: Array[BuildingInstance] = []
	if not _building_manager:
		return result
	for instance in _building_manager.get_all_buildings():
		if instance.is_ruined or instance.is_under_construction:
			continue
		result.append(instance)
	return result
