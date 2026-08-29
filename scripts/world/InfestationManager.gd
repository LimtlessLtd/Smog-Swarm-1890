class_name InfestationManager
extends Node

## design_doc.md §2.1's strategic hex infestation: how many zombies are on each
## macro-hex, what fraction of that hex's capacity they are, and the band that
## ratio puts the hex in.
##
## **One mutable number per hex, everything else derived** (D1). This class owns
## the resident count; `infestation` and `is_cleared` are computed on demand and
## never stored, so the two cannot drift — the same derived-never-stored pattern
## `UnitUpgrades.gd` uses. Killing zombies lowers infestation because it lowers
## the count; that is arithmetic, not a rule anyone has to implement.
##
## **A hex's zombies are its residents PLUS whatever hordes are standing on it,
## and the two are stored separately because they already were.** `Horde` is a
## saved `Resource` owned by `HordeManager`; mirroring horde sizes into a second
## per-hex ledger here would be the double-source-of-truth D5 deletes the
## diffusion PDE to avoid, and would have to chase four separate traps to stay
## in sync — the combat kill path emits no signal at all, merge and split both
## emit `horde_size_changed` while conserving the total, `CombatCoordinator`'s
## knockback moves a horde without emitting `horde_moved`, and
## `HordeManager.load_save_state()` replaces every horde silently. Reading the
## roaming half live through `HordeManager`'s public API cannot go stale, and it
## makes three §2.1 rules fall out for free:
##
##   * killing a horde on a hex lowers that hex's infestation (D8's "killing is
##     the only suppression"),
##   * a roaming horde crossing a Cleared hex raises it above 5% while it is
##     there (§2.1's re-infestation),
##   * an export conserves the total exactly — the count leaves `_resident` and
##     arrives as a `Horde` on the same hex.
##
## **Per macro-hex is the design, not a CLAUDE.md §3 flattening.** §2.1 opens
## "Each 5-mile strategic hex carries one mutable number and one static
## capacity", so one value per hex IS the model here, the same way the strategic
## routing graph is hex-granularity by design. Do not "fix" this into a sub-hex
## read.
##
## **Not this class's job, and not built yet:**
##   * ZoC severance and the Fringe -25% logistics efficiency. There is no
##     logistics throughput number anywhere in the codebase to reduce
##     (`SupplyLineCatalog.get_speed_multiplier()` is unit MOVEMENT speed), and
##     the Contested band's stockpile split needs per-settlement stockpiles,
##     which `backlog.md` insists is its own PR. Both wait for §2.2.
##   * Contested-band decay of non-defensive structures.
##
## **Not the same thing as `TerritoryController`,** which answers a different
## question with a different trigger: "did the player lose a building here to a
## horde" (an event, a boolean, recaptured when no horde stands there). This
## answers "how many zombies are here" (a population, a ratio). Neither derives
## from the other and neither should — but do not add a second "is this hex
## contested" reader without deciding which one it means.

## design_doc.md §2.1's band table. Boundaries are the spec's, stated once here
## rather than in each caller.
const CLEARED_BELOW: float = 5.0        ## D2 — deliberately lenient, verbatim: "I was just trying to be a bit lenient so players could still build things even if theyre getting attacked by zombies/clearing out zombies etc."
const FRINGE_BELOW: float = 25.0
const HIVE_CORE_FROM: float = 75.0

## D4's source term: a hex above the Hive Core threshold breeds at a flat
## percentage of its OWN capacity per day, so one constant works from Highland
## Scotland to Southwark. §2.1 says outright that the exact figure "is a
## balancing number, not a design decision" — 2%/day means a hex refills from
## the 75% export floor back to 100% in 12.5 days.
const SPAWN_RATE_PER_DAY: float = 0.02

## D4's floor: exporting a horde never takes a hex below 75%. Only player
## killing goes lower, so a city ground down stops shipping and a city left
## alone ships indefinitely.
const EXPORT_FLOOR_FRACTION: float = 0.75

