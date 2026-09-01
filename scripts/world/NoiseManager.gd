class_name NoiseManager
extends Node

## Per-hex ATTRACTION tracking, feeding the Threat Meter HUD and
## HordeManager's ATTRACTED state. Mirrors FogOfWarManager's exact shape: a
## per-hex Dictionary recomputed from BuildingManager's placements on every
## building_placed/removed/building_ruined signal, plus
## TimeCycleManager.phase_changed for the night term — same "owns
## neither BuildingManager nor HexGridMap, only derives a per-hex field
## from them" relationship FogOfWarManager and LogisticsNetwork have. Wired
## as a Main.tscn sibling of those systems, same reasoning as
## FogOfWarManager (never spawns its own positioned Node2D children, just a
## queryable data source).
##
## ## What a hex's number is
##
## `attraction = max(0, combined_sound_db - HEARING_THRESHOLD_DB) + light_term`
##
## The sound half is real decibels, produced by `NoisePropagation` from each
## building's `noise_source_db` with distance attenuation, air absorption and
## design_doc.md §6's terrain rules. The light half is still the flat
## night-only placeholder D10 calls the crude version — a lit perimeter with no
## industry behind it draws SOME attention after dark. The two are added in the
## attraction domain, not the acoustic one, because light is not sound and
## nothing is served by pretending a Gas Streetlamp has a decibel rating.
##
## ## What this replaced, and why the numbers moved
##
## Until 2026-09-01 this was a FLAT aura: a hard-edged 2-hex disc of a
## per-building constant, no falloff, identical for a Brickworks and a
## Bessemer complex. It was ~43x the reach of §6's loudest listed sound, which
## is what `backlog.md` filed; but §6's whole table fits inside a twentieth of
## one hex, so the fix was not to shrink the aura to §6's radii — see
## `NoisePropagation`'s header for why doing that would delete the ATTRACTED
## mechanic outright.
##
## Three things changed, measured in `scripts/test/verify_noise_emission.gd`:
##
## - **Reach now depends on the source.** A Brickworks pulls a horde from 0.85
##   hexes and a Bessemer Smelting Complex from 2.03; before, both pulled from
##   exactly 2. The loudest building is calibrated to land where the flat disc
##   already was, so this is a change of shape rather than of balance.
## - **Reach now depends on the terrain between.** A kilometre of woodland on
##   the path costs 6 dB, crossing high ground costs 6 dB once, and a Level 4
##   mountain blocks the path entirely (§6). Building the foundry behind a
##   ridge is now a real decision.
## - **Sources combine as intensities, not as sums.** Four equal buildings on
##   one hex are +6 dB, so their pull grows 1.45 -> 1.71 hexes rather than
##   quadrupling. The old comment here claimed summing was "closer to how real
##   industrial noise stacks"; it is the opposite, and the flat model was
##   wrong about the physics as well as about the scale.
##
## design_doc.md §2.1's "Going dark" reaches this class through
## BuildingManager.building_powered_down/building_powered_up, connected
## alongside the placed/removed/ruined trio below: a switched-off building
## contributes neither noise nor light, so the field has to be rebuilt the
## instant the player pulls the switch, not on whatever unrelated change
## happens next. A ruined building contributes nothing — rubble has no
## operating machinery left to be loud, and no light left to cast.
##
## Sub-Hex Mechanical Layer Phase 5b (todo.md, [[sub-hex-mechanical-layer-epic]]
## memory) — both ends of this field stay sub-hex-aware. The SOURCE side keeps
## each building's real hex_coord + local_position for the DISTANCE term, so a
## Foundry near its hex's edge is genuinely louder on that side. (Terrain
## attenuation is cast between hex centres and cached per pair — see
## `NoisePropagation.attenuation_db()` for why the two halves split there.) The
## LISTENER side is get_loudest_hex_within()'s optional
## `listener_local_position`, so HordeManager can scan from a horde's own
## sub-hex position rather than its hex_coord.

signal noise_recomputed

## Attraction a lit_at_night source adds to its own hex after dark, on top of
## whatever its machinery already emits. Unchanged from the flat model, and
## still the placeholder D10 describes: full §6 line-of-sight illumination is
## a later increment, and until it exists there is nothing to derive a
## distance curve from.
const NIGHT_LIGHT_ATTRACTION: float = 1.0

@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath

var _hex_grid_map: HexGridMap
var _building_manager: BuildingManager
var _noise_by_hex: Dictionary = {}  # Vector2i -> float attraction

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
		_building_manager.building_placed.connect(_on_buildings_changed)
		_building_manager.building_removed.connect(_on_buildings_changed)
		_building_manager.building_ruined.connect(_on_building_ruined)
		_building_manager.building_powered_down.connect(_on_buildings_changed)
		_building_manager.building_powered_up.connect(_on_buildings_changed)
		# The two transitions back. Without them a rebuilt foundry stayed
		# silent, and a building that finished construction kept whatever the
		# site was emitting, until the next TimeCycleManager phase flip
		# happened to rebuild the field — up to half an in-game day (1200
		# scaled seconds), and forever while the game is paused. Ruin already
		# had its trigger; only the return paths were missing.
		_building_manager.building_repaired.connect(_on_buildings_changed)
		_building_manager.building_construction_completed.connect(_on_buildings_changed)
	TimeCycleManager.phase_changed.connect(_on_phase_changed)
	recompute()

func get_noise_at(coord: Vector2i) -> float:
	return _noise_by_hex.get(coord, 0.0)

