class_name ResourceBarView
extends HBoxContainer

## Top HUD strip (design doc Phase 6.1): one Label per GameEnums.ResourceType,
## live-updated off ResourceManager.resources_changed. Deliberately dumb — it
## only formats whatever ResourceManager reports (amount/cap), no economy
## logic of its own. Built entirely in code rather than scene-authored,
## matching HexCellView/StrategicOverlayManager's "code-drawn placeholder"
## convention.

## Icon pixel size — small enough to sit comfortably inline with a Label at
## this bar's own font size, matching HUDStyles' existing text scale rather
## than a hand-picked number disconnected from it.
const ICON_SIZE: int = 20

var _resource_manager: ResourceManager
var _labels: Dictionary = {}  # GameEnums.ResourceType -> Label

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	HUDStyles.style_panel(self)
	for resource_type in ResourceVisuals.display_order():
		# User request, this pass: a real icon (assets/icons/README.md) next
		# to each resource's text where one exists yet — an inner HBoxContainer
		# per resource so the icon (TextureRect, only added when
		# ResourceVisuals.icon() returns non-null) and Label sit side by side.
		# No icon authored yet just means today's exact text-only look, same
		# "art lands incrementally" contract every other *Visuals.gd here
		# already follows.
		var entry := HBoxContainer.new()
		entry.add_theme_constant_override("separation", 4)
		var icon_texture := ResourceVisuals.icon(resource_type)
		if icon_texture:
			var icon_rect := TextureRect.new()
			icon_rect.texture = icon_texture
			icon_rect.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			entry.add_child(icon_rect)
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		HUDStyles.style_label(label)
		entry.add_child(label)
		add_child(entry)
		_labels[resource_type] = label

## Called by MainHUD once it has resolved its ResourceManager NodePath — this
## view has no NodePath of its own since MainHUD builds it in code, not via
## a scene with pre-wired exports.
func setup(resource_manager: ResourceManager) -> void:
	_resource_manager = resource_manager
	_resource_manager.resources_changed.connect(_on_resources_changed)
	_on_resources_changed(_resource_manager.get_full_stockpile())

func _on_resources_changed(stockpile: Dictionary) -> void:
	for resource_type in _labels:
		var amount: float = stockpile.get(resource_type, 0.0)
		var cap := _resource_manager.get_storage_cap(resource_type)
		var cap_text := "∞" if is_inf(cap) else str(int(cap))
		_labels[resource_type].text = "%s: %d/%s" % [ResourceVisuals.display_name(resource_type), int(amount), cap_text]
