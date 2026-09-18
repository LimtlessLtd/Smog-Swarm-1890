class_name CombatCoordinator
extends Node


## Acquires nearby targets and resolves range-limited attacks on a shared cooldown.
## WallDefenseController supplies protected volleys through strike_from_cover().

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
var _combat_elapsed: float = 0.0
var _attack_cooldowns: Dictionary = {}
const CONTACT_INTERVAL := 20.0
const ACQUIRE_RADIUS := 80.0
const MELEE_REACH := 2.5

func _ready() -> void:
	if unit_manager_path != NodePath():
		_unit_manager = get_node(unit_manager_path)
		_unit_manager.unit_trained.connect(func(unit: UnitInstance) -> void: _attack_cooldowns.erase(unit.id))
		_unit_manager.unit_removed.connect(func(unit: UnitInstance) -> void: _attack_cooldowns.erase(unit.id))
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

func _on_horde_moved(_horde: Horde, _from_coord: Vector2i, _to_coord: Vector2i) -> void:
	pass # Contact is evaluated in world space on the combat clock.

func _on_unit_moved(_instance: UnitInstance, _from_coord: Vector2i, _to_coord: Vector2i) -> void:
	pass

func _process(delta: float) -> void:
	advance_combat(delta)

func advance_combat(delta: float) -> void:
	if not _horde_manager or not _unit_manager or delta <= 0.0:
		return
	for id in _attack_cooldowns.keys():
		_attack_cooldowns[id] -= delta
		if _attack_cooldowns[id] <= 0.0:
			_attack_cooldowns.erase(id)
	var pursuit_slots: Dictionary = {}  # int UnitInstance.id -> next distinct contact slot.
	for horde in _horde_manager.get_all_hordes():
		horde.has_combat_target = false
		if _horde_manager.get_sieged_segment(horde):
			continue
		var at := HexCoord.axial_to_world(horde.hex_coord) + horde.local_position
		var nearest: UnitInstance = null
		var distance := ACQUIRE_RADIUS
		for unit in _unit_manager.get_all_units():
			var world := HexCoord.axial_to_world(unit.hex_coord) + unit.local_position
			var reach := at.distance_to(world)
			var resident_invasion := horde.resident_target_id == -1 and unit.hex_coord == horde.hex_coord
			if not unit.is_destroyed() and (reach < distance or (nearest == null and resident_invasion)):
				nearest = unit
				distance = reach
		if nearest:
			horde.has_combat_target = true
			var slot := int(pursuit_slots.get(nearest.id, 0))
			pursuit_slots[nearest.id] = slot + 1
			horde.combat_target = _pursuit_slot(HexCoord.axial_to_world(nearest.hex_coord) + nearest.local_position, slot)
	for unit in _unit_manager.get_all_units():
		if not _attack_cooldowns.has(unit.id):
			engage_unit(unit)
	_combat_elapsed += delta
	if _combat_elapsed >= CONTACT_INTERVAL:
		_combat_elapsed = 0.0
		for horde in _horde_manager.get_all_hordes():
			_siege_buildings(horde, HexCoord.world_to_axial(HexCoord.axial_to_world(horde.hex_coord) + horde.local_position))

## Hordes pursuing one unit approach from separate close positions instead of
## converging into one visual and physical stack. Eight slots make the first ring
## evenly spaced; later groups form compact outer rings and only make contact when
## their own crowd radius reaches the unit.
static func _pursuit_slot(unit_world: Vector2, slot: int) -> Vector2:
	const SLOTS_PER_RING := 8
	const FIRST_RING_RADIUS := 1.5
	const RING_SPACING := 1.0
	var ring := slot / SLOTS_PER_RING
	var index := slot % SLOTS_PER_RING
	var angle := TAU * float(index) / float(SLOTS_PER_RING) + float(ring) * TAU / float(SLOTS_PER_RING * 2)
	return unit_world + Vector2(cos(angle), sin(angle)) * (FIRST_RING_RADIUS + float(ring) * RING_SPACING)

