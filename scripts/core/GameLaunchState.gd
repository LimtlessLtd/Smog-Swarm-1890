extends Node

## Tiny cross-scene handoff (playtest round 6, "There should be a Main
## Menu that has all the save/load functionality on it") — MainMenuView's
## boot screen lives in its own scene (MainMenu.tscn, now the project's
## `run/main_scene`) with no live gameplay systems to load INTO yet, so
## "Continue"/"Load" there can't call SaveLoadManager.load_game() directly
## the way the in-game menu's own Save/Load screen does. Instead it records
## which campaign/slot the player picked here, changes scene to
## Main.tscn, and Main.gd's own `_ready()` (guaranteed to run after every
## sibling manager's `_ready()` — see that script's existing camera-recenter
## logic for why that ordering matters) consumes it and performs the real
## load once every manager SaveLoadManager needs actually exists.
##
## Autoload (project.godot), same "tiny piece of state nothing else already
## owns" role DisplaySettings already plays — this is genuinely
## cross-scene session state (which save to load next), not something
## either scene's own root node could hold across a scene change.

var _pending_campaign: String = ""
var _pending_slot: String = ""

func request_load(campaign_name: String, slot_name: String) -> void:
	_pending_campaign = campaign_name
	_pending_slot = slot_name

func has_pending_load() -> bool:
	return not _pending_campaign.is_empty() and not _pending_slot.is_empty()

## Returns {"campaign": String, "slot": String} and clears the pending
## request — a load request is consumed exactly once, same "read it, then
## it's gone" contract a one-shot signal would have, just surviving a scene
## change in between.
func consume_pending_load() -> Dictionary:
	var result := {"campaign": _pending_campaign, "slot": _pending_slot}
	_pending_campaign = ""
	_pending_slot = ""
	return result
