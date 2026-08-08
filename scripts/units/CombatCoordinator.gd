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

## Design doc, user request: a Dragoon's charge stuns whatever it hits for
## "a second" — a literal number from the request, not a derived one. The
## Steam-Tractor Landship's TRAMPLE_KNOCKBACK deliberately does NOT use
## this — see _apply_special_ability_effects()'s own doc comment for why.
const CHARGE_STUN_SECONDS: float = 1.0

@export var unit_manager_path: NodePath
@export var horde_manager_path: NodePath
@export var unit_order_controller_path: NodePath
@export var resource_manager_path: NodePath  ## Optional — unset always resolves as "Gunpowder available", same "gracefully skip it" convention as every other optional dependency.
@export var building_manager_path: NodePath  ## Optional — Phase 5.12's undefended-building siege trigger; unset gracefully skips it, same convention as every other optional dependency here.
@export var hex_grid_map_path: NodePath      ## Optional — user request's CHARGE_KNOCKBACK/TRAMPLE_KNOCKBACK abilities need to validate a knockback destination is a real, passable hex; unset just means those two abilities never physically knock a horde anywhere (a stun from CHARGE_KNOCKBACK still applies regardless — see _knock_back()'s own doc comment).

var _unit_manager: UnitManager
var _horde_manager: HordeManager
var _resource_manager: ResourceManager
var _building_manager: BuildingManager
var _hex_grid_map: HexGridMap

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
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)

func _on_horde_moved(horde: Horde, from_coord: Vector2i, to_coord: Vector2i) -> void:
	var defenders: Array[UnitInstance] = []
	if _unit_manager:
		defenders = _unit_manager.get_units_at(to_coord)
	for instance in defenders:
		_engage(instance, horde, from_coord, to_coord)
	if defenders.is_empty():
		_siege_buildings(horde, to_coord)

func _on_unit_moved(instance: UnitInstance, from_coord: Vector2i, to_coord: Vector2i) -> void:
	if not _horde_manager:
		return
	for horde in _horde_manager.get_hordes_at(to_coord):
		_engage(instance, horde, from_coord, to_coord)

## `movement_from`/`movement_to` are whichever side's own move triggered
## this specific contact event (the horde's for `_on_horde_moved`, the
## unit's for `_on_unit_moved`) — passed through purely so
## `_apply_special_ability_effects()` can knock a surviving horde back
## along that same line of travel; ordinary engagements ignore both.
func _engage(instance: UnitInstance, horde: Horde, movement_from: Vector2i, movement_to: Vector2i) -> void:
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
	else:
		_apply_special_ability_effects(instance, horde, movement_from, movement_to)

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

## Design doc, user request: "each special unit type should do something
## special." Called only once `_engage()` already knows `horde` survived
## this round (a destroyed horde has nothing left to knock back or stun).
## CHARGE_KNOCKBACK (Dragoon) gets both a knockback AND a stun; TRAMPLE_
## KNOCKBACK (Steam-Tractor Landship) gets the same knockback with NO
## stun — deliberately: the Landship is a slow damage sponge that shoves
## zombies aside as it grinds forward, not a shock unit that needs to
## freeze its target the way a fast charging Dragoon does. Every other
## ability value (including plain NONE) does nothing here — Outrider's
## unarmed-ness, Chasseur/Grenadier's damage bonuses, and the Armored Car's
## mobile ZoC aura are all expressed elsewhere (UnitCatalog's stat curve,
## LogisticsNetwork.recompute() respectively), not in this method.
func _apply_special_ability_effects(instance: UnitInstance, horde: Horde, movement_from: Vector2i, movement_to: Vector2i) -> void:
	match instance.definition.ability:
		GameEnums.UnitAbility.CHARGE_KNOCKBACK:
			_knock_back(horde, movement_from, movement_to)
			horde.stun_seconds_remaining = CHARGE_STUN_SECONDS
		GameEnums.UnitAbility.TRAMPLE_KNOCKBACK:
			_knock_back(horde, movement_from, movement_to)

## Displaces `horde` one further hex along whichever line of travel caused
## this contact — `movement_to + (movement_to - movement_from)`, i.e. "the
## same direction the moving side was already heading, continued one more
## step," which reads correctly regardless of whether the HORDE walked into
## the unit or the UNIT walked into the horde (both callers pass their OWN
## from/to pair — see _engage()'s own doc comment). Requires an optional
## `_hex_grid_map` to validate the destination is a real, passable hex
## (never shoves a horde into open ocean or a marsh) — unset, or no valid
## destination (map edge, impassable terrain), just means the knockback
## itself fizzles; a CHARGE_KNOCKBACK's stun is applied by the caller
## regardless, since being stunned doesn't require successfully being
## shoved anywhere. Directly mutates the passed-in Horde Resource (same
## "manager mutates a passed-in Resource, engine/coordinator stays
## ignorant of who owns it" pattern CombatEngine/WallManager.damage_segment()
## already use) rather than going through HordeManager — this does NOT
## emit HordeManager.horde_moved, a deliberate, minor, accepted gap: any
## listener keyed off that signal (StrategicOverlayManager's marker,
## TerritoryController) just reflects the knock-back on the horde's own
## NEXT real movement tick instead of instantly, not incorrectly.
func _knock_back(horde: Horde, movement_from: Vector2i, movement_to: Vector2i) -> void:
	if movement_from == movement_to or not _hex_grid_map:
		return
	var target := movement_to + (movement_to - movement_from)
	var cell := _hex_grid_map.get_cell(target)
	if cell == null or not cell.is_passable():
		return
	horde.hex_coord = target
	horde.local_position = Vector2.ZERO
	horde.path.clear()  # Forces HordeManager to replan fresh from the new position next _advance_horde() call.
