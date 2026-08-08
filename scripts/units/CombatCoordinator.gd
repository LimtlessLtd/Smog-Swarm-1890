class_name CombatCoordinator
extends Node

## Phase 5.4/5.9/5.10's missing live combat trigger — the single piece
## every one of those phases' own "no live combat trigger exists" notes has
## been pointing at. Sits ABOVE UnitManager, HordeManager,
## UnitOrderController and CombatEngine without any of them knowing this
## class exists (none of the four reference it, and it never mutates their
## private state directly — only the UnitInstance/Horde data Resources they
## already expose) — same "owns neither, only reads/computes from what's
## passed in" layering FogOfWarManager already uses over BuildingManager/
## LogisticsNetwork.
##
## Detects contact off HordeManager.horde_moved and UnitOrderController.
## unit_moved (every step, not just final arrival — a unit or horde merely
## passing through a shared hex still makes contact) rather than a
## per-frame poll, same "recompute on the signal" precedent as
## LogisticsNetwork/FogOfWarManager/DiscontentManager. Resolves ONE round
## of combat per contacting pair via CombatEngine.resolve_engagement(),
## then feeds the result back into both sides: the horde's size
## (Horde.apply_remaining_hp()), and — if the unit dies —
## HordeManager.add_casualty_zombies() (Phase 5.9), the exact reuse that
## method was built public for.
##
## **Decided (the horde-combat-stat gap this class exists to close):**
## Horde.HP_PER_ZOMBIE/DAMAGE_PER_ZOMBIE (see that class) convert a horde's
## headcount into the HP/damage pair CombatEngine needs. Placeholder
## balancing numbers, not an architecture decision, same framing as every
## other constant table in this project — but a real, callable decision
## instead of an indefinitely-deferred one.
##
## **Decided (engagement granularity):** one attacking UnitInstance per
## contact event — if several units and a horde share a hex, each
## unit/horde movement that triggers contact resolves its OWN independent
## engagement rather than the whole stack piling into one shared
## defender_hp pool. Simpler to reason about and extend later; revisit if
## playtesting finds hordes trivially outnumbered.
##
## **Decided (one-shot, not continuous):** an engagement fires off a
## MOVEMENT signal, not a per-frame "are these two still on the same hex"
## check — two survivors left sharing a hex after a round don't keep
## grinding each other down tick after tick just for standing still
## together; only a fresh move by either side (or the next horde/unit that
## wanders in) triggers another round. A real continuous siege is Phase
## 5.10's `ATTACKING` state, still unbuilt; this is deliberately a lighter
## "you bumped into each other" skirmish resolver, not that.
##
## **Decided (contact matters however it happens):** engagement triggers
## regardless of the unit's current order — MOVE, PATROL, ATTACK_MOVE, even
## a HOLD/GARRISON unit a horde walks onto, all fight the same way. Matches
## the design doc's own Phase 5.10 framing ("a horde doesn't need to be
## actively attracted to trigger a siege — pure chance wandering into a
## player-held hex triggers the same ATTACKING transition"). Which means
## ATTACK_MOVE genuinely has no distinct mechanical behavior left to build
## here — ordering a unit to a horde's hex and ordering it to merely pass
## through both resolve identically once contact happens, which is exactly
## right: the "attack" in attack-move was never about a special combat
## mode, only about deliberately seeking a fight out (a targeting/UI
## concern for a future order-issuing screen, Phase 6+, not a resolution one).
##
## **Phase 5.7 (Morale & Veterancy):** `UnitMorale.get_damage_multiplier()`
## folds a unit's current morale (HP/equipment/rank/tier) and veterancy
## bonus (rank alone) into the one scalar `CombatEngine.resolve_engagement()`
## accepts as `damage_multiplier` — computed fresh per engagement, never
## cached. **Phase 5.1's Day bonus (`DAY_DAMAGE_MULTIPLIER`) stacks
## multiplicatively on top of that same scalar**, `_engage()`'s own doing,
## not `UnitMorale`'s — the two are independent inputs feeding one output,
## same "orchestration layer folds independent systems together" role this
## class already plays for morale + garrison/searchlight incoming-damage. A
## win that destroys a Horde outright increments `UnitInstance.kill_count`
## (`UnitMorale.get_rank()`'s own doc comment explains why "destroys a
## Horde" is the decided definition of a kill). `CombatCoordinator` is the
## only thing that references both `CombatEngine` and `UnitMorale` —
## neither references the other or this class back.
##
## **Phase 2.5.4 (Individual Units & Squads):** `UnitInstance.get_squad_headcount()`
## derives a Tier 0-3 unit's visible figure count from `current_hp` alone —
## nothing new stored. `_engage()` snapshots that headcount before and after
## `CombatEngine.resolve_engagement()` and spawns one casualty zombie
## (`HordeManager.add_casualty_zombies()`) per figure the engagement cost,
## generalizing the old "only on total unit loss" trigger to "every fallen
## squad member, mid-fight" — a Tier 4-5 unit (headcount always 1 while
## alive) still only ever fires this once, on its own death, so this is a
## strict generalization, not a behavior change for those.
##
## **Garrison/Searchlight defense bonus, now real:** `_garrison_incoming_multiplier()`
## folds into `CombatEngine.resolve_engagement()`'s new `incoming_damage_multiplier`
## parameter — a flat `GARRISON_INCOMING_DAMAGE_MULTIPLIER` reduction whenever
## the defending `UnitInstance.order` is `GARRISON`, stacking with a further
## `SEARCHLIGHT_NIGHT_INCOMING_DAMAGE_MULTIPLIER` reduction at night if a
## non-ruined Searchlight Tower's own `vision_radius` reaches the unit's
## hex — "during night defense, granting combat bonuses to garrisoned
## units" (design doc Phase 4.1), previously blocked purely on
## `CombatEngine` having no input for it at all. `TimeCycleManager.is_night()`
## (autoload) and the already-optional `building_manager_path` (wired in
## Phase 5.12 for `_siege_buildings()`) supply everything this needs — no
## new export.
##
## **Still NOT implemented:**
##   - Phase 5.10's ATTACKING state as a deliberate seek-out-a-target
##     behavior (the wall-siege slice — a horde attacking whichever segment
##     its own WANDERING drift happens to reach — is real now, see
##     `HordeManager._siege_wall()`; a horde CHOOSING a target on purpose
##     still needs the still-nonexistent ATTRACTED/noise system), and Phase
##     5.8's territory capture is a separate class (`TerritoryController`)
##     entirely, reacting to `BuildingManager.building_ruined` rather than
##     anything here.
##   - The full defense-in-depth cascade (outer wall -> legacy wall ->
##     garrison -> buildings, Phase 4.2) — `_siege_buildings()` (Phase
##     5.10/5.12) covers the simplest case (no wall, no garrison, nothing
##     between a horde and an undefended building) and `HordeManager`'s own
##     wall siege covers "a wall blocks a horde's step, full stop" — but
##     there's still no distinct "outer" vs "legacy inner" wall tier, so a
##     horde that breaches one segment just walks into the hex behind it,
##     it doesn't hit a second layer.
##   - Phase 5.7's own "reasonable fifth" morale input (a severe famine
##     ratio) — see UnitMorale's own doc comment for why it's not wired.

