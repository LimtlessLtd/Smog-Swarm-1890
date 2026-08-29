class_name ResidentDefenseController
extends Node

## design_doc.md §2.1's resident population fights back. One rule, one class:
## **a hex's own zombies rise to meet the player's units standing on it.**
##
## The gap this closes (D42's own accepted cost, filed as its own backlog item
## rather than bolted onto the tactical layer): `InfestationManager` owns a
## per-hex RESIDENT count, `CombatCoordinator` engages `Horde`s, and a resident
## is not one — so a player standing on a Greater London hex holding 446,729
## zombies could shoot none of them. D8 says killing is the only suppression,
## and before this it only reached the roaming half.
##
## **Residents condense into a defending `Horde`; they are not fought as a
## second kind of enemy.** `Horde` is already what `CombatCoordinator` fights,
## `TerritoryController` tests for, `HordeManager` paths and `SaveLoadManager`
## saves; teaching all four about a resident block buys no gameplay difference
## the player can see. Conservation then costs no code — the count leaves
## `InfestationManager._resident` and arrives as a `Horde` on the hex it left,
## which is exactly what `InfestationManager.export_from()` already does, and
## §2.1 already describes this seam in the other direction ("a horde dissolves
## into live entities on entering a live hex and re-condenses on exit,
## conserving its count").
##
## **Sits ABOVE the four managers it reads, and none of them know it exists** —
## the same "orchestration layer reads from many, referenced by none" role
## `CombatCoordinator` and `FogOfWarManager` play over what THEY sit above.
## Extracted rather than added to `CombatCoordinator`, which already carries
## seven `NodePath` dependencies and is the class CLAUDE.md §1's "extract a
## narrower collaborator instead" rule is about.
##
## **Nothing here is saved.** The wave accumulator is transient, and everything
## else is derived from two things that already save themselves: a hex's
## resident count (`InfestationManager`) and the hordes standing on it
## (`HordeManager`). A save mid-grind reloads with the defending wave still
## standing, because the wave IS a horde.
##
## **Per macro-hex, not a CLAUDE.md §3 flattening.** The frontage below reads a
## hex's population density, and population is one number per hex by design
## (§2.1's opening line, and `InfestationManager`'s own doc comment on exactly
## this question). It reads no terrain field at all.

## How often a hex holding player units resolves a round, in SIMULATED seconds.
## `_process` delta is already scaled by `Engine.time_scale`, which `TickManager`
## drives, so this is the same clock and the same 20.0 that
## `HordeManager.LOGIC_TICK_SECONDS` and `UnitOrderController.LOGIC_TICK_SECONDS`
## already run on. That alignment is load-bearing rather than tidy:
## `UnitOrderController.GARRISON_REGEN_FRACTION_PER_TICK` heals 5% of max HP on
## the same interval, so "one round of incoming damage against one tick of
## regen" is a fair comparison the player can actually reason about.
const WAVE_INTERVAL_SECONDS: float = 20.0

## How far around a unit a zombie can be and still reach it inside one round —
## `HexCoord.SUB_HEX_CELL_SIZE_METERS`, the project's own finest spatial unit,
## rather than a number invented for this. See frontage_for() for what it buys.
const ENGAGEMENT_RADIUS_METRES: float = HexCoord.SUB_HEX_CELL_SIZE_METERS

## A frame that swallowed a long stall must not resolve dozens of rounds at
## once and wipe a garrison the player was watching hold. At 1000x a 60 fps
## frame is 16.7 simulated seconds, so under 1 tick/frame is normal and this
## only ever fires after a real hitch; the backlog is discarded rather than
## banked, the same "no cross-frame accumulator" restraint
## `InfestationManager.run_daily_tick()` documents for its own hazard.
const MAX_TICKS_PER_FRAME: int = 4

## What a wave tick did, for a HUD or a diagnostic that wants to watch the tide
## without polling every hex. Emitted once per tick, not once per hex.
signal wave_resolved(hexes: int, condensed: int)

@export var unit_manager_path: NodePath
@export var combat_coordinator_path: NodePath
## Optional — unset means a hex's residents never rise, and only hordes that
## are already roaming get fought.
@export var infestation_manager_path: NodePath
@export var horde_manager_path: NodePath

var _unit_manager: UnitManager
var _combat_coordinator: CombatCoordinator
var _infestation_manager: InfestationManager
var _horde_manager: HordeManager

var _elapsed: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  ## Background-simulation infrastructure — shouldn't freeze if the SceneTree is ever paused, same as HordeManager/UnitOrderController.
	if unit_manager_path:
		_unit_manager = get_node_or_null(unit_manager_path) as UnitManager
	if combat_coordinator_path:
		_combat_coordinator = get_node_or_null(combat_coordinator_path) as CombatCoordinator
	if infestation_manager_path:
		_infestation_manager = get_node_or_null(infestation_manager_path) as InfestationManager
	if horde_manager_path:
		_horde_manager = get_node_or_null(horde_manager_path) as HordeManager


