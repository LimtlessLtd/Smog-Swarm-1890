class_name HUDStyles
extends RefCounted

const PANEL_COLOR: Color = Color("#1f150f")
const PANEL_BORDER: Color = Color("#8b6f44")
const TEXT_COLOR: Color = Color("#f4e7c5")
const MUTED_COLOR: Color = Color("#d7bc80")
const ACCENT_COLOR: Color = Color("#cfa24e")
const BUTTON_NORMAL: Color = Color("#3d2a1d")
const BUTTON_HOVER: Color = Color("#5a3d29")
const BUTTON_PRESSED: Color = Color("#24170f")
const BUTTON_DISABLED: Color = Color("#43372d")
const SHADOW_COLOR: Color = Color("#000000", 0.45)

static func style_label(label: Label, accent: bool = false, muted: bool = false) -> void:
	label.add_theme_color_override("font_color", ACCENT_COLOR if accent else (MUTED_COLOR if muted else TEXT_COLOR))
	label.add_theme_color_override("font_shadow_color", SHADOW_COLOR)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_font_size_override("font_size", 15 if accent else 13)
	label.add_theme_constant_override("line_spacing", 2)

static func style_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = BUTTON_NORMAL
	normal.border_color = PANEL_BORDER
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_right = 8
	normal.corner_radius_bottom_left = 8
	normal.content_margin_left = 8.0
	normal.content_margin_right = 8.0
	normal.content_margin_top = 4.0
	normal.content_margin_bottom = 4.0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = BUTTON_HOVER

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = BUTTON_PRESSED

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = BUTTON_DISABLED
	disabled.border_color = Color("#67553b")

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", Color("#fff2cb"))
	button.add_theme_color_override("font_pressed_color", Color("#f3e1a2"))
	button.add_theme_color_override("font_disabled_color", Color("#b8a27d"))
	button.add_theme_font_size_override("font_size", 13)
	button.custom_minimum_size = Vector2(0, 30)
	# Button's default focus_mode is FOCUS_ALL — clicking ANY button leaves
	# it holding keyboard focus, and Godot's built-in "ui_accept" handling
	# on a focused Button (bound to Enter/Space by default) intercepts a
	# later Space press before it reaches TickManager's own
	# _unhandled_input (a GUI Control consuming an event via accept_event()
	# stops it from propagating to unhandled input at all). No HUD button
	# in this project needs keyboard/gamepad focus navigation — FOCUS_NONE
	# on every button this shared helper styles removes the whole class of
	# "a previously-clicked button silently steals a global keyboard
	# shortcut" bugs (found via: pressing Space while paused "quickly
	# flashes on 5x then flashes back to 0x").
	button.focus_mode = Control.FOCUS_NONE

static func make_panel_stylebox() -> StyleBoxFlat:
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL_COLOR
	panel.border_color = PANEL_BORDER
	panel.border_width_left = 1
	panel.border_width_top = 1
	panel.border_width_right = 1
	panel.border_width_bottom = 1
	panel.corner_radius_top_left = 10
	panel.corner_radius_top_right = 10
	panel.corner_radius_bottom_right = 10
	panel.corner_radius_bottom_left = 10
	panel.shadow_color = Color("#000000", 0.28)
	panel.shadow_size = 4
	panel.content_margin_left = 10.0
	panel.content_margin_right = 10.0
	panel.content_margin_top = 8.0
	panel.content_margin_bottom = 8.0
	return panel

static func style_panel(control: Control) -> void:
	control.add_theme_stylebox_override("panel", make_panel_stylebox())

## Godot's default TabContainer theme is a blue/grey out of place against
## this project's brown/gold Victorian palette — the same reason
## style_button()/style_panel() exist rather than leaving controls at
## engine-default theme.
static func style_tab_container(tabs: TabContainer) -> void:
	var selected := StyleBoxFlat.new()
	selected.bg_color = BUTTON_HOVER
	selected.border_color = ACCENT_COLOR
	selected.border_width_bottom = 2
	selected.content_margin_left = 10.0
	selected.content_margin_right = 10.0
	selected.content_margin_top = 5.0
	selected.content_margin_bottom = 5.0

	var unselected := selected.duplicate() as StyleBoxFlat
	unselected.bg_color = BUTTON_NORMAL
	unselected.border_color = PANEL_BORDER
	unselected.border_width_bottom = 1

	var panel := make_panel_stylebox()
	panel.bg_color = Color(PANEL_COLOR, 0.0)  # The tab content area sits directly on this panel's own already-styled background — no second layer needed, just enough of a stylebox to carry content_margin.
	panel.border_width_left = 0
	panel.border_width_top = 0
	panel.border_width_right = 0
	panel.border_width_bottom = 0

	tabs.add_theme_stylebox_override("tab_selected", selected)
	tabs.add_theme_stylebox_override("tab_unselected", unselected)
	tabs.add_theme_stylebox_override("tab_hovered", unselected)
	tabs.add_theme_stylebox_override("panel", panel)
	tabs.add_theme_color_override("font_selected_color", Color("#fff2cb"))
	tabs.add_theme_color_override("font_unselected_color", MUTED_COLOR)
	tabs.add_theme_color_override("font_hovered_color", TEXT_COLOR)
	tabs.add_theme_font_size_override("font_size", 13)

