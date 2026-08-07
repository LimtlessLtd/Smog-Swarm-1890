class_name SaveLoadManager
extends Node

## Aggregates state out of BuildingManager / ResourceManager /
## LogisticsNetwork / FogOfWarManager / TechManager / DiscontentManager /
## WallManager / ReclamationManager / HordeManager / UnitManager /
## TerritoryController / TickManager into a single SaveGameData Resource and
## back again (design doc Phase 2.8.2).
## Wired as a Main.tscn sibling via exported NodePaths, same pattern as
## LogisticsNetwork/FogOfWarManager — it owns none of that state, only
## reads and restores it.
##
## **Decided (design doc 2.8.3):** saves are grouped by a player-named
## Campaign, with multiple manual save slots per campaign and multiple
## independent campaigns coexisting on disk. This class only knows how to
## list/read/write one campaign+slot at a time; the actual Save/Load UI is
## out of scope until Phase 6's HUD work — nothing here depends on it
## existing, a future screen just calls into this the same way a headless
## test does.
##
## "Persistent background" (design doc, Phase 2.8 header) describes what
## BackgroundExecutionManager already does DURING a play session — it does
## NOT mean the colony simulates while the application is closed. There is
## deliberately no elapsed-time/catch-up math here: closing the game pauses
## everything exactly where it was, and loading resumes there, nothing more.

signal game_saved(campaign_name: String, slot_name: String)
signal game_loaded(campaign_name: String, slot_name: String)
signal load_failed(campaign_name: String, slot_name: String, reason: String)

const SAVE_FORMAT_VERSION: int = 1
const SAVES_ROOT: String = "user://saves"

## Characters that are unsafe in a filename across the platforms Godot's
## `user://` maps to. Hand-rolled rather than relying on
## String.validate_filename() (only added in a specific 4.x minor version)
## so this doesn't depend on exactly which 4.x patch is running.
const _UNSAFE_FILENAME_CHARS: Array[String] = [":", "/", "\\", "?", "*", "\"", "<", ">", "|"]

@export var building_manager_path: NodePath
@export var resource_manager_path: NodePath
@export var logistics_network_path: NodePath
@export var fog_of_war_manager_path: NodePath
@export var tech_manager_path: NodePath
@export var discontent_manager_path: NodePath
@export var wall_manager_path: NodePath
@export var reclamation_manager_path: NodePath
@export var horde_manager_path: NodePath
@export var unit_manager_path: NodePath
@export var territory_controller_path: NodePath

var _building_manager: BuildingManager
var _resource_manager: ResourceManager
var _logistics_network: LogisticsNetwork
var _fog_of_war_manager: FogOfWarManager
var _tech_manager: TechManager
var _discontent_manager: DiscontentManager
var _wall_manager: WallManager
var _reclamation_manager: ReclamationManager
var _horde_manager: HordeManager
var _unit_manager: UnitManager
var _territory_controller: TerritoryController

func _ready() -> void:
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
	if resource_manager_path != NodePath():
		_resource_manager = get_node(resource_manager_path)
	if logistics_network_path != NodePath():
		_logistics_network = get_node(logistics_network_path)
	if fog_of_war_manager_path != NodePath():
		_fog_of_war_manager = get_node(fog_of_war_manager_path)
	if tech_manager_path != NodePath():
		_tech_manager = get_node(tech_manager_path)
	if discontent_manager_path != NodePath():
		_discontent_manager = get_node(discontent_manager_path)
	if wall_manager_path != NodePath():
		_wall_manager = get_node(wall_manager_path)
	if reclamation_manager_path != NodePath():
		_reclamation_manager = get_node(reclamation_manager_path)
	if horde_manager_path != NodePath():
		_horde_manager = get_node(horde_manager_path)
	if unit_manager_path != NodePath():
		_unit_manager = get_node(unit_manager_path)
	if territory_controller_path != NodePath():
		_territory_controller = get_node(territory_controller_path)

## Every campaign with at least one save slot on disk, alphabetical. Empty if
## nothing has ever been saved yet.
func get_campaign_names() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(SAVES_ROOT)
	if not dir:
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			result.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result

