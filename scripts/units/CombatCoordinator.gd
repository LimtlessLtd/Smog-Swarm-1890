class_name CombatCoordinator
extends Node

## The live combat trigger. Sits ABOVE UnitManager, HordeManager,
## UnitOrderController and CombatEngine without any of them knowing this
## class exists (none reference it, and it never mutates their private
## state directly — only the UnitInstance/Horde data Resources they already
## expose) — same "owns neither, only reads/computes from what's passed in"
## layering FogOfWarManager uses over BuildingManager/LogisticsNetwork.
##
## Detects contact off HordeManager.horde_moved and UnitOrderController.unit_moved
## (every step, not just final arrival — a unit or horde merely passing
## through a shared hex still makes contact) rather than a per-frame poll,
## same "recompute on the signal" precedent as LogisticsNetwork/
## FogOfWarManager/DiscontentManager. Resolves ONE round of combat per
## contacting pair via CombatEngine.resolve_engagement(), then feeds the
## result back into both sides: the horde's size (Horde.apply_remaining_hp()),
## and — if the unit dies — HordeManager.add_casualty_zombies().
##
## Horde.HP_PER_ZOMBIE/DAMAGE_PER_ZOMBIE convert a horde's headcount into
## the HP/damage pair CombatEngine needs — placeholder balancing numbers,
## not an architecture decision, same framing as every other constant table
## in this project.
##
## Engagement granularity: one attacking UnitInstance per contact event — if
## several units and a horde share a hex, each unit/horde movement that
## triggers contact resolves its OWN independent engagement rather than the
## whole stack piling into one shared defender_hp pool.
##
## Movement is not the only way contact happens. The two signals above are
## the only ones this class subscribes to, but engage_units_at() below is
## public so a caller that produces contact WITHOUT movement can resolve a
## round: ResidentDefenseController condenses a hex's own resident zombies
## into a defending horde underneath a unit that never moved, on a timer, so
## a unit holding infested ground now grinds tick after tick instead of
## trading one round per crossing. That is a deliberate change from this
## class's original "one-shot skirmish resolver" framing — without it,
## design_doc.md §2.1's endless tide stalls the moment the defending horde
## reaches its frontage size and neither side moves again.
##
## Contact matters however it happens: engagement triggers regardless of
## the unit's current order — MOVE, PATROL, ATTACK_MOVE, even a HOLD/
## GARRISON unit a horde walks onto, all fight the same way. Which means
## ATTACK_MOVE has no distinct mechanical behavior left to build here —
## ordering a unit to a horde's hex and ordering it to merely pass through
## both resolve identically once contact happens: the "attack" in
## attack-move was never about a special combat mode, only about
## deliberately seeking a fight out (a targeting/UI concern, not a
## resolution one).
##
## UnitMorale.get_damage_multiplier() folds a unit's current morale (HP/
## equipment/rank/tier) and veterancy bonus (rank alone) into the one
## scalar CombatEngine.resolve_engagement() accepts as damage_multiplier —
## computed fresh per engagement, never cached. DAY_DAMAGE_MULTIPLIER
## stacks multiplicatively on top of that same scalar, this class's own
## doing, not UnitMorale's — two independent inputs feeding one output. A
## win that destroys a Horde outright increments UnitInstance.kill_count
## (see UnitMorale.get_rank()'s own doc comment for why "destroys a Horde"
## is the decided definition of a kill). CombatCoordinator is the only
## class referencing both CombatEngine and UnitMorale — neither references
## the other or this class back.
##
## UnitInstance.get_squad_headcount() derives a Tier 0-3 unit's visible
## figure count from current_hp alone — nothing new stored. _engage()
## snapshots that headcount before and after resolve_engagement() and spawns
## one casualty zombie per figure the engagement cost — every fallen squad
## member, mid-fight, not only once the whole unit is wiped out. A Tier 4-5
## (single-model) unit's headcount is always 1 while alive, so this still
## fires exactly once for those, on the unit's own death.
##
## _garrison_incoming_multiplier() folds into resolve_engagement()'s
## incoming_damage_multiplier parameter — a flat GARRISON_INCOMING_DAMAGE_MULTIPLIER
## reduction whenever the defending UnitInstance.order is GARRISON, stacking
## with a further SEARCHLIGHT_NIGHT_INCOMING_DAMAGE_MULTIPLIER reduction at
## night if a non-ruined Searchlight Tower's own vision_radius reaches the
## unit's hex. TimeCycleManager.is_night() and the already-optional
## building_manager_path supply everything this needs — no new export.
##
## Not implemented yet:
##   - ATTACKING as a deliberate seek-out-a-target behavior against
##     buildings/ZoC hexes — the wall-siege slice (HordeManager._siege_wall())
##     is real; a horde CHOOSING a target on purpose still needs the
##     ATTRACTED/noise system to drive it. Territory capture is a separate
##     class (TerritoryController), reacting to BuildingManager.building_ruined
##     rather than anything here.
##   - The full defense-in-depth cascade (outer wall -> legacy wall ->
##     garrison -> buildings) — _siege_buildings() covers the simplest case
##     (no wall, no garrison, nothing between a horde and an undefended
##     building) and HordeManager's own wall siege covers "a wall blocks a
##     horde's step, full stop" — but there's still no distinct outer vs.
##     legacy-inner wall tier, so a horde that breaches one segment just
##     walks into the hex behind it, not a second layer.
##   - A severe-famine morale input — see UnitMorale's own doc comment for
##     why it's not wired.