## Shared clickable "card" shape — icon, name, and a multi-line details
## block, all visible at once without hovering. Originally BuildMenuView-
## only; UnitPanelView's own training/retrain buttons want the identical
## shape (art + cost/upkeep), so it lives here rather than as two
## copy-pasted implementations drifting apart.
##
## Built as a plain PanelContainer with manual gui_input rather than a
## stock Button: a Button's icon has no reliable size-independent-of-
## source-resolution control in this project (see ResourceBarView's own
## TextureRect + EXPAND_IGNORE_SIZE note — the same AI-generated art here
## is authored at non-trivial resolution), so a hand-built card reuses that
## pattern instead of fighting Button.icon for it. `on_pressed` takes no
## arguments — callers .bind() whatever payload they need. `enabled=false`
## (a tier-locked/unaffordable unit) dims the card and swallows clicks
## instead of removing it from the row — the player can still see what a
## locked option costs/does.
##
## `category_colors`: optional {fill, border, hover_fill} override, straight
## from CATEGORY_CARD_COLORS below. Empty (the default — every UnitPanelView
## training/retrain card, no BuildingCategory to key off of) keeps the
## neutral brown look. Only FILL and BORDER carry the category color —
## name/details text stay the existing gold/cream (style_label's own
## colors, already contrast-tuned against a dark background) rather than
## also being recolored per category, so legibility can't regress
## category-by-category; the border (a clear, saturated hue) plus the fill
## (a darker, muted tint of the same family) is what reads as "this
## category's color" — two tones from one accent pair, not a flat block
## that would fight this project's dark Victorian palette.
##
## `name_font_size`/`details_font_size` default to style_label()'s own
## 15/13 (UnitPanelView's training/retrain cards keep looking as before),
## overridable per call site for a denser card — BuildMenuView's own
## bottom-bar cards pass smaller values since a shrunk card_width alone
## would leave normal-size text cramped/wrapping awkwardly.
static func build_card(display_name: String, icon_texture: Texture2D, details: String, on_pressed: Callable, enabled: bool = true, card_width: float = 132.0, icon_size: float = 44.0, category_colors: Dictionary = {}, name_font_size: int = 15, details_font_size: int = 13) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(card_width, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_FORBIDDEN

	var fill: Color = category_colors.get("fill", BUTTON_NORMAL)
	var hover_fill: Color = category_colors.get("hover_fill", BUTTON_HOVER)
	var border: Color = category_colors.get("border", PANEL_BORDER)

	var normal_box := StyleBoxFlat.new()
	normal_box.bg_color = fill if enabled else BUTTON_DISABLED
	normal_box.border_color = border if enabled else Color("#67553b")
	normal_box.border_width_left = 1
	normal_box.border_width_top = 1
	normal_box.border_width_right = 1
	normal_box.border_width_bottom = 1
	normal_box.corner_radius_top_left = 6
	normal_box.corner_radius_top_right = 6
	normal_box.corner_radius_bottom_right = 6
	normal_box.corner_radius_bottom_left = 6
	normal_box.content_margin_left = 6.0
	normal_box.content_margin_right = 6.0
	normal_box.content_margin_top = 6.0
	normal_box.content_margin_bottom = 6.0
	card.add_theme_stylebox_override("panel", normal_box)
	if enabled:
		var hover_box := normal_box.duplicate() as StyleBoxFlat
		hover_box.bg_color = hover_fill
		card.mouse_entered.connect(func() -> void: card.add_theme_stylebox_override("panel", hover_box))
		card.mouse_exited.connect(func() -> void: card.add_theme_stylebox_override("panel", normal_box))
		card.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				on_pressed.call()
		)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	card.add_child(content)

	if icon_texture:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_texture
		icon_rect.custom_minimum_size = Vector2(icon_size, icon_size)
		# Same EXPAND_IGNORE_SIZE/STRETCH_KEEP_ASPECT_CENTERED fix
		# ResourceBarView's own icons need — see that class's doc comment.
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon_rect.modulate = Color(1, 1, 1, 1) if enabled else Color(1, 1, 1, 0.5)
		content.add_child(icon_rect)

	# An autowrap Label with no explicit width to wrap AGAINST reports a
	# degenerate get_minimum_size() in Godot — the narrowest possible width
	# (a single unbreakable word/character) and, at that width, the
	# tallest possible wrapped height (every word on its own line). That
	# propagates up through this card's VBoxContainer -> the parent
	# ScrollContainer -> PanelContainer -> the containing HBoxContainer,
	# and since a Control's size can never be set below its own combined
	# minimum size, the whole containing bar can silently balloon past its
	# intended height, squeezing sibling elements (e.g. the minimap) out
	# of any usable space. `custom_minimum_size.x` pinned to this card's
	# own real content width (card_width minus the panel's 6px left/right
	# content margins) gives autowrap an actual width to wrap against, so
	# its minimum height comes out as "however many real lines this text
	# needs at THIS width" instead of the degenerate one-word-per-line
	# worst case.
	var label_width := card_width - 12.0
	var name_label := Label.new()
	name_label.text = display_name
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.custom_minimum_size.x = label_width
	style_label(name_label, enabled, not enabled)
	name_label.add_theme_font_size_override("font_size", name_font_size)
	content.add_child(name_label)

	var details_label := Label.new()
	details_label.text = details
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	details_label.custom_minimum_size.x = label_width
	style_label(details_label, false, true)
	details_label.add_theme_font_size_override("font_size", details_font_size)
	content.add_child(details_label)

	return card