signal engagement_resolved(instance: UnitInstance, horde: Horde, result: Dictionary)

## Design doc Phase 5.9: "every civilian and military unit lost becomes a
## zombie" — 1 lost unit becomes 1 zombie at the site, same
## "not a token/percentage loss" spirit as the rest of 5.9, sized for a
## single unit rather than a whole building's housed population (which
## civilians_starved/a future building-ruins event already handle at their
## own scale). A placeholder balancing number, not an architecture decision.
##
## Phase 2.5.4 generalizes "1 lost unit" to "1 lost derived squad figure" —
## see _engage()'s figures_lost computation below. A Tier 4-5 (single-model,
## not squad-rendered) unit's headcount is always 1 while alive, so for
## those this constant still fires exactly once, on the unit's own death —
## same effective behavior as before this phase, just derived generically
## instead of special-cased on is_destroyed().
const CASUALTY_ZOMBIES_PER_UNIT: int = 1

## Design doc Phase 4.1/5.6: "granting combat bonuses to garrisoned units" /
## "a stationary defense bonus instead of patrolling" — placeholder
## balancing numbers, not an architecture decision, same framing as every
## other constant table in this project. The Searchlight bonus stacks
## (multiplies) with the flat Garrison one, not replaces it.
const GARRISON_INCOMING_DAMAGE_MULTIPLIER: float = 0.75          ## 25% less incoming damage while GARRISON, any time of day.
const SEARCHLIGHT_NIGHT_INCOMING_DAMAGE_MULTIPLIER: float = 0.6  ## A further 40% off at night, specifically near a lit Searchlight Tower.

