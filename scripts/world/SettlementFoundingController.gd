class_name SettlementFoundingController
extends Node

## Second-settlement founding — design_doc.md §3's Tier 3 Town Hall
## ("Establishes a new 5mi x 5mi ZoC hex. Allows players to found far-flung
## cities specialized in extracting specific resource nodes. Only 1 can be
## built per hex tile.").
##
## Before this class, HexMapGenerator was the only thing that ever set
## HexCell.is_settlement/URBAN, and it set them once at map generation — the
## whole map had exactly three settlements (Manchester, Birmingham, Greater
## London) and no player action could ever add a fourth.
##
## What founding actually does, on a Town Hall FINISHING construction (not on
## placement — an unbuilt hall hasn't founded anything yet) on a hex that
## isn't already a settlement:
##
## 1. Flips the macro HexCell.is_settlement, which is what
##    BuildingDefinition.requires_settlement gates on. The other 11
##    settlement-gated buildings (housing, unit training, research) become
##    legal here.
## 2. Registers a growing urban disc in SubHexTerrainOverride, so the sub-hex
##    biome under the town really is URBAN. That matters because those same
##    11 buildings ALSO restrict allowed_biomes to URBAN, and
##    BuildingManager.get_placement_error() resolves allowed_biomes at
##    sub-hex resolution — is_settlement alone would found a city nothing
##    could be built in.
##
## The disc, not the whole hex, is the user-specified rule: "it should be a
## radius around the town hall that starts at 1 mile diameter circle and at
## tier 4 levels of population it should cover the whole hex tile." So a new
## foundation paves a half-mile radius around the hall itself and spreads
## outward as the settlement's population grows, rather than instantly
## turning ~10km of countryside into city.
##
## Macro HexCell.biome_type is flipped to URBAN only once the disc covers the
## whole hex, and back to the hex's original biome if it ever shrinks below
## that. Deriving it from the radius every recompute (rather than latching it
## on at founding) is what keeps the macro and sub-hex layers from
## disagreeing: while the town is still a disc, the macro biome still
## describes what most of the hex actually is, and strategic-zoom visuals and
## HexPathfinder's per-biome cost stay honest.
##
## Does NOT re-run DistrictPartitioner for a founded hex. Districts are a
## fixed categorical map-gen template (todo.md's "Known Architecture
## Constraint"); repartitioning a live hex is that constraint's problem to
## solve, not something to bolt on here.
##
## No save state of its own. Everything above is derived from two things a
## save already restores — which hexes carry a Town Hall, and the
## current_population of the buildings on them — so rebuild_from_buildings()
## reconstructs the full founded set after a load instead of persisting a
## parallel copy that could disagree with the buildings it describes. That's
## the difference from ReclamationManager._drained_hexes/TerritoryController.
## _lost_hexes, which both persist because nothing else records what they did.

signal settlement_founded(coord: Vector2i)
signal settlement_abandoned(coord: Vector2i)
signal urban_extent_changed(coord: Vector2i, radius: float)

@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath

var _hex_grid_map: HexGridMap
var _building_manager: BuildingManager

## Vector2i -> original GameEnums.BiomeType, for hexes THIS class founded.
## Same bookkeeping discipline TerritoryController._lost_hexes keeps: only
## ever revert state this class itself caused, so a map-gen settlement
## (Manchester's starting Town Hall included) is never un-founded or
## repainted by a Town Hall being demolished on it.
var _founded: Dictionary = {}

## design_doc.md §3 gives the Town Hall a "5mi x 5mi" ZoC but no figure at
## all for how much ground the settlement itself paves, so both ends of the
## growth curve are a disclosed interpretive choice, not a doc quote.
##
## Near end — "starts at 1 mile diameter circle" (user), i.e. a half-mile
## radius around the hall.
const FOUNDING_RADIUS_MILES: float = 0.5

