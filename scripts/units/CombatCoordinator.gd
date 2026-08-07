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
## cached. A win that destroys a Horde outright increments
## `UnitInstance.kill_count` (`UnitMorale.get_rank()`'s own doc comment
## explains why "destroys a Horde" is the decided definition of a kill).
## `CombatCoordinator` is the only thing that references both `CombatEngine`
## and `UnitMorale` — neither references the other or this class back.
##
## **Still NOT implemented:**
##   - Phase 5.10's ATTACKING state, wall-segment targeting, and Phase
##     5.8's territory capture — this resolves an engagement wherever units
##     and a horde meet, it doesn't make a horde seek one out, target a
##     wall segment, or flip district control on a win/loss.
##   - Combat bonuses beyond morale/veterancy (Searchlight Tower night
##     defense, Garrison orders' "stationary defense bonus") — CombatEngine
##     has no inputs for either yet, so neither applies here either.
##   - Building-vs-horde combat (a horde besieging an undefended settlement
##     directly) — this only resolves engagements against a UnitInstance;
##     Phase 5.12's building HP/ruins state doesn't exist yet to be a
##     defender_hp source of its own.
##   - Phase 5.7's own "reasonable fifth" morale input (a severe famine
##     ratio) — see UnitMorale's own doc comment for why it's not wired.

signal engagement_resolved(instance: UnitInstance, horde: Horde, result: Dictionary)

## Design doc Phase 5.9: "every civilian and military unit lost becomes a
## zombie" — 1 lost unit becomes 1 zombie at the site, same
## "not a token/percentage loss" spirit as the rest of 5.9, sized for a
## single unit rather than a whole building's housed population (which
## civilians_starved/a future building-ruins event already handle at their
## own scale). A placeholder balancing number, not an architecture decision.
const CASUALTY_ZOMBIES_PER_UNIT: int = 1

@export var unit_manager_path: NodePath
@export var horde_manager_path: NodePath
@export var unit_order_controller_path: NodePath
@export var resource_manager_path: NodePath  ## Optional — unset always resolves as "Gunpowder available", same "gracefully skip it" convention as every other optional dependency.

var _unit_manager: UnitManager
var _horde_manager: HordeManager
var _resource_manager: ResourceManager

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

func _on_horde_moved(horde: Horde, _from_coord: Vector2i, to_coord: Vector2i) -> void:
	if not _unit_manager:
		return
	for instance in _unit_manager.get_units_at(to_coord):
		_engage(instance, horde)

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
	var result := CombatEngine.resolve_engagement(instance, gunpowder_available, horde.get_combat_hp(), horde.get_combat_damage(), damage_multiplier)
	horde.apply_remaining_hp(result.defender_hp_remaining)
	engagement_resolved.emit(instance, horde, result)

	if horde.size <= 0:
		instance.kill_count += 1  # Phase 5.7: destroying a Horde outright is the decided definition of "a kill" — see UnitMorale.get_rank()'s own doc comment.
		if _horde_manager:
			_horde_manager.remove_horde(horde)

	if instance.is_destroyed():
		if _horde_manager:
			_horde_manager.add_casualty_zombies(instance.hex_coord, CASUALTY_ZOMBIES_PER_UNIT)
		if _unit_manager:
			_unit_manager.remove_unit(instance)