## How much of its own capacity a hex may ship in ONE day. The 75% floor above
## is the hard constraint; this is the rate at which a hex walks down to it.
##
## §2.1 describes the pump as "breed to 100, export down to 75, breed again",
## which taken literally means one day's export is the whole 25%. Measured on
## the real map (scripts/test/diagnose_infestation_pressure.gd, 60 days, no
## player action) that ships **37,582 zombies on day one**, out of a Manchester
## suburb hex six hexes from the player's Town Hall — against a colony holding a
## Town Hall, a Lumber Yard and one farm. That is not difficulty, it is the run
## ending before the first horde finishes walking.
##
## Capping the RATE rather than the total keeps the mechanism §2.1 specifies —
## breed, ship, never below the floor, only killing goes lower — and makes the
## same city bleed over ten days instead of one. §2.1 itself calls the spawn
## figure "a balancing number, not a design decision"; this is the same kind of
## number on the other side of the pump. See decisions.md D37.
##
## What it actually produces, and it is better than the flat version: shipping
## drops a hex off the 100% trigger for a day or two while it breeds back, so
## the single daily export ROTATES around whichever Hive Cores are nearest the
## player rather than coming out of the same hex every morning. Pressure arrives
## from all sides, which is what P1's "the map is hostile everywhere" wants, and
## it falls out of the rate cap rather than being scripted.
const MAX_EXPORT_FRACTION_PER_DAY: float = 0.025

## **The export bound, and why it exists.** Worldgen seeds ring four outward at
## 100%, which is roughly 4,655 of the map's 4,692 land hexes — every one of
## them an export candidate on day one. Shipping a horde from each would spawn
## thousands of `Horde` resources into a manager whose merge check is per
## co-located pair and whose `get_hordes_at()` is a linear scan.
##
## The bound is the same one D13 applies to entities and the same one PR #90
## applied to ambient spawns: a horde nobody could ever meet is not simulated.
## A Hive Core farther than this from a player building still breeds and still
## sits at 100% — its count is real — it just does not ship. Nearest-first, so
## the pressure comes from the ground the player is actually next to.
const EXPORT_MAX_DISTANCE_FROM_PLAYER: int = 8
const MAX_EXPORTS_PER_DAY: int = 1

## D7's opening state: 0% on the player's own hex, then 25 / 50 / 75, and 100%
## from ring four out. Ring three sits exactly at the Hive Core threshold on
## purpose, so breeding is visible near home from the first day rather than
## being a late-game surprise. Index is hex distance; past the end is the last
## entry.
const RING_SEED_PERCENT: Array[float] = [0.0, 25.0, 50.0, 75.0, 100.0]

## Emitted when a hex crosses a band boundary. NOT emitted per hex from the
## daily sweep: breeding moves a hex within Hive Core and export lands it back
## on the threshold, so the sweep produces almost no band changes, and a signal
## per land hex per day would be ~4,700 emissions a day at 1000x speed. A
## consumer that needs the band of an arbitrary hex calls band_at().
signal band_changed(coord: Vector2i, band: GameEnums.InfestationBand)

## One emission per simulated day, carrying what the sweep did. Lets a HUD or a
## test see the pump working without polling 4,692 hexes.
signal day_simulated(bred: int, exported_hordes: int, exported_zombies: int)

@export var hex_grid_map_path: NodePath
## Optional — without it a Hive Core still breeds but never ships, since there
## is nothing to hand an exported horde to.
@export var horde_manager_path: NodePath
## Optional — supplies the starting settlement hex the worldgen rings are
## measured from, and the player positions export range is measured against.
@export var building_manager_path: NodePath

var _hex_grid_map: HexGridMap
var _horde_manager: HordeManager
var _building_manager: BuildingManager

## Vector2i -> int. The one mutable number per hex. Only non-zero entries are
## held, so "absent" and "zero" are the same answer here (unlike the baked
## capacity, where 0 means open sea).
var _resident: Dictionary = {}

## Every non-OCEAN hex, cached at seed time. The daily sweep walks this rather
## than HexGridMap.get_all_cells(), which allocates all 27,566 cells — most of
## them sea — on every call.
var _land_coords: Array[Vector2i] = []

var _seeded: bool = false


