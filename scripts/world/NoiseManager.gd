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

## Attraction a lit_at_night source adds to its own hex after dark. D101: "their
## settlement creating more light and noise drawing in zombies from further
## afield" — so light has a reach, and lamps SUM (brightness adds), which is what
## makes a bigger lit settlement visible from further away. Still the crude
## version: a radial falloff with no line of sight (full §6 illumination is
## Deferred), blocked only where NoisePropagation says a Level 4 mountain blocks
## the path.
##
## Balance numbers, chosen against HordeManager.ATTRACTION_THRESHOLD 3.0 for a
## horde of mean susceptibility: one lamp (2.5 on its hex) does not draw a horde
## on its own; two lamps on one hex draw from 2 hexes and three from 3. A jumpy
## horde (threshold 1.9) sees one lamp from 1 hex and two from 3.
const NIGHT_LIGHT_ATTRACTION: float = 2.5
## Hexes a lamp is seen across, falling linearly to a fifth of
## NIGHT_LIGHT_ATTRACTION at this distance and to nothing past it. Kept at or
## under HordeManager.ATTRACTION_AWARENESS_RADIUS, the furthest a horde perceives
## anything, which HordeFlowField.REGION_RADIUS is sized against.
const NIGHT_LIGHT_REACH_HEXES: int = 4

## What a hex's attraction is mostly made of, for a horde that has to pick a
## direction and for a player who has to know what to switch off.
const KIND_NOISE: StringName = &"noise"
const KIND_LIGHT: StringName = &"light"

@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath

var _hex_grid_map: HexGridMap
var _building_manager: BuildingManager
var _noise_by_hex: Dictionary = {}  # Vector2i -> float attraction
## Vector2i -> [BuildingInstance, float contribution, StringName kind]: for each
## hex, the SOURCE HEX contributing the most attraction there, represented by its
## strongest building. Summed per source hex, not taken per building, because a
## horde perceives a place: a town of three lamps is brighter than one lamp even
## where each of the three is dimmer. Contributions are compared in the
## attraction domain (dB above HEARING_THRESHOLD_DB for sound, the falloff value
## for light), the domain the field itself sums in.
var _dominant_by_hex: Dictionary = {}

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

## The building contributing the most attraction at `coord`, or null where
## nothing reaches. A horde standing on `coord` walks toward this building's hex:
## it follows the strongest signal where it stands, so a decoy lamp nearer the
## horde out-pulls a louder town further off, and switching the dominant source
## off hands the horde to the next one or to nothing.
func get_dominant_source_at(coord: Vector2i) -> BuildingInstance:
	var entry: Array = _dominant_by_hex.get(coord, [])
	return entry[0] if not entry.is_empty() else null

## KIND_NOISE or KIND_LIGHT for get_dominant_source_at(); &"" where nothing
## reaches.
func get_dominant_kind_at(coord: Vector2i) -> StringName:
	var entry: Array = _dominant_by_hex.get(coord, [])
	return entry[2] if not entry.is_empty() else &""

## Every hex carrying nonzero attraction. The field is sparse by construction
## — recompute() only records a hex a source can actually be heard on, which
## is tens of hexes against a 27,566-hex map — so a caller that needs to draw
## or scan "everywhere there is noise" should iterate this rather than test
## every hex.
##
## MinimapView's Threat Meter did the latter, and its own comment called it
## "cheap at this scale ... get_noise_at() is already a plain Dictionary
## lookup". Each lookup is cheap; 27,566 of them per frame measured 17.7 ms
## of a 48 ms frame (scripts/test/profile_tactical_bisect.gd).
func get_attracting_hexes() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_noise_by_hex.keys())
	return result

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
	var light_by_hex: Dictionary = {}      # Vector2i -> summed night-light attraction
	var contributions: Dictionary = {}  # listener Vector2i -> {source Vector2i: [summed float, strongest BuildingInstance, its float, kind]}
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
			_accumulate_sound(instance, is_night, intensity_by_hex, contributions)
			# The lamp, not the building: an unbuilt Gas Streetlamp is not
			# lit, so a construction site draws nothing through this term
			# even though the line above deliberately leaves it loud. Same
			# claim FogOfWarManager._building_vision_radius() makes about the
			# same lamp, and CombatCoordinator about the same Search Light
			# beam.
			if is_night and instance.definition.lit_at_night and not instance.is_under_construction:
				_accumulate_light(instance, light_by_hex, contributions)

	var result: Dictionary = {}
	for coord in intensity_by_hex:
		var attraction := NoisePropagation.level_from_intensity(intensity_by_hex[coord]) - NoisePropagation.HEARING_THRESHOLD_DB
		if attraction > 0.0:
			result[coord] = attraction
	for coord in light_by_hex:
		result[coord] = result.get(coord, 0.0) + light_by_hex[coord]
	_noise_by_hex = result
	_dominant_by_hex = _dominant_from(contributions)
	noise_recomputed.emit()

