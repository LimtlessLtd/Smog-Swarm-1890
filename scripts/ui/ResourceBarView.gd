class_name ResourceBarView
extends HBoxContainer

## Top HUD strip (design doc Phase 6.1): one Label per GameEnums.ResourceType,
## live-updated off ResourceManager.resources_changed. Deliberately dumb — it
## only formats whatever ResourceManager reports (amount/cap), no economy
## logic of its own. Built entirely in code rather than scene-authored,
## matching HexCellView/StrategicOverlayManager's "code-drawn placeholder"
## convention.

var _resource_manager: ResourceManager
var _labels: Dictionary = {}  # GameEnums.ResourceType -> Label

func _ready() -> void:
	add_theme_constant_override("separation", 24)
	for resource_type in ResourceVisuals.display_order():
		var label := Label.new()
		add_child(label)
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