func _ready() -> void:
	if hex_grid_map_path:
		_hex_grid_map = get_node_or_null(hex_grid_map_path) as HexGridMap
	if horde_manager_path:
		_horde_manager = get_node_or_null(horde_manager_path) as HordeManager
	if building_manager_path:
		_building_manager = get_node_or_null(building_manager_path) as BuildingManager

	# This node must be a LATER Main.tscn sibling than BuildingManager, whose
	# own _ready() runs seed_starting_buildings() — the rings below are measured
	# from the hex that puts down. Main.tscn ordinal position is the only
	# mechanism; there is no priority system. Same load-bearing ordering
	# DiscontentManager documents for its own day handler.
	_seed_from_starting_settlement()
	TickManager.day_completed.connect(_on_day_completed)


## design_doc.md §2.1's static capacity for one hex: `total_zombie_pop`, baked
## from real 1890s population. 0 for open sea and for a hex with no cell.
func capacity_at(coord: Vector2i) -> int:
	if not _hex_grid_map:
		return 0
	var cell := _hex_grid_map.get_cell(coord)
	return cell.total_zombie_pop if cell else 0


## The saved half: zombies that live on this hex rather than roaming.
func resident_count_at(coord: Vector2i) -> int:
	return int(_resident.get(coord, 0))


## §2.1's `zombie_count`: everything on the hex right now, residents plus any
## horde standing on it. See this class's doc comment for why the roaming half
## is read live rather than mirrored.
func zombie_count_at(coord: Vector2i) -> int:
	var roaming := _horde_manager.get_zombie_count_at(coord) if _horde_manager else 0
	return resident_count_at(coord) + roaming


## `zombie_count / total_zombie_pop * 100.0`, clamped to 100. Derived, never
## stored (D1). A hex with no capacity — open sea, or a hex the bake never
## covered — reads 0.0 rather than dividing by zero.
func infestation_at(coord: Vector2i) -> float:
	var capacity := capacity_at(coord)
	if capacity <= 0:
		return 0.0
	return minf(100.0, float(zombie_count_at(coord)) / float(capacity) * 100.0)


## D2: `infestation < 5.0`, derived, not a stored boolean.
func is_cleared(coord: Vector2i) -> bool:
	return infestation_at(coord) < CLEARED_BELOW


func band_at(coord: Vector2i) -> GameEnums.InfestationBand:
	return band_for(infestation_at(coord))


## Split out from band_at() so a caller that already has a percentage — a HUD
## legend, a test asserting the table itself — does not have to invent a hex.
static func band_for(infestation: float) -> GameEnums.InfestationBand:
	if infestation < CLEARED_BELOW:
		return GameEnums.InfestationBand.CLEARED
	if infestation <= FRINGE_BELOW:
		return GameEnums.InfestationBand.FRINGE
	if infestation < HIVE_CORE_FROM:
		return GameEnums.InfestationBand.CONTESTED
	return GameEnums.InfestationBand.HIVE_CORE


## Adds to a hex's resident count, capped at its capacity. The entry point a
## future tactical layer re-condenses entities through; nothing calls it in
## anger yet.
func add_zombies(coord: Vector2i, count: int) -> void:
	if count <= 0:
		return
	_set_resident(coord, resident_count_at(coord) + count)


## Removes from a hex's resident count, floored at zero. D8's "killing is the
## only suppression" reaches roaming hordes through `HordeManager` instead; the
## player's own units reach residents through `condense_defenders()` below,
## which turns them into a horde first rather than teaching combat a second kind
## of enemy.
func remove_zombies(coord: Vector2i, count: int) -> void:
	if count <= 0:
		return
	_set_resident(coord, resident_count_at(coord) - count)


## Moves up to `count` of a hex's residents into a `Horde` standing on the SAME
## hex, so the player's units can fight them. `CombatCoordinator` engages
## `Horde`s and a resident is not one (D42), which is why a player standing on
## 400,000 zombies could shoot none of them. Returns how many actually moved.
##
## **Conserves exactly, and for the same reason `export_from()` does:** the
## count leaves `_resident` and arrives as a `Horde` on the hex it left, so
## `zombie_count_at()` — and therefore `infestation` and the band — are
## unchanged by the move itself. Only killing lowers them, which is D8 intact
## rather than D8 worked around.
##
## Writes through `_write_resident()` rather than `_set_resident()`: a
## conserving move provably cannot change the band (`zombie_count_at()` sums
## both halves), and the comparison `_set_resident()` does costs two linear
## scans over every horde — the same argument the daily sweep makes for using
## this path.
##
## `ResidentDefenseController` owns WHEN and HOW MANY. This owns only the
## transfer, so a test can exercise the conservation law without going through
## the wave rule.
func condense_defenders(coord: Vector2i, count: int) -> int:
	if not _horde_manager or count <= 0:
		return 0
	var moved := mini(count, resident_count_at(coord))
	if moved <= 0:
		return 0
	_write_resident(coord, resident_count_at(coord) - moved)
	_horde_manager.spawn_horde_at(coord, moved)
	return moved