signal engagement_resolved(instance: UnitInstance, horde: Horde, result: Dictionary)

## 1 lost unit becomes 1 zombie at the site — a placeholder balancing
## number. Generalizes to "1 lost derived squad figure" (see _engage()'s
## figures_lost computation) — a Tier 4-5 unit's headcount is always 1 while
## alive, so for those this still fires exactly once, on the unit's death.
const CASUALTY_ZOMBIES_PER_UNIT: int = 1

## Placeholder balancing numbers, not an architecture decision. The
## Searchlight bonus stacks (multiplies) with the flat Garrison one, not replaces it.
const GARRISON_INCOMING_DAMAGE_MULTIPLIER: float = 0.75          ## 25% less incoming damage while GARRISON, any time of day.
const SEARCHLIGHT_NIGHT_INCOMING_DAMAGE_MULTIPLIER: float = 0.6  ## A further 40% off at night, specifically near a lit Searchlight Tower.

## "Military units get increased movement speed and damage" (Day) — the
## damage half (see UnitOrderController.DAY_MOVE_SPEED_MULTIPLIER for the
## movement half, which lives there since this class has no movement code
## of its own). No exact design number — a placeholder balancing
## multiplier. Applies to every unit's OUTGOING damage during Day, not a
## horde's — specifically a "Military units" benefit, not a general
## Day/Night combat-wide swing.
const DAY_DAMAGE_MULTIPLIER: float = 1.1

## A Dragoon's charge stuns whatever it hits for one second. The Traction
## Ram/Holt Breaker's TRAMPLE_KNOCKBACK deliberately does NOT use this — see
## _apply_special_ability_effects()'s own doc comment for why.
const CHARGE_STUN_SECONDS: float = 1.0

@export var unit_manager_path: NodePath
@export var horde_manager_path: NodePath
@export var unit_order_controller_path: NodePath
@export var resource_manager_path: NodePath  ## Optional — unset always resolves as "Gunpowder available".
@export var building_manager_path: NodePath  ## Optional — the undefended-building siege trigger; unset skips it.
@export var tech_manager_path: NodePath      ## Optional — per-unit research upgrades (UnitUpgrades). Unset means every unit fights at its raw UnitDefinition stats, exactly as before upgrades existed.
@export var hex_grid_map_path: NodePath      ## Optional — CHARGE_KNOCKBACK/TRAMPLE_KNOCKBACK need to validate a knockback destination is a real, passable hex; unset means those two abilities never physically knock a horde anywhere (a CHARGE_KNOCKBACK's stun still applies regardless — see _knock_back()'s own doc comment).

var _unit_manager: UnitManager
var _horde_manager: HordeManager
var _resource_manager: ResourceManager
var _building_manager: BuildingManager
var _tech_manager: TechManager
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
	if tech_manager_path != NodePath():
		_tech_manager = get_node(tech_manager_path)
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


