class_name SaveLoadManager
extends Node

## Aggregates state out of BuildingManager / ResourceManager /
## LogisticsNetwork / FogOfWarManager / TechManager / DiscontentManager /
## WallManager / ReclamationManager / HordeManager / UnitManager /
## TerritoryController / SettlementFoundingController / InfestationManager /
## TickManager into a single SaveGameData Resource and back again. Wired as a
## Main.tscn sibling via exported NodePaths, same pattern as
## LogisticsNetwork/FogOfWarManager — it owns none of that state, only reads
## and restores it.
##
## CLAUDE.md §1 says to extract a narrower collaborator rather than widen a
## class past roughly eight dependencies, and this one now holds thirteen
## NodePaths. Stated rather than silently ignored: aggregating every manager
## IS this class's single responsibility, so a "narrower collaborator" would be
## a second aggregator with the same shape and one more indirection between a
## manager and its own saved field. The rule's target is a class that grew a
## second job; this class only ever had the one.
##
## Saves are grouped by a player-named Campaign, with multiple manual save
## slots per campaign and multiple independent campaigns coexisting on
## disk.
##
## Exactly one campaign is ACTIVE per play session — "when you create a
## campaign, you choose the name of the campaign at that point. then when
## you save games, they are all saved under that campaign that you are
## playing" (user request). The name arrives from the boot screen via
## GameLaunchState and is applied by Main.gd; save_game()/load_game()
## therefore take a slot only, and cannot write into or read out of a
## campaign the player is not currently in. Listing IS campaign-explicit
## (get_campaign_names()/get_slot_names()), because the boot screen's own
## browser has to show campaigns it is not in yet.
##
## Each save writes a sibling `<slot>.png` screenshot next to `<slot>.res`
## — a separate file rather than a field on SaveGameData so a browser can
## show every slot's thumbnail without deserializing whole game states to
## get at them.
##
## No elapsed-time/catch-up math: closing the game pauses everything
## exactly where it was, and loading resumes there, nothing more —
## BackgroundExecutionManager's own background-simulation handling only
## covers DURING a play session, not while the application is closed.

signal game_saved(slot_name: String)
signal game_loaded(slot_name: String)
signal load_failed(slot_name: String, reason: String)

const SAVE_FORMAT_VERSION: int = 1
const SAVES_ROOT: String = "user://saves"

## Used when nothing set an active campaign — Main.tscn run directly (a
## headless test, or F5 on it in the editor) rather than reached through
## MainMenu.tscn's New Game/Continue. Saving still works and lands
## somewhere findable instead of failing on an empty folder name.
const DEFAULT_CAMPAIGN_NAME: String = "Untitled Campaign"

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
@export var infestation_manager_path: NodePath
@export var wall_manager_path: NodePath
@export var reclamation_manager_path: NodePath
@export var horde_manager_path: NodePath
@export var unit_manager_path: NodePath
@export var territory_controller_path: NodePath
@export var settlement_founding_controller_path: NodePath  ## Optional — re-derives founded settlements from the restored buildings. Unset means a loaded save's founded hexes revert to their map-gen terrain.

var _settlement_founding_controller: SettlementFoundingController
var _building_manager: BuildingManager
var _resource_manager: ResourceManager
var _logistics_network: LogisticsNetwork
var _fog_of_war_manager: FogOfWarManager
var _tech_manager: TechManager
var _discontent_manager: DiscontentManager
var _infestation_manager: InfestationManager
var _wall_manager: WallManager
var _reclamation_manager: ReclamationManager
var _horde_manager: HordeManager
var _unit_manager: UnitManager
var _territory_controller: TerritoryController
var _active_campaign: String = DEFAULT_CAMPAIGN_NAME

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
	if infestation_manager_path != NodePath():
		_infestation_manager = get_node(infestation_manager_path)
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
	if settlement_founding_controller_path != NodePath():
		_settlement_founding_controller = get_node(settlement_founding_controller_path)

## Which campaign this session's saves belong to. Set once, by Main.gd, from
## whatever the boot screen recorded on GameLaunchState.
##
## Stored already sanitized rather than raw: the name is BOTH the folder on
## disk and the label the Save/Load screen shows, and sanitizing only on the
## way to the filesystem would make a campaign called "Manchester: 1890"
## display under one name in-game and a different one ("Manchester_ 1890")
## in the boot screen's browser, which lists real directory names.
func set_active_campaign(campaign_name: String) -> void:
	var clean := _sanitize_filename(campaign_name)
	_active_campaign = DEFAULT_CAMPAIGN_NAME if clean.is_empty() else clean