## D7's opening state, measured from `start`. Public so a test can seed a
## fixture without a BuildingManager; the real game calls it once from _ready().
func seed_rings_from(start: Vector2i) -> void:
	if not _hex_grid_map:
		return
	_resident.clear()
	_land_coords.clear()
	for cell: HexCell in _hex_grid_map.get_all_cells():
		if cell.biome_type == GameEnums.BiomeType.OCEAN:
			continue
		_land_coords.append(cell.coord)
		if cell.total_zombie_pop <= 0:
			continue
		var ring: int = mini(HexCoord.distance(cell.coord, start), RING_SEED_PERCENT.size() - 1)
		var seeded := int(round(RING_SEED_PERCENT[ring] / 100.0 * float(cell.total_zombie_pop)))
		if seeded > 0:
			_resident[cell.coord] = seeded
	_seeded = true


## D4's self-regulating pump, run once per in-game day: every hex above the
## Hive Core threshold breeds, and the nearest hexes at 100% ship a horde back
## down to the 75% floor.
##
## Public so a verification can advance the simulation deterministically instead
## of waiting 40 real minutes per day. TickManager.day_completed can fire
## several times in one frame (its _process drains elapsed_in_day in a while
## loop, and a day is 2.4 real seconds at 1000x), so this is pure per-call
## arithmetic with no cross-frame accumulator — the same hazard
## BuildingSustenanceController documents.
func run_daily_tick() -> void:
	if not _seeded:
		return
	var bred := 0
	var candidates: Array[Vector2i] = []
	# One pass over the hordes, not one linear scan per hex: zombie_count_at()
	# is O(hordes) per call, so asking it 4,692 times a day would be
	# O(hexes * hordes) for a number that does not change during the sweep.
	var roaming: Dictionary = _horde_manager.get_zombie_counts_by_hex() if _horde_manager else {}
	for coord in _land_coords:
		var capacity := capacity_at(coord)
		if capacity <= 0:
			continue
		var count: int = resident_count_at(coord) + int(roaming.get(coord, 0))
		if float(count) < HIVE_CORE_FROM / 100.0 * float(capacity):
			continue
		var grown := mini(capacity, count + maxi(1, int(round(SPAWN_RATE_PER_DAY * float(capacity)))))
		var delta := grown - count
		if delta > 0:
			_write_resident(coord, resident_count_at(coord) + delta)
			bred += delta
		if grown >= capacity:
			candidates.append(coord)

	var exported_hordes := 0
	var exported_zombies := 0
	for coord in _nearest_exportable(candidates):
		var shipped := export_from(coord)
		if shipped <= 0:
			continue
		exported_hordes += 1
		exported_zombies += shipped
		if exported_hordes >= MAX_EXPORTS_PER_DAY:
			break

	day_simulated.emit(bred, exported_hordes, exported_zombies)


func get_save_state() -> Dictionary:
	# `infestation` and `is_cleared` are absent on purpose: both are derived
	# (D1, D2) and saving either would let it drift from the count. So is
	# `total_zombie_pop` — it is static, baked terrain data, and rebuilds
	# identically on every boot.
	return {"resident_by_hex": _resident.duplicate()}


## An EMPTY or absent dictionary means "this save predates infestation", not
## "there are no zombies". Keeping the worldgen rings in that case loads a
## hostile world; zeroing them would load a dead one, and there is no save
## format version reader to tell the two apart (SAVE_FORMAT_VERSION is written
## and never read).
func load_save_state(state: Dictionary) -> void:
	var restored: Dictionary = state.get("resident_by_hex", {})
	if restored.is_empty():
		return
	_resident = restored.duplicate()
	# Deliberately silent: no band_changed emissions during a restore. Every
	# downstream reader recomputes from band_at() afterwards, and emitting here
	# would fire consumers against half-restored state — the same restraint
	# TerritoryController.load_save_state() records.