## Muted-fill + saturated-border color pairs, one per BuildMenuView column
## — keyed by a plain string (not GameEnums.BuildingCategory directly)
## since "Defense Works & Walls combined" isn't a single enum value:
## DEFENSE_WORKS (BuildingCatalog) and the Walls column (WallCatalog, a
## separate placement flow) never shared a category to key off of before
## being asked to merge their COLUMN, not their underlying data model.
## Fill colors stay dark (similar luminance to the neutral BUTTON_NORMAL)
## so style_label's already-tuned gold/cream text keeps full contrast
## regardless of category; border colors are the actual "this is category
## X" signal, bright/saturated enough to read clearly against this
## project's dark brown HUD without turning neon.
static func category_card_colors(key: String) -> Dictionary:
	match key:
		"housing_civil":  # Blue & purple.
			return {"fill": Color(0.16, 0.17, 0.27), "hover_fill": Color(0.22, 0.23, 0.35), "border": Color(0.58, 0.50, 0.85)}
		"industry_extraction":  # White & black.
			return {"fill": Color(0.14, 0.14, 0.15), "hover_fill": Color(0.20, 0.20, 0.22), "border": Color(0.82, 0.82, 0.85)}
		"agriculture":  # Green & brown.
			return {"fill": Color(0.17, 0.15, 0.10), "hover_fill": Color(0.24, 0.21, 0.15), "border": Color(0.48, 0.68, 0.36)}
		"defense_walls":  # Red & white — Defense Works + Walls, combined into one column.
			return {"fill": Color(0.23, 0.12, 0.11), "hover_fill": Color(0.32, 0.17, 0.16), "border": Color(0.88, 0.85, 0.82)}
		"infrastructure":  # Ochre & grey — Road/Railway/Canal/Bridge (Infrastructure rework, todo.md).
			return {"fill": Color(0.20, 0.17, 0.10), "hover_fill": Color(0.28, 0.24, 0.15), "border": Color(0.78, 0.66, 0.38)}
		_:
			return {}

## Shared cost/upkeep formatter (BuildMenuView's own cards and
## UnitPanelView's training/retrain cards all price things the same "N
## Resource, M Resource" way) — trims a whole-number float down to a clean
## integer-looking string ("40" not "40.0") while still showing real
## precision for a genuinely fractional value, same reasoning
## UnitPanelView's own _format_upkeep() applies to building upkeep display.
static func format_resource_dict(costs: Dictionary) -> String:
	var text := ""
	var first := true
	for resource_type in costs:
		if not first:
			text += ", "
		text += "%s %s" % [String.num(float(costs[resource_type]), 1).rstrip("0").rstrip("."), ResourceVisuals.display_name(resource_type)]
		first = false
	return text