## Design doc Phase 5.1's Day Phase bullet: "Military units get increased
## movement speed and damage" — the damage half (see
## UnitOrderController.DAY_MOVE_SPEED_MULTIPLIER for the movement half,
## which lives there instead since this class has no movement code of its
## own). No exact number in the design doc — a placeholder balancing
## multiplier, same disclaimer every other constant table here already
## carries. Applies to every unit's OUTGOING damage during Day, not a
## horde's — the design doc frames this bullet as a benefit specifically
## for "Military units", not a general Day/Night combat-wide swing.
const DAY_DAMAGE_MULTIPLIER: float = 1.1

@export var unit_manager_path: NodePath
@export var horde_manager_path: NodePath
@export var unit_order_controller_path: NodePath
@export var resource_manager_path: NodePath  ## Optional — unset always resolves as "Gunpowder available", same "gracefully skip it" convention as every other optional dependency.
@export var building_manager_path: NodePath  ## Optional — Phase 5.12's undefended-building siege trigger; unset gracefully skips it, same convention as every other optional dependency here.

var _unit_manager: UnitManager
var _horde_manager: HordeManager
var _resource_manager: ResourceManager
var _building_manager: BuildingManager

func _ready() -> void:
	if unit_manager_path != NodePath():
		_unit_manager = get_node(unit_manager_path)
	if horde_manager_path != NodePath():
		_horde_manager = get_node(horde_manager_path)
		_horde_manager.horde_moved.connect(_on_horde_moved)
	if unit_order_controller_path != NodePath():
		var unit_order_controller: UnitOrderController = get_node(unit_order_controller_path)
		unit_order_controller.unit_moved.connect(_on_unit_moved)
	if resource_manager_path != NodePath():
		_resource_manager = get_node(resource_manager_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)

func _on_horde_moved(horde: Horde, _from_coord: Vector2i, to_coord: Vector2i) -> void:
	var defenders: Array[UnitInstance] = []
	if _unit_manager:
		defenders = _unit_manager.get_units_at(to_coord)
	for instance in defenders:
		_engage(instance, horde)
	if defenders.is_empty():
		_siege_buildings(horde, to_coord)

func _on_unit_moved(instance: UnitInstance, _from_coord: Vector2i, to_coord: Vector2i) -> void:
	if not _horde_manager:
		return
	for horde in _horde_manager.get_hordes_at(to_coord):
		_engage(instance, horde)

