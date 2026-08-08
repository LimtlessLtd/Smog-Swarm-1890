class_name NoiseManager
extends Node

## Design doc Phase 5.2: "Industrial noise fills Threat Meters, triggering
## night raids from uncleared wilderness" — the piece this exact bullet, and
## Phase 5.10's ATTRACTED horde state, and Phase 6.1's still-unbuilt Threat
## Meter HUD were ALL blocked on ("nothing currently tracks a per-building/
## per-hex noise output"). Mirrors FogOfWarManager's exact shape: a per-hex
## Dictionary recomputed from BuildingManager's placements on every
## building_placed/removed/building_ruined signal, plus
## TimeCycleManager.phase_changed for the night doubling design doc 5.1
## already calls for — same "owns neither BuildingManager nor HexGridMap,
## only derives a per-hex field from them" relationship FogOfWarManager and
## LogisticsNetwork both already have. Wired as a Main.tscn sibling of those
## systems, same reasoning as FogOfWarManager (never spawns its own
## positioned Node2D children, just a queryable data source).
##
## Deliberately an AURA, same shape as Zone of Control/vision (design doc,
## explicit under 5.10: "gunfire/noise/light project a limited radius ...
## not colony-wide awareness") — a flat BuildingDefinition.noise_output
## value applied to every hex within a fixed NOISE_RADIUS of the source, no
## distance falloff. Matches FogOfWarManager's own vision_radius precedent:
## simplicity over realism for a first pass, a balancing/feel refinement to
## revisit later, not an architecture gap.
##
## Multiple overlapping sources SUM on a shared hex (a hex next to both a
## Foundry and a Powder Mill is louder than either alone) rather than taking
## the max — closer to how real industrial noise actually stacks, and gives
## a dense industrial district a genuine reason to draw more attention than
## any single loud building would on its own.
##
## Phase 2.6's lit_at_night sources ALSO contribute, night only (design doc
## Phase 5.10: "a horde within range of a noise or light source above
## threshold ... Phase 2.6's lit vision sources at night") — a fixed
## NIGHT_LIGHT_ATTRACTION add-on, stacking with (not replacing) whatever
## noise_output that same building already has, so a lit-but-otherwise-quiet
## perimeter (a Gas Streetlamp ring with no industry behind it) still draws
## SOME attention after dark, just less than an active foundry district
## would. A ruined building contributes nothing — rubble has no operating
## machinery left to be loud, and no light left to cast.

signal noise_recomputed

## Placeholder balancing numbers, not architecture decisions — same framing
## as every other constant table in this project (HordeManager's own
## WALL_SIEGE_DAMAGE_MULTIPLIER, UnitCatalog's per-tier curve, etc.).
const NOISE_RADIUS: int = 2
const NIGHT_NOISE_MULTIPLIER: float = 2.0  ## Design doc Phase 5.1: "double noise-attraction multiplier" at night.
const NIGHT_LIGHT_ATTRACTION: float = 1.0  ## A lit_at_night source's own flat night-only contribution.

@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath

var _hex_grid_map: HexGridMap
var _building_manager: BuildingManager
var _noise_by_hex: Dictionary = {}  # Vector2i -> float

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
		_building_manager.building_placed.connect(_on_buildings_changed)
		_building_manager.building_removed.connect(_on_buildings_changed)
		_building_manager.building_ruined.connect(_on_building_ruined)
	TimeCycleManager.phase_changed.connect(_on_phase_changed)
	recompute()

func get_noise_at(coord: Vector2i) -> float:
	return _noise_by_hex.get(coord, 0.0)

## The loudest hex within `radius` of `coord` (INCLUSIVE of `coord` itself)
## — HordeManager's own "attraction is local, not global" check (design doc
## 5.10) reads this rather than the raw per-hex Dictionary directly. Returns
## `coord` itself both when nothing in range is louder than `coord` already
## is, AND when nothing at all has been generated there — callers that care
## about the difference check get_noise_at() on the result themselves
## (HordeManager._pick_attraction_target() does exactly that against
## ATTRACTION_THRESHOLD).
func get_loudest_hex_within(coord: Vector2i, radius: int) -> Vector2i:
	var best_coord := coord
	var best_noise := get_noise_at(coord)
	for candidate in HexCoord.hex_disk(coord, radius):
		var noise := get_noise_at(candidate)
		if noise > best_noise:
			best_noise = noise
			best_coord = candidate
	return best_coord

## Recomputes the current noise field from scratch — cheap enough to call on
## every building/day-phase change at this scale, same reasoning
## FogOfWarManager.recompute()/LogisticsNetwork.recompute() already give.
func recompute() -> void:
	var result: Dictionary = {}
	if _building_manager:
		var is_night := TimeCycleManager.is_night()
		for instance in _building_manager.get_all_buildings():
			if instance.is_ruined:
				continue
			var contribution := float(instance.definition.noise_output)
			if is_night:
				contribution *= NIGHT_NOISE_MULTIPLIER
			if is_night and instance.definition.lit_at_night:
				contribution += NIGHT_LIGHT_ATTRACTION
			if contribution <= 0.0:
				continue
			for coord in HexCoord.hex_disk(instance.hex_coord, NOISE_RADIUS):
				if not _hex_grid_map or _hex_grid_map.has_cell(coord):
					result[coord] = result.get(coord, 0.0) + contribution
	_noise_by_hex = result
	noise_recomputed.emit()

func _on_buildings_changed(_instance: BuildingInstance) -> void:
	recompute()

func _on_building_ruined(_instance: BuildingInstance, _lost_population: int) -> void:
	recompute()

func _on_phase_changed(_phase: GameEnums.DayPhase) -> void:
	recompute()
