extends Node

## Tiny cross-scene handoff. "There should be a Main Menu that has all the
## save/load functionality on it" (user request) — MainMenuView's boot
## screen lives in its own scene (MainMenu.tscn, the project's
## `run/main_scene`) with no live gameplay systems to load into yet, so
## "Continue"/"Load" there can't call SaveLoadManager.load_game() directly
## the way the in-game menu's own Save/Load screen does. Instead it
## records which campaign (and, for a load, which slot) the player picked
## here, changes scene to Main.tscn, and Main.gd's own `_ready()`
## (guaranteed to run after every sibling manager's `_ready()` — see that
## script's existing camera-recenter logic for why that ordering matters)
## consumes it and applies it once every manager SaveLoadManager needs
## actually exists.
##
## Carries BOTH launch paths, not just Load: "when you create a campaign,
## you choose the name of the campaign at that point" (user request), so
## New Game names a campaign on the boot screen and that name has to reach
## Main.tscn too. A New Game request is a campaign with no slot; a Load
## request is a campaign with one.
##
## Autoload (project.godot), same "tiny piece of state nothing else already
## owns" role DisplaySettings already plays — this is genuinely
## cross-scene session state, not something either scene's own root node
## could hold across a scene change.

var _pending_campaign: String = ""
var _pending_slot: String = ""
## Survives consume_pending_launch() on purpose: BuildingManager reads the start
## override in its own _ready(), and VerticalSliceDirector checks the mode in its
## _ready(), both of which run before Main.gd consumes the request. Cleared by the
## next request of either kind.
var _vertical_slice: bool = false

const VERTICAL_SLICE_CAMPAIGN_NAME: String = "Vertical Slice"

## The vertical slice (VerticalSliceConfig): a fresh map from the slice's own start
## hex, filed under its own campaign name so its saves never mix with a real one.
func request_vertical_slice() -> void:
	_pending_campaign = VERTICAL_SLICE_CAMPAIGN_NAME
	_pending_slot = ""
	_vertical_slice = true

func is_vertical_slice() -> bool:
	return _vertical_slice

## The hex BuildingManager seeds the starting settlement on, or null for the
## campaign's own choice.
func get_starting_hex_override() -> Variant:
	return VerticalSliceConfig.START_HEX if _vertical_slice else null

## New Game: play `campaign_name` from a fresh map. No slot — nothing has
## been saved into it yet (the campaign folder appears on its first save).
func request_new_campaign(campaign_name: String) -> void:
	_pending_campaign = campaign_name
	_pending_slot = ""
	_vertical_slice = false

## Continue: play `campaign_name`, restoring `slot_name` into it.
func request_load(campaign_name: String, slot_name: String) -> void:
	_pending_campaign = campaign_name
	_pending_slot = slot_name
	_vertical_slice = false

func has_pending_launch() -> bool:
	return not _pending_campaign.is_empty()

## Returns {"campaign": String, "slot": String} and clears the pending
## request — consumed exactly once, same "read it, then it's gone" contract
## a one-shot signal would have, just surviving a scene change in between.
## An empty "slot" means New Game.
func consume_pending_launch() -> Dictionary:
	var result := {"campaign": _pending_campaign, "slot": _pending_slot}
	_pending_campaign = ""
	_pending_slot = ""
	return result
