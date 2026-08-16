class_name ReclamationManager
extends Node

## Victorian Infrastructure Reclamation — the swamp/
## peat-bog-draining half specifically. The "rebuild destroyed stone
## bridges, steam railways, and canal locks to restore interrupted supply
## routes" half doesn't need new state: SupplyLineSegment's own doc comment
## already calls out that reclaiming a severed line "just flips is_severed
## back off" — LogisticsNetwork.restore_segment_between()
## already does exactly that. This class adds the missing piece: a
## resource-costed player action wrapping it (repair_supply_line() below),
## since restore_segment_between() itself is a free instant toggle meant for
## other systems (e.g. a future "cleared the zombies off this segment"
## trigger), not a costed reconstruction action.
##
## Wall fortification/siege-survival cascade logic (the rest of the design
## doc's Reclamation section) depends on combat, hordes, and garrisoned
## units — none of that exists yet, so it isn't attempted here.

signal swamp_drained(coord: Vector2i)
signal drain_rejected(coord: Vector2i, reason: String)
signal supply_line_repaired(hex_a: Vector2i, hex_b: Vector2i)
signal repair_rejected(hex_a: Vector2i, hex_b: Vector2i, reason: String)

@export var hex_grid_map_path: NodePath
@export var resource_manager_path: NodePath
@export var logistics_network_path: NodePath

var _hex_grid_map: HexGridMap
var _resource_manager: ResourceManager
var _logistics_network: LogisticsNetwork

## The "terrain does not need saving, fixed noise seeds regenerate it
## byte-identically" rule stopped being entirely true the moment this
## class could mutate a live HexCell — a drained swamp needs to STAY
## drained across a full app close/reopen (a fresh boot regenerates
## pristine terrain from the seed before any save is loaded), so which
## hexes were drained is the one piece of terrain state this system
## actually needs to persist. See get_save_state()/load_save_state().
var _drained_hexes: Dictionary = {}  # Vector2i -> true

## Exact numbers are a balancing pass, not an architecture decision — same
## framing as every other placeholder constant table in
## this project. Draining a Fenland basin is real Victorian civil
## engineering, priced as a deliberate, weighty investment (compare to a
## Tenant Farm's 30 Wood) rather than a casual one.
const DRAIN_COST: Dictionary = {GameEnums.ResourceType.WOOD: 40, GameEnums.ResourceType.BRICKS: 20}

## Per SupplyLineType — a railway needs more (and different) material to
## rebuild than a road or a canal lock.
const _REPAIR_COST_BY_LINE_TYPE: Dictionary = {
	GameEnums.SupplyLineType.ROAD: {GameEnums.ResourceType.WOOD: 15},
	GameEnums.SupplyLineType.RAILWAY: {GameEnums.ResourceType.IRON: 25, GameEnums.ResourceType.WOOD: 10},
	GameEnums.SupplyLineType.CANAL: {GameEnums.ResourceType.BRICKS: 20},
}

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if resource_manager_path != NodePath():
		_resource_manager = get_node(resource_manager_path)
	if logistics_network_path != NodePath():
		_logistics_network = get_node(logistics_network_path)

## Returns "" if `coord` can legally be drained right now, or a
## human-readable rejection reason otherwise — mirrors
## BuildingManager.get_placement_error()'s "queryable without side effects" pattern.
func get_drain_error(coord: Vector2i) -> String:
	if not _hex_grid_map:
		return "No hex grid map wired to ReclamationManager."
	var cell := _hex_grid_map.get_cell(coord)
	if not cell:
		return "%s is outside the map." % coord
	if not _is_drainable(cell):
		return "%s isn't a marsh or peat bog." % coord
	if _resource_manager and not _resource_manager.can_afford(DRAIN_COST):
		return "Not enough resources to drain this ground."
	return ""

func can_drain_swamp(coord: Vector2i) -> bool:
	return get_drain_error(coord).is_empty()