func _seed_from_starting_settlement() -> void:
	if not _building_manager:
		return
	var start_hexes := _building_manager.get_starting_settlement_hexes()
	if start_hexes.is_empty():
		return
	seed_rings_from(start_hexes[0])


func _on_day_completed(_day_number: int) -> void:
	run_daily_tick()


func _set_resident(coord: Vector2i, count: int) -> void:
	var before := band_at(coord)
	_write_resident(coord, count)
	var after := band_at(coord)
	if after != before:
		band_changed.emit(coord, after)


## The store, without the band comparison. The daily sweep uses this because
## the comparison is what makes a write expensive — band_at() reads
## zombie_count_at(), which is a linear scan over every horde, so emitting
## from a sweep over 4,692 hexes would be O(hexes * hordes) twice over. It is
## also provably unnecessary there: the sweep only touches hexes already at or
## above the Hive Core threshold, breeding clamps at capacity, and an export
## lands the hex exactly on the 75% floor — every one of those stays
## HIVE_CORE, so no band can change.
func _write_resident(coord: Vector2i, count: int) -> void:
	var clamped := clampi(count, 0, capacity_at(coord))
	if clamped <= 0:
		_resident.erase(coord)
	else:
		_resident[coord] = clamped


## Ships one hex's overflow as a roaming horde. The exported count is whatever
## sits above the 75% floor, so the hex lands exactly on the threshold and D4's
## pump repeats. Returns how many left, or 0 if there was nothing to ship.
##
## Public because the pump has two halves worth exercising separately: WHICH
## hexes may ship (the player-distance bound and the daily cap) and WHAT
## shipping does to the hex it leaves (the conservation law above). A test that
## can only reach the second through the first cannot tell a broken bound from
## a broken export.
func export_from(coord: Vector2i) -> int:
	if not _horde_manager:
		return 0
	var capacity := capacity_at(coord)
	var floor_count := int(round(EXPORT_FLOOR_FRACTION * float(capacity)))
	# Against the RESIDENT count, not the total: a horde already standing here
	# is counted in zombie_count_at() and shipping against it would export
	# zombies that have already left.
	var resident := resident_count_at(coord)
	var available := mini(resident - floor_count, int(round(MAX_EXPORT_FRACTION_PER_DAY * float(capacity))))
	if available <= 0:
		return 0
	_write_resident(coord, resident - available)
	_horde_manager.spawn_horde_at(coord, available)
	return available


## Export candidates within EXPORT_MAX_DISTANCE_FROM_PLAYER of a player
## building, nearest first. Distance is to a real player BUILDING rather than to
## any `is_settlement` hex, because Birmingham and London are settlement hexes in
## the map data from the first frame and the player holds neither.
func _nearest_exportable(candidates: Array[Vector2i]) -> Array[Vector2i]:
	if candidates.is_empty() or not _building_manager:
		return []
	var player_hexes: Array[Vector2i] = []
	for instance: BuildingInstance in _building_manager.get_all_buildings():
		if not player_hexes.has(instance.hex_coord):
			player_hexes.append(instance.hex_coord)
	if player_hexes.is_empty():
		return []

	var ranked: Array[Vector2i] = []
	var distances: Dictionary = {}
	for coord in candidates:
		var nearest := EXPORT_MAX_DISTANCE_FROM_PLAYER + 1
		for player_hex in player_hexes:
			nearest = mini(nearest, HexCoord.distance(coord, player_hex))
			if nearest <= 0:
				break
		if nearest <= EXPORT_MAX_DISTANCE_FROM_PLAYER:
			distances[coord] = nearest
			ranked.append(coord)
	# Deterministic: distance first, then axial order, so two runs of the same
	# save export from the same hex. No randf() here on purpose — every roll in
	# HordeManager comes off one _rng seeded HORDE_SEED, and drawing from it
	# would shift every downstream ambient spawn and split.
	ranked.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if distances[a] != distances[b]:
			return distances[a] < distances[b]
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y)
	return ranked