## Far end — "at tier 4 levels of population it should cover the whole hex
## tile" (user). design_doc.md has no Tier 4 housing to read a figure off:
## its housing ladder stops at Tier 2 (Wooden Houses 50 pop, Brick Houses
## 200, Tower Blocks 500). 2000 is that ladder's top rung stacked four deep —
## the most housing a single hex plausibly carries by the Tier 4 era — chosen
## because it's derived from real catalog numbers rather than invented whole.
## A balancing pass, not an architectural commitment.
const FULL_COVERAGE_POPULATION: float = 2000.0

## HexCoord.HEX_SIZE IS the hex's circumradius (that constant's own doc
## comment), so a disc of exactly that radius covers every corner of the hex
## — "the whole hex tile" needs no separate figure.
const _FULL_COVERAGE_RADIUS: float = HexCoord.HEX_SIZE

const _METERS_PER_MILE: float = 1609.344
const _FOUNDING_RADIUS: float = FOUNDING_RADIUS_MILES * _METERS_PER_MILE * HexCoord.WORLD_UNITS_PER_REAL_METER

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
		# Founding itself only ever triggers off construction completing.
		# The rest re-run the population -> radius recompute, since each can
		# change what current_population on the hex sums to: ruined zeroes a
		# building's population, repaired restores it, removed/demolished
		# take it away entirely (and can un-found the hex outright).
		_building_manager.building_construction_completed.connect(_on_construction_completed)
		_building_manager.building_ruined.connect(_on_building_ruined)
		_building_manager.building_repaired.connect(_on_building_changed)
		_building_manager.building_removed.connect(_on_building_changed)
		_building_manager.building_demolished.connect(_on_building_changed)

func is_founded(coord: Vector2i) -> bool:
	return _founded.has(coord)

func get_founded_hexes() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_founded.keys())
	return result

## Urban radius (world units) currently paved at `coord`, 0.0 if never
## founded. Reads through to SubHexTerrainOverride rather than keeping a
## second copy — that store is the one authority on the live extent.
func get_urban_radius(coord: Vector2i) -> float:
	return SubHexTerrainOverride.get_urban_radius(coord)

func _on_construction_completed(instance: BuildingInstance) -> void:
	if instance.definition.building_type == GameEnums.BuildingType.TOWN_HALL:
		_try_found(instance.hex_coord)
	_refresh_extent(instance.hex_coord)

func _on_building_ruined(instance: BuildingInstance, _lost_population: int) -> void:
	_on_building_changed(instance)

## A hex keeps its settlement for as long as a Town Hall instance stands on
## it in ANY condition — a ruined hall is a burnt-out building in a town that
## still exists, not the town ceasing to exist. Only the hall actually going
## away (demolished, or removed) un-founds the hex.
func _on_building_changed(instance: BuildingInstance) -> void:
	var coord := instance.hex_coord
	if _founded.has(coord) and not _has_town_hall(coord):
		_abandon(coord)
		return
	_refresh_extent(coord)

func _has_town_hall(coord: Vector2i) -> bool:
	if not _building_manager:
		return false
	for instance in _building_manager.get_buildings_at(coord):
		if instance.definition.building_type == GameEnums.BuildingType.TOWN_HALL and not instance.is_under_construction:
			return true
	return false

func _try_found(coord: Vector2i) -> void:
	if _founded.has(coord) or not _hex_grid_map:
		return
	var cell := _hex_grid_map.get_cell(coord)
	if not cell or cell.is_settlement:
		return  # Already a settlement — a Town Hall rebuilt in Manchester founds nothing, and must not be recorded as this class's to revert.
	_founded[coord] = cell.biome_type
	cell.is_settlement = true
	settlement_founded.emit(coord)

func _abandon(coord: Vector2i) -> void:
	var original_biome: GameEnums.BiomeType = _founded[coord]
	_founded.erase(coord)
	SubHexTerrainOverride.clear_urban_disc(coord)
	if _hex_grid_map:
		var cell := _hex_grid_map.get_cell(coord)
		if cell:
			cell.is_settlement = false
			cell.biome_type = original_biome
	urban_extent_changed.emit(coord, 0.0)
	settlement_abandoned.emit(coord)