## Validates and spends DRAIN_COST, then hands off to _apply_drain() (below)
## for the actual terrain mutation — see that function's doc comment for
## what the mutation is and why.
func drain_swamp(coord: Vector2i) -> bool:
	var error := get_drain_error(coord)
	if not error.is_empty():
		drain_rejected.emit(coord, error)
		return false

	if _resource_manager:
		_resource_manager.spend(DRAIN_COST)
	_apply_drain(coord)

	swamp_drained.emit(coord)
	return true

func _is_drainable(cell: HexCell) -> bool:
	return cell.terrain_feature == GameEnums.TerrainFeature.MARSH or cell.terrain_feature == GameEnums.TerrainFeature.PEAT_BOG

## Marsh/peat bog -> passable, buildable countryside: terrain_feature clears
## (HexCell.is_passable() and BuildingManager's own placement checks read
## this directly), biome_type becomes MOORLAND (the marginal-farmland tier
## Tenant Farm/Cattle Yard already accept — reclaimed ground isn't instantly
## prime LUSH farmland), and soil_fertility rises from the wetland baseline
## DESOLATE to POOR to match. Pushes an immediate visual refresh through the
## existing HexCellView rather than waiting on any recompute cycle, since
## nothing else currently watches for a mutated (not newly-generated) cell.
## Shared between drain_swamp() (cost/validation already passed) and
## load_save_state() (restoring a previously-paid-for drain, same "load
## bypasses cost/validation" convention as every other manager's load path).
func _apply_drain(coord: Vector2i) -> void:
	_drained_hexes[coord] = true
	if not _hex_grid_map:
		return
	var cell := _hex_grid_map.get_cell(coord)
	if not cell:
		return
	cell.terrain_feature = GameEnums.TerrainFeature.NONE
	cell.biome_type = GameEnums.BiomeType.MOORLAND
	cell.soil_fertility = GameEnums.SoilFertility.POOR
	var view := _hex_grid_map.get_view(coord)
	if view:
		view.refresh()

func get_repair_error(hex_a: Vector2i, hex_b: Vector2i) -> String:
	if not _logistics_network:
		return "No logistics network wired to ReclamationManager."
	var segment := _logistics_network.get_segment_between(hex_a, hex_b)
	if not segment:
		return "No supply line exists between these hexes."
	if not segment.is_severed:
		return "This supply line isn't severed."
	var cost: Dictionary = _REPAIR_COST_BY_LINE_TYPE.get(segment.line_type, {})
	if _resource_manager and not _resource_manager.can_afford(cost):
		return "Not enough resources to repair this line."
	return ""

func can_repair_supply_line(hex_a: Vector2i, hex_b: Vector2i) -> bool:
	return get_repair_error(hex_a, hex_b).is_empty()

func repair_supply_line(hex_a: Vector2i, hex_b: Vector2i) -> bool:
	var error := get_repair_error(hex_a, hex_b)
	if not error.is_empty():
		repair_rejected.emit(hex_a, hex_b, error)
		return false

	var segment := _logistics_network.get_segment_between(hex_a, hex_b)
	var cost: Dictionary = _REPAIR_COST_BY_LINE_TYPE.get(segment.line_type, {})
	if _resource_manager:
		_resource_manager.spend(cost)
	_logistics_network.restore_segment_between(hex_a, hex_b)

	supply_line_repaired.emit(hex_a, hex_b)
	return true

## Exposed for SaveLoadManager — see _drained_hexes' own doc
## comment for why this is the one piece of terrain state that needs
## persisting. Supply line repairs need no equivalent: they just flip
## SupplyLineSegment.is_severed on an existing segment, and that field is
## already part of LogisticsNetwork's own saved segment list.
func get_save_state() -> Dictionary:
	var result: Array[Vector2i] = []
	result.assign(_drained_hexes.keys())
	return {"drained_hexes": result}

func load_save_state(drained_hexes: Array[Vector2i]) -> void:
	for coord in drained_hexes:
		_apply_drain(coord)