func get_active_campaign() -> String:
	return _active_campaign

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

## Modification time (Unix seconds) of a slot's save file, 0 if it has none.
## What a save browser sorts and dates entries by — reading `saved_at` off
## SaveGameData instead would mean deserializing every full game state on
## disk just to draw a list.
func get_slot_modified_time(campaign_name: String, slot_name: String) -> int:
	var path := _slot_path(campaign_name, slot_name)
	if not FileAccess.file_exists(path):
		return 0
	return int(FileAccess.get_modified_time(path))

## The most recently written slot in `campaign_name`, "" if it has none.
func get_latest_slot_name(campaign_name: String) -> String:
	var latest := ""
	var latest_time := -1
	for slot_name in get_slot_names(campaign_name):
		var modified := get_slot_modified_time(campaign_name, slot_name)
		if modified > latest_time:
			latest_time = modified
			latest = slot_name
	return latest

## A slot's saved screenshot, or null when it has none — every save written
## before screenshots existed, and any whose capture failed. Callers must
## handle null rather than assume a thumbnail is always there.
##
## Image.load() rather than ResourceLoader, same reason RealTerrainSampler
## and ReliefTileView read their own runtime PNGs that way: these are files
## written at runtime under user://, which the res:// import pipeline knows
## nothing about and ResourceLoader reports as missing.
func get_slot_thumbnail(campaign_name: String, slot_name: String) -> Texture2D:
	var path := _thumbnail_path(campaign_name, slot_name)
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)

## The image that represents a whole campaign in a campaign browser: its
## most recent save's screenshot, so the picture shown is the furthest the
## player has actually got. Null if the campaign has no thumbnails at all.
func get_campaign_thumbnail(campaign_name: String) -> Texture2D:
	var latest := get_latest_slot_name(campaign_name)
	if latest.is_empty():
		return null
	return get_slot_thumbnail(campaign_name, latest)

## Writes the current live game state to the active campaign's `slot_name`,
## creating both the campaign folder and the slot file if they don't exist
## yet (a fresh campaign's first save). Returns whether the write succeeded.
##
## `thumbnail` is the screenshot to show for this slot in a save browser;
## null skips it. A thumbnail that fails to write is NOT a failed save —
## the game state is what matters and it is already on disk by then, so the
## write below only warns.
func save_game(slot_name: String, thumbnail: Image = null) -> bool:
	var data := _build_save_data(_active_campaign, slot_name)
	var dir_path := _campaign_dir(_active_campaign)
	var make_dir_err := DirAccess.make_dir_recursive_absolute(dir_path)
	if make_dir_err != OK and make_dir_err != ERR_ALREADY_EXISTS:
		push_warning("SaveLoadManager: could not create campaign folder %s (error %d)." % [dir_path, make_dir_err])
		return false
	var save_err := ResourceSaver.save(data, _slot_path(_active_campaign, slot_name))
	if save_err != OK:
		push_warning("SaveLoadManager: failed to save %s/%s (error %d)." % [_active_campaign, slot_name, save_err])
		return false
	if thumbnail != null:
		var png_err := thumbnail.save_png(_thumbnail_path(_active_campaign, slot_name))
		if png_err != OK:
			push_warning("SaveLoadManager: saved %s/%s but its screenshot failed (error %d)." % [_active_campaign, slot_name, png_err])
	game_saved.emit(slot_name)
	return true

## Loads `slot_name` from the active campaign and restores it into the live
## game state. Returns whether the load succeeded; emits load_failed with a
## human-readable reason otherwise rather than leaving the caller to guess
## from a bare `false`.
##
## Loading ACROSS campaigns is deliberately not possible here: the boot
## screen's browser picks a campaign, records it plus a slot on
## GameLaunchState, and Main.gd sets the active campaign before calling
## this — so an in-game load can only ever reach the campaign being played.
func load_game(slot_name: String) -> bool:
	var path := _slot_path(_active_campaign, slot_name)
	# FileAccess.file_exists(), not ResourceLoader.exists(): the latter checks
	# against the project's res:// import/resource-path cache, which a
	# runtime-written user:// save file was never registered in — it reports
	# false negatives for files that are genuinely there on disk.
	if not FileAccess.file_exists(path):
		load_failed.emit(slot_name, "Save not found.")
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
		load_failed.emit(slot_name, "Save file is corrupt or unreadable.")
		return false
	_apply_save_data(data)
	game_loaded.emit(slot_name)
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
	if _infestation_manager:
		data.resident_zombies_by_hex = _infestation_manager.get_save_state().resident_by_hex
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