## Resolves ONE round between `instance` and every horde standing on its own
## hex. The contact-without-movement entry point — see this class's own doc
## comment for who calls it and why the "one-shot" framing no longer holds.
##
## Per UNIT rather than per hex on purpose, so the caller can interleave: a
## defending wave is topped back up between one unit's round and the next, which
## is what keeps a stack of units killing at a rate proportional to its size
## while each individual unit still faces only one frontage's worth of incoming
## damage (see ResidentDefenseController.run_wave_tick()).
##
## Both from/to are the unit's own hex, so _apply_special_ability_effects()'s
## knockback fizzles on its own `movement_from == movement_to` guard: there is no
## line of travel to shove a defender back along when nobody advanced. A
## CHARGE_KNOCKBACK stun still lands, exactly as it does when the knockback
## destination is impassable.
##
## Iteration safety: get_hordes_at() builds a fresh array, so _engage() removing
## a horde mid-loop cannot skip an entry, and _engage() early-outs on an
## already-dead unit or an emptied horde. A horde CREATED mid-loop by the
## casualty path (_engage() -> HordeManager.add_casualty_zombies()) is
## deliberately not engaged this round — the snapshot predates it, and a unit's
## own dead rising should not get a free swing in the same instant they fell.
func engage_unit(instance: UnitInstance) -> void:
	if not _horde_manager or instance.is_destroyed():
		return
	for horde in _horde_manager.get_hordes_at(instance.hex_coord):
		_engage(instance, horde, instance.hex_coord, instance.hex_coord)

## `movement_from`/`movement_to` are whichever side's own move triggered
## this contact event (the horde's for _on_horde_moved, the unit's for
## _on_unit_moved) — passed through purely so
## _apply_special_ability_effects() can knock a surviving horde back along
## that same line of travel; ordinary engagements ignore both.
func _engage(instance: UnitInstance, horde: Horde, movement_from: Vector2i, movement_to: Vector2i) -> void:
	if instance.is_destroyed() or horde.size <= 0:
		return  ## Already resolved earlier this same contact event (e.g. multiple units on one hex vs. one horde).

	var gunpowder_available := true
	if _resource_manager:
		gunpowder_available = _resource_manager.get_amount(GameEnums.ResourceType.GUNPOWDER) > 0.0

	var damage_multiplier := UnitMorale.get_damage_multiplier(instance, gunpowder_available, UnitUpgrades.max_hp(_tech_manager, instance.definition))
	if TimeCycleManager.is_day():
		damage_multiplier *= DAY_DAMAGE_MULTIPLIER
	# Per-unit research upgrades fold into the multiplier seam that already
	# exists rather than a new parameter — see UnitUpgrades.damage_multiplier().
	damage_multiplier *= UnitUpgrades.damage_multiplier(_tech_manager, instance.definition)
	var forced_melee := UnitUpgrades.forced_melee_multipliers(_tech_manager, instance.definition)
	var incoming_damage_multiplier := _garrison_incoming_multiplier(instance)
	# Night's mirror of the DAY_DAMAGE_MULTIPLIER bump above, on the horde's
	# side instead of the unit's — see HordeManager.get_night_aggression_multiplier()'s
	# own doc comment.
	var horde_damage := horde.get_combat_damage() * HordeManager.get_night_aggression_multiplier()
	var headcount_before := instance.get_squad_headcount()
	var result := CombatEngine.resolve_engagement(instance, gunpowder_available, horde.get_combat_hp(), horde_damage, damage_multiplier, incoming_damage_multiplier, forced_melee["outgoing"], forced_melee["incoming"])
	horde.apply_remaining_hp(result.defender_hp_remaining)
	engagement_resolved.emit(instance, horde, result)

	if horde.size <= 0:
		instance.kill_count += 1  # Destroying a Horde outright is the decided definition of "a kill" — see UnitMorale.get_rank()'s own doc comment.
		if _horde_manager:
			_horde_manager.remove_horde(horde)
	else:
		_apply_special_ability_effects(instance, horde, movement_from, movement_to)

	# Every derived headcount point this engagement cost `instance` (an HP
	# threshold crossed, including the unit's own final death, which is just
	# its headcount's last point) spawns that many casualty zombies right
	# here, mid-fight, not only once the whole unit is wiped out.
	var headcount_after := instance.get_squad_headcount()
	var figures_lost := headcount_before - headcount_after
	if figures_lost > 0 and _horde_manager:
		_horde_manager.add_casualty_zombies(instance.hex_coord, figures_lost * CASUALTY_ZOMBIES_PER_UNIT)

	if instance.is_destroyed() and _unit_manager:
		_unit_manager.remove_unit(instance)

