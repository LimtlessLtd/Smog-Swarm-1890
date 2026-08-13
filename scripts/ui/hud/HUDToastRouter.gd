class_name HUDToastRouter
extends RefCounted

## Toast mechanics: a dark-backed panel, auto-hides after TOAST_SECONDS.
## Every other HUD collaborator calls show() instead of touching
## Label/Timer/Panel visibility directly.

const TOAST_SECONDS := 3.0

var _panel: PanelContainer
var _label: Label
var _timer: Timer

## `host` owns the created Panel/Timer nodes (RefCounted can't add_child) —
## MainHUD itself. `place` positions the panel via MainHUD's own layout
## helper — layout stays MainHUD's job, this class only owns toast state.
func _init(host: CanvasLayer, place: Callable) -> void:
	_panel = PanelContainer.new()
	_panel.name = "ToastPanel"
	host.add_child(_panel)
	place.call(_panel)
	HUDStyles.style_panel(_panel)
	_panel.visible = false

	_label = Label.new()
	_label.name = "ToastLabel"
	_panel.add_child(_label)
	HUDStyles.style_label(_label, true)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = TOAST_SECONDS
	host.add_child(_timer)
	_timer.timeout.connect(_on_timeout)

func show(text: String) -> void:
	_label.text = text
	_panel.visible = true
	_timer.start()

func _on_timeout() -> void:
	_label.text = ""
	_panel.visible = false
