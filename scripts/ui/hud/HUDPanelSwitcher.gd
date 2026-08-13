class_name HUDPanelSwitcher
extends RefCounted

## Mutual exclusion for MainHUD's four centered toggleable panels
## (SaveLoadView/TechTreeView/DisplayOptionsView/InGameMenuView) — they share
## the same screen position, so opening one closes the other three. No
## manager dependency: coordinates UI nodes MainHUD already owns.

var _save_load_view: SaveLoadView
var _tech_tree_view: TechTreeView
var _display_options_view: DisplayOptionsView
var _in_game_menu_view: InGameMenuView

func _init(save_load_view: SaveLoadView, tech_tree_view: TechTreeView, display_options_view: DisplayOptionsView, in_game_menu_view: InGameMenuView) -> void:
	_save_load_view = save_load_view
	_tech_tree_view = tech_tree_view
	_display_options_view = display_options_view
	_in_game_menu_view = in_game_menu_view

func open_menu() -> void:
	_close_all()
	_in_game_menu_view.open()

func open_save_load() -> void:
	_close_all()
	_save_load_view.open()

func open_tech_tree() -> void:
	_close_all()
	_tech_tree_view.open()

func open_display_options() -> void:
	_close_all()
	_display_options_view.open()

func _close_all() -> void:
	_save_load_view.close()
	_tech_tree_view.close()
	_display_options_view.close()
	_in_game_menu_view.close()