## Adds one building's acoustic intensity to every hex that can hear it.
##
## The disc is sized from the source itself rather than a shared constant:
## NoisePropagation.distance_to_level() gives the range at which this building
## falls to the hearing threshold, and only that many rings are visited. A
## Brickworks touches 7 hexes where a Bessemer complex touches 37.
func _accumulate_sound(instance: BuildingInstance, is_night: bool, out_intensity: Dictionary, out_contributions: Dictionary) -> void:
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
		_add_contribution(out_contributions, coord, instance, level - NoisePropagation.HEARING_THRESHOLD_DB, KIND_NOISE)

## Adds one lit building's night light to every hex within
## NIGHT_LIGHT_REACH_HEXES, falling off linearly with hex distance — see
## NIGHT_LIGHT_ATTRACTION for the numbers.
func _accumulate_light(instance: BuildingInstance, out_light: Dictionary, out_contributions: Dictionary) -> void:
	for coord in HexCoord.hex_disk(instance.hex_coord, NIGHT_LIGHT_REACH_HEXES):
		if _hex_grid_map and not _hex_grid_map.has_cell(coord):
			continue
		if coord != instance.hex_coord and NoisePropagation.attenuation_db(instance.hex_coord, coord, _hex_grid_map) == NoisePropagation.BLOCKED:
			continue
		var distance := HexCoord.distance(instance.hex_coord, coord)
		var value := NIGHT_LIGHT_ATTRACTION * (1.0 - float(distance) / float(NIGHT_LIGHT_REACH_HEXES + 1))
		out_light[coord] = out_light.get(coord, 0.0) + value
		_add_contribution(out_contributions, coord, instance, value, KIND_LIGHT)

static func _add_contribution(out_contributions: Dictionary, coord: Vector2i, instance: BuildingInstance, contribution: float, kind: StringName) -> void:
	if contribution <= 0.0:
		return
	if not out_contributions.has(coord):
		out_contributions[coord] = {}
	var by_source: Dictionary = out_contributions[coord]
	var entry: Array = by_source.get(instance.hex_coord, [0.0, null, 0.0, kind])
	entry[0] = float(entry[0]) + contribution
	if entry[1] == null or contribution > float(entry[2]):
		entry[1] = instance
		entry[2] = contribution
		entry[3] = kind
	by_source[instance.hex_coord] = entry

## Collapses per-source-hex sums into the dominant entry per listener hex. Ties
## break on axial order so the same field always names the same source.
static func _dominant_from(contributions: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for coord in contributions:
		var by_source: Dictionary = contributions[coord]
		var best_hex := Vector2i.ZERO
		var best: Array = []
		for source_hex: Vector2i in by_source:
			var entry: Array = by_source[source_hex]
			if best.is_empty() or float(entry[0]) > float(best[0]) or (is_equal_approx(float(entry[0]), float(best[0])) and (source_hex.x < best_hex.x or (source_hex.x == best_hex.x and source_hex.y < best_hex.y))):
				best = entry
				best_hex = source_hex
		result[coord] = [best[1], best[0], best[3]]
	return result

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