## Recomputes `coord`'s paved radius from the population currently housed
## there. No-ops for a hex this class didn't found, so a map-gen settlement
## never grows a disc — its whole hex is already URBAN from map generation.
func _refresh_extent(coord: Vector2i) -> void:
	if not _founded.has(coord) or not _building_manager:
		return
	var center := _town_hall_center(coord)
	var radius := _radius_for_population(_population_at(coord))
	if not SubHexTerrainOverride.set_urban_disc(coord, center, radius):
		return  # Boundary didn't actually move — nothing to repaint or re-derive.
	_sync_macro_biome(coord, radius)
	urban_extent_changed.emit(coord, radius)

## The disc is centered on the Town Hall's own sub-hex position, not the hex
## center — BuildingInstance.local_position stopped being cosmetic with the
## Sub-Hex Mechanical Layer epic, and a town visibly growing out from
## somewhere other than its own hall would contradict that.
func _town_hall_center(coord: Vector2i) -> Vector2:
	var hex_center := HexCoord.axial_to_world(coord)
	for instance in _building_manager.get_buildings_at(coord):
		if instance.definition.building_type == GameEnums.BuildingType.TOWN_HALL:
			return hex_center + instance.local_position
	return hex_center

func _population_at(coord: Vector2i) -> float:
	var total := 0.0
	for instance in _building_manager.get_buildings_at(coord):
		total += float(instance.current_population)
	return total

## Interpolates paved AREA, not radius, so the town spreads at roughly
## constant population density — doubling the population doubles the ground
## it covers, which a linear radius ramp would not do (it would quadruple
## it near the end and barely move at the start).
func _radius_for_population(population: float) -> float:
	var t := clampf(population / FULL_COVERAGE_POPULATION, 0.0, 1.0)
	# r^2 is area/pi, so interpolating the squared radius IS interpolating
	# area. lerpf(), not lerp() — the untyped lerp() returns Variant, which
	# this project's warnings-as-errors config rejects.
	var radius_squared := lerpf(_FOUNDING_RADIUS * _FOUNDING_RADIUS, _FULL_COVERAGE_RADIUS * _FULL_COVERAGE_RADIUS, t)
	return sqrt(radius_squared)

## Keeps the macro biome agreeing with the sub-hex layer: URBAN only once the
## disc actually covers the hex, the original biome otherwise. See this
## class's own doc comment for why this is derived every recompute rather
## than latched on at founding.
func _sync_macro_biome(coord: Vector2i, radius: float) -> void:
	if not _hex_grid_map:
		return
	var cell := _hex_grid_map.get_cell(coord)
	if not cell:
		return
	var fully_covered := radius >= _FULL_COVERAGE_RADIUS
	var target: GameEnums.BiomeType = GameEnums.BiomeType.URBAN if fully_covered else _founded[coord]
	if cell.biome_type != target:
		cell.biome_type = target

## Reconstructs every founded hex from the buildings currently registered
## with BuildingManager — called by SaveLoadManager after buildings restore.
## See this class's own doc comment for why founding carries no save state of
## its own.
##
## Clears first, both here and in SubHexTerrainOverride: a load into a
## running session must not inherit the previous game's founded hexes, the
## same clear-then-restore contract BuildingManager.load_save_entries()
## follows.
func rebuild_from_buildings() -> void:
	for coord: Vector2i in _founded.keys():
		_restore_biome(coord)
	_founded.clear()
	SubHexTerrainOverride.clear_all()
	if not _building_manager:
		return
	for instance in _building_manager.get_all_buildings():
		if instance.definition.building_type != GameEnums.BuildingType.TOWN_HALL or instance.is_under_construction:
			continue
		_try_found(instance.hex_coord)
	for coord: Vector2i in _founded.keys():
		_refresh_extent(coord)

## Reverts one hex's macro state without emitting — rebuild_from_buildings()
## is a wholesale restore, not a gameplay event, and TerritoryController.
## load_save_state() sets the same precedent of restoring silently.
func _restore_biome(coord: Vector2i) -> void:
	if not _hex_grid_map:
		return
	var cell := _hex_grid_map.get_cell(coord)
	if not cell:
		return
	cell.is_settlement = false
	cell.biome_type = _founded[coord]