## A GARRISON-ordered unit takes less incoming damage, stacking further at
## night if a non-ruined Search Light's own vision_radius reaches this
## hex. HOLD deliberately does NOT qualify — this is Garrison's own payoff
## over plain Hold, same distinction UnitOrderController's healing mechanic makes.
func _garrison_incoming_multiplier(instance: UnitInstance) -> float:
	if instance.order != GameEnums.UnitOrderType.GARRISON:
		return 1.0
	var multiplier := GARRISON_INCOMING_DAMAGE_MULTIPLIER
	if _building_manager and TimeCycleManager.is_night() and _is_near_searchlight_tower(instance.hex_coord):
		multiplier *= SEARCHLIGHT_NIGHT_INCOMING_DAMAGE_MULTIPLIER
	return multiplier

func _is_near_searchlight_tower(coord: Vector2i) -> bool:
	for instance in _building_manager.get_all_buildings():
		if instance.is_ruined or instance.definition.building_type != GameEnums.BuildingType.SEARCH_LIGHT:
			continue
		if HexCoord.distance(instance.hex_coord, coord) <= instance.definition.vision_radius:
			return true
	return false

## A horde reaching a hex with NO defending UnitInstance sieges whatever
## non-ruined building stands there instead of the contact being a no-op.
## One building damaged per contact event (same "one attacking side, one
## engagement" granularity _engage() uses for units) — the first non-ruined
## instance found, not every building on the hex at once; a hex with
## several buildings falls one at a time across repeated contacts.
##
## Does NOT check Zone of Control coverage or wall segments — this is the
## simplest possible "the layer in front has failed" case (no wall, no
## garrison, nothing between the horde and the building but the building
## itself), not the full defense-in-depth cascade (outer wall -> legacy
## wall -> garrison -> buildings) the still-missing outer/inner-wall
## distinction and horde-vs-wall targeting would need. Extends naturally
## once those exist; doesn't block on them.
func _siege_buildings(horde: Horde, coord: Vector2i) -> void:
	if not _building_manager or horde.size <= 0:
		return
	for instance in _building_manager.get_buildings_at(coord):
		if instance.is_ruined:
			continue
		_building_manager.damage_building(instance, horde.get_combat_damage() * HordeManager.get_night_aggression_multiplier())
		return  # One building per contact event — see this method's own doc comment.

## "Each special unit type should do something special." Called only once
## _engage() already knows `horde` survived this round (a destroyed horde
## has nothing left to knock back or stun). CHARGE_KNOCKBACK (Dragoon) gets
## both a knockback AND a stun; TRAMPLE_KNOCKBACK (Traction Ram, Holt
## Breaker) gets the same knockback with NO stun — both are slow damage
## sponges that shove zombies aside as they grind forward, not shock units
## that need to freeze their target the way a fast charging Dragoon does.
## Every other ability value (including plain NONE) does nothing here —
## Outrider's unarmed-ness, Chasseur/Grenadier/Armoured Command Car's stat
## leans, and Searchlight Tender's mobile ZoC/vision aura are expressed
## elsewhere (UnitCatalog's stat curve, LogisticsNetwork.recompute()
## respectively), not in this method.
func _apply_special_ability_effects(instance: UnitInstance, horde: Horde, movement_from: Vector2i, movement_to: Vector2i) -> void:
	match instance.definition.ability:
		GameEnums.UnitAbility.CHARGE_KNOCKBACK:
			_knock_back(horde, movement_from, movement_to)
			horde.stun_seconds_remaining = CHARGE_STUN_SECONDS
		GameEnums.UnitAbility.TRAMPLE_KNOCKBACK:
			_knock_back(horde, movement_from, movement_to)

## Displaces `horde` one further hex along whichever line of travel caused
## this contact — movement_to + (movement_to - movement_from), i.e. "the
## same direction the moving side was already heading, continued one more
## step," which reads correctly regardless of whether the HORDE walked into
## the unit or the UNIT walked into the horde (both callers pass their own
## from/to pair). Requires an optional _hex_grid_map to validate the
## destination is a real, passable hex (never shoves a horde into open
## ocean or a marsh) — unset, or no valid destination, just means the
## knockback fizzles; a CHARGE_KNOCKBACK's stun is applied by the caller
## regardless. Directly mutates the passed-in Horde Resource (same "manager
## mutates a passed-in Resource" pattern CombatEngine/WallManager.damage_segment()
## use) rather than going through HordeManager — this does NOT emit
## HordeManager.horde_moved, a deliberate, minor gap: any listener keyed off
## that signal reflects the knock-back on the horde's own NEXT real
## movement tick instead of instantly, not incorrectly.
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