## The loudest hex within `radius` of a listener sitting at
## `listener_local_position` inside `coord` (INCLUSIVE of `coord` itself) —
## HordeManager's own "attraction is local, not global" check reads this
## rather than the raw per-hex Dictionary directly, passing the horde's own
## `local_position` (Phase 5b) so a horde standing near its hex's edge
## scans from where it actually is, not just which hex it's in. Returns
## `coord` itself both when nothing in range is louder than `coord` already
## is, AND when nothing at all has been generated there — callers that care
## about the difference check get_noise_at() on the result themselves
## (HordeManager._pick_attraction_target() does exactly that against
## ATTRACTION_THRESHOLD). `listener_local_position` defaults to
## Vector2.ZERO (the old hex-center behavior) for any other caller.
func get_loudest_hex_within(coord: Vector2i, radius: int, listener_local_position: Vector2 = Vector2.ZERO) -> Vector2i:
	var best_coord := coord
	var best_noise := get_noise_at(coord)
	for candidate in HexCoord.sub_hex_disk(coord, listener_local_position, radius):
		var noise := get_noise_at(candidate)
		if noise > best_noise:
			best_noise = noise
			best_coord = candidate
	return best_coord

## Recomputes the current attraction field from scratch — cheap enough to call
## on every building/day-phase change at this scale, same reasoning
## FogOfWarManager.recompute()/LogisticsNetwork.recompute() give. The
## expensive half, terrain attenuation, is cached per hex pair inside
## NoisePropagation and so is paid once per source/listener pair ever, not
## once per recompute.
func recompute() -> void:
	var intensity_by_hex: Dictionary = {}  # Vector2i -> summed acoustic intensity
	var light_by_hex: Dictionary = {}      # Vector2i -> flat night-light attraction
	if _building_manager:
		var is_night := TimeCycleManager.is_night()
		for instance in _building_manager.get_all_buildings():
			# A switched-off building emits neither the sound term nor the
			# lit_at_night night add-on below — design_doc.md §2.1's "Going
			# dark", and the whole reason the mechanic exists: this is the
			# line a player pulls to stop a horde walking toward their foundry
			# district. A building still UNDER CONSTRUCTION is deliberately
			# left loud (§6 rates Building Construction at 8 tiles) and cannot
			# be switched off anyway
			# (BuildingPowerController.get_power_down_error()).
			if instance.is_ruined or instance.is_powered_down:
				continue
			_accumulate_sound(instance, is_night, intensity_by_hex)
			# The lamp, not the building: an unbuilt Gas Streetlamp is not
			# lit, so a construction site draws nothing through this term
			# even though the line above deliberately leaves it loud. Same
			# claim FogOfWarManager._building_vision_radius() makes about the
			# same lamp, and CombatCoordinator about the same Search Light
			# beam.
			if is_night and instance.definition.lit_at_night and not instance.is_under_construction:
				light_by_hex[instance.hex_coord] = light_by_hex.get(instance.hex_coord, 0.0) + NIGHT_LIGHT_ATTRACTION

	var result: Dictionary = {}
	for coord in intensity_by_hex:
		var attraction := NoisePropagation.level_from_intensity(intensity_by_hex[coord]) - NoisePropagation.HEARING_THRESHOLD_DB
		if attraction > 0.0:
			result[coord] = attraction
	for coord in light_by_hex:
		result[coord] = result.get(coord, 0.0) + light_by_hex[coord]
	_noise_by_hex = result
	noise_recomputed.emit()

## Adds one building's acoustic intensity to every hex that can hear it.
##
## The disc is sized from the source itself rather than a shared constant:
## NoisePropagation.distance_to_level() gives the range at which this building
## falls to the hearing threshold, and only that many rings are visited. A
## Brickworks touches 7 hexes where a Bessemer complex touches 37.
func _accumulate_sound(instance: BuildingInstance, is_night: bool, out_intensity: Dictionary) -> void:
	var source_db := instance.definition.noise_source_db
	if source_db <= 0.0:
		return  # 0.0 is the catalogue's "not machinery" sentinel, not a 0 dB source.
	if is_night:
		source_db += NoisePropagation.NIGHT_PROPAGATION_BONUS_DB

	var audible_metres := NoisePropagation.distance_to_level(source_db, NoisePropagation.HEARING_THRESHOLD_DB)
	var rings := ceili(audible_metres / _hex_step_metres())
	var source_world := HexCoord.axial_to_world(instance.hex_coord) + instance.local_position

	for coord in HexCoord.hex_disk(instance.hex_coord, rings):
		if _hex_grid_map and not _hex_grid_map.has_cell(coord):
			continue
		var attenuation := NoisePropagation.attenuation_db(instance.hex_coord, coord, _hex_grid_map)
		if attenuation == NoisePropagation.BLOCKED:
			continue
		var distance_metres := source_world.distance_to(HexCoord.axial_to_world(coord)) / HexCoord.WORLD_UNITS_PER_REAL_METER
		var level := NoisePropagation.level_at(source_db, distance_metres, attenuation)
		if level <= NoisePropagation.HEARING_THRESHOLD_DB:
			continue
		out_intensity[coord] = out_intensity.get(coord, 0.0) + NoisePropagation.intensity_of(level)

## Centre-to-centre distance between neighbouring hexes, in metres — the unit
## an audible radius has to be converted into to become a ring count. Derived
## from HexCoord rather than restated as a constant, so it cannot drift from
## HEX_SIZE the way a copied number would.
func _hex_step_metres() -> float:
	return HexCoord.axial_to_world(Vector2i(1, 0)).length() / HexCoord.WORLD_UNITS_PER_REAL_METER

func _on_buildings_changed(_instance: BuildingInstance) -> void:
	recompute()

func _on_building_ruined(_instance: BuildingInstance, _lost_population: int) -> void:
	recompute()

func _on_phase_changed(_phase: GameEnums.DayPhase) -> void:
	recompute()