func _engage(instance: UnitInstance, horde: Horde) -> void:
	if instance.is_destroyed() or horde.size <= 0:
		return  ## Already resolved earlier this same contact event (e.g. multiple units on one hex vs. one horde).

	var gunpowder_available := true
	if _resource_manager:
		gunpowder_available = _resource_manager.get_amount(GameEnums.ResourceType.GUNPOWDER) > 0.0

	var damage_multiplier := UnitMorale.get_damage_multiplier(instance, gunpowder_available)
	if TimeCycleManager.is_day():
		damage_multiplier *= DAY_DAMAGE_MULTIPLIER
	var incoming_damage_multiplier := _garrison_incoming_multiplier(instance)
	var headcount_before := instance.get_squad_headcount()
	var result := CombatEngine.resolve_engagement(instance, gunpowder_available, horde.get_combat_hp(), horde.get_combat_damage(), damage_multiplier, incoming_damage_multiplier)
	horde.apply_remaining_hp(result.defender_hp_remaining)
	engagement_resolved.emit(instance, horde, result)

	if horde.size <= 0:
		instance.kill_count += 1  # Phase 5.7: destroying a Horde outright is the decided definition of "a kill" — see UnitMorale.get_rank()'s own doc comment.
		if _horde_manager:
			_horde_manager.remove_horde(horde)

	# Phase 2.5.4, decided: "a fallen squad member becomes a real, fightable
	# threat" — every derived headcount point this engagement cost `instance`
	# (an HP threshold crossed, including the unit's own final death, which
	# is just its headcount's last point) spawns that many casualty zombies
	# right here, mid-fight, not only once the whole unit is wiped out.
	var headcount_after := instance.get_squad_headcount()
	var figures_lost := headcount_before - headcount_after
	if figures_lost > 0 and _horde_manager:
		_horde_manager.add_casualty_zombies(instance.hex_coord, figures_lost * CASUALTY_ZOMBIES_PER_UNIT)

	if instance.is_destroyed() and _unit_manager:
		_unit_manager.remove_unit(instance)

## Design doc Phase 5.6/4.1: a `GARRISON`-ordered unit takes less incoming
## damage, stacking further at night if a non-ruined Searchlight Tower's own
## `vision_radius` reaches this hex — "illuminate perimeter walls ...
## granting combat bonuses to garrisoned units". `HOLD` deliberately does
## NOT qualify — the design doc frames this as Garrison's own payoff over
## plain Hold (see `UnitOrderController`'s own doc comment on Phase 2.5.4's
## healing mechanic making the same Garrison-vs-Hold distinction).
func _garrison_incoming_multiplier(instance: UnitInstance) -> float:
	if instance.order != GameEnums.UnitOrderType.GARRISON:
		return 1.0
	var multiplier := GARRISON_INCOMING_DAMAGE_MULTIPLIER
	if _building_manager and TimeCycleManager.is_night() and _is_near_searchlight_tower(instance.hex_coord):
		multiplier *= SEARCHLIGHT_NIGHT_INCOMING_DAMAGE_MULTIPLIER
	return multiplier

func _is_near_searchlight_tower(coord: Vector2i) -> bool:
	for instance in _building_manager.get_all_buildings():
		if instance.is_ruined or instance.definition.building_type != GameEnums.BuildingType.SEARCHLIGHT_TOWER:
			continue
		if HexCoord.distance(instance.hex_coord, coord) <= instance.definition.vision_radius:
			return true
	return false

## Design doc Phase 5.10/5.12: closes the exact gap this class's own doc
## comment used to flag ("an undefended-but-covered hex currently has
## nothing to fight back with, since Phase 5.12's building combat doesn't
## exist") — a horde reaching a hex with NO defending UnitInstance now
## sieges whatever non-ruined building stands there instead of the contact
## being a no-op. One building damaged per contact event (same "one
## attacking side, one engagement" granularity _engage() already uses for
## units) — the first non-ruined instance found, not every building on the
## hex at once; a hex with several buildings falls one at a time across
## repeated contacts, not in a single visit.
##
## Deliberately does NOT check Zone of Control coverage or wall segments —
## this is the SIMPLEST possible "the layer in front has failed" case
## (there is no wall, no garrison here, nothing between the horde and the
## building but the building itself), not the full defense-in-depth cascade
## (outer wall -> legacy wall -> garrison -> buildings) Phase 4.1/4.2's own
## still-missing outer/inner-wall distinction and horde-vs-wall targeting
## describe. Extends naturally once those exist; doesn't block on them.
func _siege_buildings(horde: Horde, coord: Vector2i) -> void:
	if not _building_manager or horde.size <= 0:
		return
	for instance in _building_manager.get_buildings_at(coord):
		if instance.is_ruined:
			continue
		_building_manager.damage_building(instance, horde.get_combat_damage())
		return  # One building per contact event — see this method's own doc comment.
