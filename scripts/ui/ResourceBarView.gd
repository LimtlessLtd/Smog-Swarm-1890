class_name ResourceBarView
extends PanelContainer

## Top HUD strip: one entry per GameEnums.ResourceType, live-updated off
## ResourceManager.resources_changed. Deliberately dumb — it only formats
## whatever ResourceManager/BuildingManager report, no economy logic of
## its own. Built entirely in code rather than scene-authored, matching
## HexCellView/StrategicOverlayManager's "code-drawn placeholder" convention.
##
## Icon-only, dark background — "remove the names of the items and keep
## the icons... make the resource bar have a dark background" (user
## feedback): the per-resource Label used to read "Food: 42/100" — the
## "Food:" name prefix is gone (the icon carries that now). A hover tooltip
## (Control.tooltip_text, Godot's own built-in mechanism) fills the gap left
## by the removed name and adds today's projected income and expenditure,
## straight off BuildingManager.get_projected_daily_flow() so the tooltip
## can never drift from what the next day_completed tick will actually bank.
##
## Amount only, no "/cap" — "remove the slash infinity symbol from the
## resources top bar for all the resources please, just show the 1 number"
## (user feedback): the storage cap (often literally "∞" for uncapped
## resources) is gone from the label entirely, not moved into the tooltip —
## the per-resource tooltip content is otherwise untouched.
##
## Grouped into three sections — Pooled / Extracted / Processed
## (ResourceVisuals.display_groups(), design_doc.md §2's own Capacity &
## Yield / Raw / Processed split) — per user feedback ("split the resources
## into grouped sections that describe how each section works"). Kept to
## ONE line (not a 2-line header+icons stack) so this view's height stays
## exactly what MainHUD's fixed top-row grid already allocates it: each
## group gets a small accent-colored name Label ahead of its own icon row,
## with the "how it works" description living in THAT label's own tooltip
## (same Control.tooltip_text mechanism the per-resource entries already
## use) rather than a second visible line.
##
## Dark background: extends HBoxContainer used to not draw a background at
## all — HUDStyles.style_panel() sets a "panel" theme stylebox override,
## but only Panel/PanelContainer (and similar) actually draw one; plain
## Container subclasses like HBoxContainer silently ignore it. Switching
## the root to PanelContainer (with the resource entries in an inner
## HBoxContainer — PanelContainer itself only manages ONE child's margins,
## not a row layout) is what actually renders HUDStyles.PANEL_COLOR.

const ICON_SIZE: int = 20  ## Small enough to sit comfortably inline with a Label at this bar's own font size, matching HUDStyles' existing text scale.

var _resource_manager: ResourceManager
var _building_manager: BuildingManager
var _entries: Dictionary = {}  # GameEnums.ResourceType -> Control (tooltip owner)
var _labels: Dictionary = {}  # GameEnums.ResourceType -> Label

func _ready() -> void:
	HUDStyles.style_panel(self)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)

	var groups := ResourceVisuals.display_groups()
	for i in range(groups.size()):
		var group: Dictionary = groups[i]

		var group_label := Label.new()
		group_label.text = group["name"]
		group_label.tooltip_text = group["description"]  ## "describe how each section works" (user feedback) — lives here rather than a second visible line, keeping this bar one line tall (see class doc comment).
		group_label.mouse_filter = Control.MOUSE_FILTER_STOP
		HUDStyles.style_label(group_label, true)
		group_label.add_theme_font_size_override("font_size", 11)
		row.add_child(group_label)

		for resource_type in group["types"]:
			row.add_child(_build_resource_entry(resource_type))

		if i < groups.size() - 1:
			row.add_child(VSeparator.new())

func _build_resource_entry(resource_type: GameEnums.ResourceType) -> Control:
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 4)
	entry.mouse_filter = Control.MOUSE_FILTER_STOP  ## Own tooltip target — PASS (the container default) would let hover fall through to whatever's behind this bar instead of showing it.
	var icon_texture := ResourceVisuals.icon(resource_type)
	if icon_texture:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_texture
		icon_rect.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		# The AI-generated icons (assets/icons/README.md) are authored at
		# 2048x2048. TextureRect's default expand_mode (EXPAND_KEEP_SIZE) makes
		# get_minimum_size() return the *texture's* native size, which wins
		# over custom_minimum_size above (the effective minimum is the max of
		# the two) — without this, each icon forces its whole HBoxContainer,
		# and the HUD around it, out to full source resolution.
		# EXPAND_IGNORE_SIZE lets custom_minimum_size actually be the size,
		# with STRETCH_KEEP_ASPECT_CENTERED scaling the texture down to fit it.
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  ## The parent `entry` owns the tooltip/hover, not this child.
		entry.add_child(icon_rect)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HUDStyles.style_label(label)
	entry.add_child(label)
	_entries[resource_type] = entry
	_labels[resource_type] = label
	return entry

## Called by MainHUD once it has resolved its ResourceManager/BuildingManager
## NodePaths — this view has no NodePath of its own since MainHUD builds it
## in code, not via a scene with pre-wired exports. `building_manager` is
## optional — without it, the tooltip still shows the resource's name,
## just no income/expenditure lines.
func setup(resource_manager: ResourceManager, building_manager: BuildingManager = null) -> void:
	_resource_manager = resource_manager
	_building_manager = building_manager
	_resource_manager.resources_changed.connect(_on_resources_changed)
	_on_resources_changed(_resource_manager.get_full_stockpile())

func _on_resources_changed(stockpile: Dictionary) -> void:
	for resource_type in _labels:
		var amount: float = stockpile.get(resource_type, 0.0)
		_labels[resource_type].text = str(int(amount))
		_entries[resource_type].tooltip_text = _build_tooltip(resource_type)

## "The name of the resource, total daily income and total daily
## expenditure" (user feedback) — income/expenditure read straight off
## BuildingManager.get_projected_daily_flow()'s live preview, so this can't
## drift from what the next day_completed tick will actually bank. A
## resource with neither income nor expenditure today still gets a
## tooltip (just the name) rather than an empty one.
func _build_tooltip(resource_type: GameEnums.ResourceType) -> String:
	var text := ResourceVisuals.display_name(resource_type)
	if not _building_manager:
		return text
	var flow := _building_manager.get_projected_daily_flow()
	var income: float = (flow["produced"] as Dictionary).get(resource_type, 0.0)
	var expenditure: float = (flow["consumed"] as Dictionary).get(resource_type, 0.0)
	text += "\nIncome: %s/day" % String.num(income, 1)
	text += "\nExpenditure: %s/day" % String.num(expenditure, 1)
	return text