static func attack_reach(instance: UnitInstance) -> float:
	return WallDefenseController.reach_metres(instance.definition) * HexCoord.WORLD_UNITS_PER_REAL_METER

static func contact_distance(instance: UnitInstance, horde: Horde) -> float:
	var unit_world := HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
	var horde_world := HexCoord.axial_to_world(horde.hex_coord) + horde.local_position
	return maxf(0.0, unit_world.distance_to(horde_world) - ZombieSwarmManager.HORDE_BASE_SPREAD * sqrt(maxf(1.0, float(horde.size) / 5.0)))

func engage_unit(instance: UnitInstance) -> void:
	if not _horde_manager or instance.is_destroyed() or _attack_cooldowns.has(instance.id):
		return
	var closest: Horde = null
	var best := attack_reach(instance)
	if instance.definition.requires_gunpowder and _resource_manager and _resource_manager.get_amount(GameEnums.ResourceType.GUNPOWDER) < 1.0:
		best = MELEE_REACH
	for horde in _horde_manager.get_all_hordes():
		if (_horde_manager.get_sieged_segment(horde) and instance.on_wall) or horde.size <= 0:
			continue
		var distance := contact_distance(instance, horde)
		if distance <= best and _horde_manager.has_clear_contact(instance, horde):
			closest = horde
			best = distance
	if closest:
		_attack_cooldowns[instance.id] = CONTACT_INTERVAL
		_engage(instance, closest, instance.hex_coord, instance.hex_coord)

func _engage(instance: UnitInstance, horde: Horde, movement_from: Vector2i, movement_to: Vector2i) -> void:
	_resolve(instance, horde, movement_from, movement_to, false)

## One strike by a defender at a horde clawing at a wall piece the defender stands
## behind — WallDefenseController decides who and when. Same outgoing damage as a
## contact round (morale, veterancy, day bonus, research, gunpowder), but the horde
## cannot reach the defender through an unbreached wall, so nothing comes back:
## no damage taken, no casualty conversion, no knockback. engagement_resolved
## carries `"from_cover": true` so a view can draw it as a shot over the wall.
func strike_from_cover(instance: UnitInstance, horde: Horde) -> void:
	_resolve(instance, horde, instance.hex_coord, instance.hex_coord, true)