## Every save slot name (without extension) within `campaign_name`, alphabetical.
func get_slot_names(campaign_name: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(_campaign_dir(campaign_name))
	if not dir:
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".res"):
			result.append(entry.get_basename())
		entry = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result

## Writes the current live game state to `campaign_name`/`slot_name`,
## creating both the campaign folder and the slot file if they don't exist
## yet (a fresh campaign's first save). Returns whether the write succeeded.
func save_game(campaign_name: String, slot_name: String) -> bool:
	var data := _build_save_data(campaign_name, slot_name)
	var dir_path := _campaign_dir(campaign_name)
	var make_dir_err := DirAccess.make_dir_recursive_absolute(dir_path)
	if make_dir_err != OK and make_dir_err != ERR_ALREADY_EXISTS:
		push_warning("SaveLoadManager: could not create campaign folder %s (error %d)." % [dir_path, make_dir_err])
		return false
	var save_err := ResourceSaver.save(data, _slot_path(campaign_name, slot_name))
	if save_err != OK:
		push_warning("SaveLoadManager: failed to save %s/%s (error %d)." % [campaign_name, slot_name, save_err])
		return false
	game_saved.emit(campaign_name, slot_name)
	return true

## Loads `campaign_name`/`slot_name` and restores it into the live game
## state. Returns whether the load succeeded; emits load_failed with a
## human-readable reason otherwise rather than leaving the caller to guess
## from a bare `false`.
func load_game(campaign_name: String, slot_name: String) -> bool:
	var path := _slot_path(campaign_name, slot_name)
	# FileAccess.file_exists(), not ResourceLoader.exists(): the latter checks
	# against the project's res:// import/resource-path cache, which a
	# runtime-written user:// save file was never registered in — it reports
	# false negatives for files that are genuinely there on disk.
	if not FileAccess.file_exists(path):
		load_failed.emit(campaign_name, slot_name, "Save not found.")
		return false
	# CACHE_MODE_IGNORE: always read the file on disk fresh rather than a
	# stale cached copy — this class is exactly the "please definitely load
	# what's on disk right now" caller ResourceLoader's cache exists to opt
	# out for. type_hint deliberately left blank: passing a plain script
	# class name (SaveGameData has no dedicated ResourceFormatLoader of its
	# own) makes ResourceLoader fail to find ANY loader for it at all, rather
	# than falling back to the generic binary-resource loader .res would
	# otherwise resolve to — Godot's type_hint is for disambiguating loaders,
	# not for asserting an expected class.
	var data := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SaveGameData
	if not data:
		load_failed.emit(campaign_name, slot_name, "Save file is corrupt or unreadable.")
		return false
	_apply_save_data(data)
	game_loaded.emit(campaign_name, slot_name)
	return true

func _build_save_data(campaign_name: String, slot_name: String) -> SaveGameData:
	var data := SaveGameData.new()
	data.save_format_version = SAVE_FORMAT_VERSION
	data.campaign_name = campaign_name
	data.slot_name = slot_name
	data.saved_at = Time.get_datetime_string_from_system()

	if _building_manager:
		data.buildings = _building_manager.get_save_entries()
		data.next_building_id = _building_manager.get_next_id()
	if _resource_manager:
		data.resource_stockpile = _resource_manager.get_full_stockpile()
		data.resource_storage_caps = _resource_manager.get_full_storage_caps()
	if _logistics_network:
		data.supply_lines = _logistics_network.get_save_segments()
	if _fog_of_war_manager:
		data.fog_state = _fog_of_war_manager.get_save_state()
	if _tech_manager:
		var tech_state := _tech_manager.get_save_state()
		data.researched_techs.assign(tech_state.researched)
		data.active_tech_id = tech_state.active_tech_id
		data.tech_days_remaining = tech_state.days_remaining
	if _discontent_manager:
		data.discontent_by_hex = _discontent_manager.get_save_state().discontent_by_hex
	if _wall_manager:
		var wall_state := _wall_manager.get_save_state()
		data.wall_segments.assign(wall_state.segments)
		data.next_wall_id = wall_state.next_id
	if _reclamation_manager:
		data.drained_hexes.assign(_reclamation_manager.get_save_state().drained_hexes)
	if _horde_manager:
		var horde_state := _horde_manager.get_save_state()
		data.hordes.assign(horde_state.hordes)
		data.next_horde_id = horde_state.next_id
	if _unit_manager:
		data.units = _unit_manager.get_save_entries()
		data.next_unit_id = _unit_manager.get_next_id()
		data.unit_rally_points = _unit_manager.get_rally_points_save_state()
	if _territory_controller:
		data.lost_territory_hexes.assign(_territory_controller.get_save_state().lost_hexes)

	var tick_state := TickManager.get_save_state()
	data.current_day = tick_state.current_day
	data.elapsed_in_day = tick_state.elapsed_in_day
	data.speed_index = tick_state.speed_index
	return data