## Restoration order matters here even though every manager's recompute()
## is individually idempotent: terrain reclamation FIRST (a hex's
## terrain_feature/biome_type must already reflect any past draining before
## anything else queries them — see ReclamationManager's own doc comment),
## then TerritoryController (a hex's District.is_contested state must
## already reflect any past territorial loss before LogisticsNetwork reads
## it), then buildings (LogisticsNetwork/FogOfWarManager both react to
## building_placed signals and recompute against whatever they currently
## know, including the just-restored territory state), then supply lines
## (so LogisticsNetwork's own recompute sees the full restored building
## set), then DiscontentManager (its region flood-fill needs
## LogisticsNetwork's ZoC coverage already recomputed against the restored
## buildings/supply lines above), then WallManager (no dependency on the
## others), then units (units are a fog vision source too, so
## load_save_entries()'s per-unit unit_trained emit must land BEFORE the
## authoritative fog load for the same reason buildings do), and
## FogOfWarManager LAST — its saved fog_state is authoritative and
## deliberately overrides whatever transient VISIBLE-only recomputes ran
## during the steps before it (see FogOfWarManager.load_save_state()'s own
## doc comment). Sequencing units before fog also matters because
## TickManager.load_save_state() (below, restores the saved day/night
## clock) runs even later — any recompute triggered before it reads
## whatever day/night phase was live before the load, not the save's own;
## harmless for a step whose transient recompute gets overridden by fog's
## authoritative load right after it, but would be a real bug for units
## specifically if they were sequenced after fog instead.
func _apply_save_data(data: SaveGameData) -> void:
	if _resource_manager:
		_resource_manager.load_state(data.resource_stockpile, data.resource_storage_caps)
	if _reclamation_manager:
		_reclamation_manager.load_save_state(data.drained_hexes)
	if _territory_controller:
		_territory_controller.load_save_state(data.lost_territory_hexes)
	if _building_manager:
		_building_manager.load_save_entries(data.buildings, data.next_building_id)
	# Immediately after buildings, and before anything that reads terrain
	# back: founding carries no save entry of its own — which hexes are
	# founded, and how far each has paved, is re-derived wholesale from the
	# Town Halls and populations load_save_entries() just restored (see
	# SettlementFoundingController's own doc comment). Sequenced here so
	# LogisticsNetwork's ZoC recompute below already sees the restored
	# is_settlement/biome_type rather than the pristine map-gen values a
	# fresh boot regenerated.
	if _settlement_founding_controller:
		_settlement_founding_controller.rebuild_from_buildings()
	if _logistics_network:
		_logistics_network.load_save_segments(data.supply_lines)
	if _discontent_manager:
		_discontent_manager.load_save_state({"discontent_by_hex": data.discontent_by_hex})
	# No ordering dependency in either direction, stated so nobody has to
	# re-derive it: InfestationManager's stored half is a plain per-hex
	# Dictionary that reads nothing during a restore, and the roaming half it
	# adds on top is read live from HordeManager whenever it is asked.
	if _infestation_manager:
		_infestation_manager.load_save_state({"resident_by_hex": data.resident_zombies_by_hex})
	if _wall_manager:
		_wall_manager.load_save_state(data.wall_segments, data.next_wall_id)
	if _unit_manager:
		_unit_manager.load_save_entries(data.units, data.next_unit_id)
		_unit_manager.load_rally_points_save_state(data.unit_rally_points)
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

	TickManager.load_save_state({
		"current_day": data.current_day,
		"elapsed_in_day": data.elapsed_in_day,
		"speed_index": data.speed_index,
	})

func _campaign_dir(campaign_name: String) -> String:
	return "%s/%s" % [SAVES_ROOT, _sanitize_filename(campaign_name)]

func _slot_path(campaign_name: String, slot_name: String) -> String:
	return "%s/%s.res" % [_campaign_dir(campaign_name), _sanitize_filename(slot_name)]

## Sibling of _slot_path() with a .png extension — get_slot_names() only
## collects ".res" entries, so a thumbnail sharing its slot's basename can't
## be mistaken for a save slot of its own.
func _thumbnail_path(campaign_name: String, slot_name: String) -> String:
	return "%s/%s.png" % [_campaign_dir(campaign_name), _sanitize_filename(slot_name)]

func _sanitize_filename(raw_name: String) -> String:
	var result := raw_name.strip_edges()
	for bad_char in _UNSAFE_FILENAME_CHARS:
		result = result.replace(bad_char, "_")
	return result