func _resolve(instance: UnitInstance, horde: Horde, movement_from: Vector2i, movement_to: Vector2i, from_cover: bool) -> void:
	if instance.is_destroyed() or horde.size <= 0:
		return  ## Already resolved earlier this same contact event (e.g. multiple units on one hex vs. one horde).

	var gunpowder_available := true
	if _resource_manager:
		gunpowder_available = _resource_manager.get_amount(GameEnums.ResourceType.GUNPOWDER) >= 1.0

	var damage_multiplier := UnitMorale.get_damage_multiplier(instance, gunpowder_available, UnitUpgrades.max_hp(_tech_manager, instance.definition))
	if TimeCycleManager.is_day():
		damage_multiplier *= DAY_DAMAGE_MULTIPLIER
	# Per-unit research upgrades fold into the multiplier seam that already
	# exists rather than a new parameter — see UnitUpgrades.damage_multiplier().
	damage_multiplier *= UnitUpgrades.damage_multiplier(_tech_manager, instance.definition)
	var forced_melee := UnitUpgrades.forced_melee_multipliers(_tech_manager, instance.definition)
	var incoming_damage_multiplier := 0.0 if from_cover or instance.on_wall or horde.contact_grace > 0.0 or contact_distance(instance, horde) > MELEE_REACH else _garrison_incoming_multiplier(instance)
	# Night's mirror of the DAY_DAMAGE_MULTIPLIER bump above, on the horde's
	# side instead of the unit's — see HordeManager.get_night_aggression_multiplier()'s
	# own doc comment.
	var frontage := mini(horde.size, HordeManager.wall_contact_frontage(horde.size))
	if horde.resident_frontage_limit > 0:
		frontage = mini(frontage, horde.resident_frontage_limit)
	var horde_damage := frontage * Horde.DAMAGE_PER_ZOMBIE * HordeManager.get_night_aggression_multiplier()
	if gunpowder_available and instance.definition.requires_gunpowder and _resource_manager:
		_resource_manager.spend({GameEnums.ResourceType.GUNPOWDER: 1.0})
	var hp_before := instance.current_hp
	var headcount_before := instance.get_squad_headcount()
	var result := CombatEngine.resolve_engagement(instance, gunpowder_available, horde.get_combat_hp(), horde_damage, damage_multiplier, incoming_damage_multiplier, forced_melee["outgoing"], forced_melee["incoming"])
	var size_before := horde.size
	horde.apply_remaining_hp(result.defender_hp_remaining)
	result["zombies_killed"] = size_before - horde.size
	result["from_cover"] = from_cover
	result["damage_taken"] = hp_before - instance.current_hp
	engagement_resolved.emit(instance, horde, result)

	if horde.size <= 0:
		instance.kill_count += 1  # Destroying a Horde outright is the decided definition of "a kill" — see UnitMorale.get_rank()'s own doc comment.
		if _horde_manager:
			_horde_manager.remove_horde(horde)
	elif not from_cover:
		_apply_special_ability_effects(instance, horde, movement_from, movement_to)

	# Every derived headcount point this engagement cost `instance` (an HP
	# threshold crossed, including the unit's own final death, which is just
	# its headcount's last point) spawns that many casualty zombies right
	# here, mid-fight, not only once the whole unit is wiped out.
	var headcount_after := instance.get_squad_headcount()
	var figures_lost := headcount_before - headcount_after
	if figures_lost > 0 and _horde_manager:
		_horde_manager.add_casualty_zombies(instance.hex_coord, figures_lost * CASUALTY_ZOMBIES_PER_UNIT, instance.local_position)

	if instance.is_destroyed() and _unit_manager:
		_unit_manager.remove_unit(instance)

## A GARRISON-ordered unit takes less incoming damage, stacking further at
## night if a FINISHED, intact, switched-on Search Light's own vision_radius
## reaches this hex. HOLD deliberately does NOT qualify — this is Garrison's
## own payoff over plain Hold, same distinction UnitOrderController's healing
## mechanic makes.
func _garrison_incoming_multiplier(instance: UnitInstance) -> float:
	if instance.order != GameEnums.UnitOrderType.GARRISON:
		return 1.0
	var multiplier := GARRISON_INCOMING_DAMAGE_MULTIPLIER
	if _building_manager and TimeCycleManager.is_night() and _is_near_searchlight_tower(instance.hex_coord):
		multiplier *= SEARCHLIGHT_NIGHT_INCOMING_DAMAGE_MULTIPLIER
	return multiplier

func _is_near_searchlight_tower(coord: Vector2i) -> bool:
	for instance in _building_manager.get_all_buildings():
		# The beam, and nothing about the beam survives any of the three
		# not-operating states: rubble has none, a switched-off tower has
		# none (design_doc.md §2.1's "Going dark"), and an unbuilt one does
		# not have one yet — which is exactly is_running(). The two other
		# systems reading the same lamp off the same definition fields need
		# a finer answer than this and say so at their own call sites
		# (FogOfWarManager._building_vision_radius() keeps a dark tower's
		# base radius; NoiseManager leaves a building site loud). This one is
		# reached only through a full combat round, so unlike those two it is
		# not covered by verify_building_state_emissions.gd.
		if not instance.is_running() or instance.definition.building_type != GameEnums.BuildingType.SEARCH_LIGHT:
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
		var source := HexCoord.axial_to_world(horde.hex_coord) + horde.local_position
		var target := HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
		if source.distance_to(target) > ObstacleRadii.BUILDING_RADIUS + MELEE_REACH:
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