## Restoration order matters here even though every manager's recompute() is
## individually idempotent: terrain reclamation FIRST (a hex's
## terrain_feature/biome_type need to already reflect any past draining
## before anything else queries them — see ReclamationManager's own doc
## comment for why this is the one bit of terrain state saved at all), then
## TerritoryController (Phase 5.8 — a hex's District.is_contested state
## needs to already reflect any past territorial loss before LogisticsNetwork
## reads it, same "terrain-like state that doesn't regenerate from the seed"
## reasoning ReclamationManager's own ordering already follows — see that
## class's own doc comment), then buildings (LogisticsNetwork/FogOfWarManager
## both react to building_placed signals and recompute against whatever they
## currently know, including the just-restored territory state), then supply
## lines (so LogisticsNetwork's own recompute sees the full restored
## building set), then DiscontentManager (its region
## flood-fill, Phase 2.11, needs LogisticsNetwork's ZoC coverage already
## recomputed against the restored buildings/supply lines above), then
## WallManager (no dependency on the others, just grouped here), and
## FogOfWarManager LAST — its saved fog_state is authoritative and
## deliberately overrides whatever transient VISIBLE-only recomputes ran
## during the steps before it (see FogOfWarManager.load_save_state()'s own
## doc comment).
func _apply_save_data(data: SaveGameData) -> void:
	if _resource_manager:
		_resource_manager.load_state(data.resource_stockpile, data.resource_storage_caps)
	if _reclamation_manager:
		_reclamation_manager.load_save_state(data.drained_hexes)
	if _territory_controller:
		_territory_controller.load_save_state(data.lost_territory_hexes)
	if _building_manager:
		_building_manager.load_save_entries(data.buildings, data.next_building_id)
	if _logistics_network:
		_logistics_network.load_save_segments(data.supply_lines)
	if _discontent_manager:
		_discontent_manager.load_save_state({"discontent_by_hex": data.discontent_by_hex})
	if _wall_manager:
		_wall_manager.load_save_state(data.wall_segments, data.next_wall_id)
	if _fog_of_war_manager:
		_fog_of_war_manager.load_save_state(data.fog_state)
	if _tech_manager:
		_tech_manager.load_save_state({
			"researched": data.researched_techs,
			"active_tech_id": data.active_tech_id,
			"days_remaining": data.tech_days_remaining,
		})
	if _horde_manager:
		_horde_manager.load_save_state(data.hordes, data.next_horde_id)
	if _unit_manager:
		_unit_manager.load_save_entries(data.units, data.next_unit_id)
		_unit_manager.load_rally_points_save_state(data.unit_rally_points)

	TickManager.load_save_state({
		"current_day": data.current_day,
		"elapsed_in_day": data.elapsed_in_day,
		"speed_index": data.speed_index,
	})

func _campaign_dir(campaign_name: String) -> String:
	return "%s/%s" % [SAVES_ROOT, _sanitize_filename(campaign_name)]

func _slot_path(campaign_name: String, slot_name: String) -> String:
	return "%s/%s.res" % [_campaign_dir(campaign_name), _sanitize_filename(slot_name)]

func _sanitize_filename(raw_name: String) -> String:
	var result := raw_name.strip_edges()
	for bad_char in _UNSAFE_FILENAME_CHARS:
		result = result.replace(bad_char, "_")
	return result