func _process(delta: float) -> void:
	_elapsed += delta
	var ticks := 0
	while _elapsed >= WAVE_INTERVAL_SECONDS and ticks < MAX_TICKS_PER_FRAME:
		_elapsed -= WAVE_INTERVAL_SECONDS
		ticks += 1
		run_wave_tick()
	if ticks >= MAX_TICKS_PER_FRAME:
		_elapsed = 0.0  # See MAX_TICKS_PER_FRAME — discarded, not banked.


## **How many of a hex's residents can physically reach the player's units in
## one round.** Not a fraction of the population: `residents` are spread across
## 25 square miles, and what presses on a squad is whatever stands within
## contact reach of it. So the wave is an AREA of the hex's own density, not a
## share of its count — a disc of ENGAGEMENT_RADIUS_METRES against
## `HexCoord.hex_area_square_metres()`.
##
## What that produces against the real map's own measured resident counts
## (decisions.md D44's table):
##
##   | hex                             | residents | wave |
##   | Greater London                  |   446,729 |   20 |
##   | Birmingham                      |   321,008 |   14 |
##   | Manchester                      |    68,075 |    3 |
##   | a 1,000-floor hex at 100%       |     1,000 |    1 |
##
## which makes §2.1's "capacity is the difficulty curve, and that is the point"
## true at the tactical layer too, off one constant that was already in the
## project. The alternative — a flat percentage of the population — hands a
## London hex a wave of thousands and ends the run on contact, and hands a
## Highland hex a wave of zero.
##
## The floor of 1 is what makes an emptying hex finishable: below ~11,450
## residents the disc holds less than half a zombie, and a hex that can never
## field a defender can never be cleared either, since clearing IS killing (D8).
## The cap at `residents` is what keeps the transfer honest — a hex cannot field
## more defenders than it has people.
##
## Static and pure, so a verification can assert the curve without a scene.
static func frontage_for(residents: int) -> int:
	if residents <= 0:
		return 0
	var density := float(residents) / HexCoord.hex_area_square_metres()
	var reach := PI * ENGAGEMENT_RADIUS_METRES * ENGAGEMENT_RADIUS_METRES
	return clampi(int(round(density * reach)), 1, residents)


## One wave tick: on every hex holding at least one player unit, each unit in
## turn meets a defending force topped back up to the frontage and resolves one
## round against it.
##
## Public so a verification can advance the model deterministically instead of
## driving `_process` at a real frame rate — the same reason
## `InfestationManager.run_daily_tick()` and `ZombieSwarmManager.allocate()` are
## public.
func run_wave_tick() -> void:
	if not _unit_manager or not _combat_coordinator:
		return
	var condensed := 0
	var coords := _hexes_holding_units()
	for coord in coords:
		# Topped up BEFORE each unit's round, not once for the hex. The
		# frontage is what one squad has in contact with it, so every unit on
		# the hex meets a full one and the gap it cuts is refilled before the
		# next unit swings — measured, and the difference is not cosmetic
		# (decisions.md D50): with one top-up per hex, ten units killed exactly
		# as fast as one, because the first unit wiped the wave and the other
		# nine engaged an empty hex. A stack now kills in proportion to its
		# size while each unit still takes one frontage's worth of damage.
		#
		# Unconditional, not only when something condensed: once the wave is
		# already at strength the shortfall is zero, and a tick that skipped the
		# round would stall the grind exactly when the fight is hardest.
		for instance: UnitInstance in _unit_manager.get_units_at(coord):
			condensed += reinforce(coord)
			_combat_coordinator.engage_unit(instance)
	wave_resolved.emit(coords.size(), condensed)


## Tops `coord`'s defending force up to its frontage and returns how many
## residents it took to do it. Zero when the hex has no residents left, or when
## the zombies already standing there — condensed defenders, a roaming horde
## that wandered in, or both — already meet or exceed the frontage.
##
## Measured against the RESIDENT count rather than `zombie_count_at()`: the
## count shrinks as the player grinds the hex down, so a thinned hex presses
## proportionally less hard, which is the same "capacity is the difficulty
## curve" statement applied over time instead of across the map.
##
## Public for the same reason `InfestationManager.export_from()` is: a test that
## can only reach the transfer through the tick cannot tell a broken frontage
## from a broken transfer.
func reinforce(coord: Vector2i) -> int:
	if not _infestation_manager or not _horde_manager:
		return 0
	var residents := _infestation_manager.resident_count_at(coord)
	if residents <= 0:
		return 0
	var shortfall := frontage_for(residents) - _horde_manager.get_zombie_count_at(coord)
	if shortfall <= 0:
		return 0
	return _infestation_manager.condense_defenders(coord, shortfall)


## Every hex with at least one live player unit on it, de-duplicated. One pass
## over `get_all_units()` rather than a query per hex — `UnitManager` has no hex
## index, so the alternative is a linear scan per candidate hex.
func _hexes_holding_units() -> Array[Vector2i]:
	var seen: Dictionary = {}
	var coords: Array[Vector2i] = []
	for instance: UnitInstance in _unit_manager.get_all_units():
		if instance.is_destroyed() or seen.has(instance.hex_coord):
			continue
		seen[instance.hex_coord] = true
		coords.append(instance.hex_coord)
	return coords
