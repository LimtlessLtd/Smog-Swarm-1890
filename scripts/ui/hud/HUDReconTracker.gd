class_name HUDReconTracker
extends RefCounted

## Reconnaissance countdown label: the soonest-arriving currently-observed
## ATTRACTED horde's ETA, refreshed once a second. Not gated on
## StrategicOverlayManager.HORDE_MARKER_MIN_SIZE (the Strategic-marker size
## threshold) — early warning is exactly the case where a smaller,
## not-yet-marker-worthy horde still matters. "Observed" means Fog of War
## VISIBLE, reusing existing vision sources rather than a dedicated
## observation-post mechanic.

const REFRESH_SECONDS := 1.0  ## Matches TimeControlsView's own refresh cadence.

var _label: Label
var _horde_manager: HordeManager
var _fog_of_war_manager: FogOfWarManager

## `host` owns the created Timer (RefCounted can't add_child) — MainHUD itself.
func _init(host: CanvasLayer, label: Label, horde_manager: HordeManager, fog_of_war_manager: FogOfWarManager) -> void:
	_label = label
	_horde_manager = horde_manager
	_fog_of_war_manager = fog_of_war_manager
	var timer := Timer.new()
	timer.wait_time = REFRESH_SECONDS
	timer.autostart = true
	host.add_child(timer)
	timer.timeout.connect(refresh)
	refresh()

func refresh() -> void:
	if not _horde_manager or not _fog_of_war_manager:
		_label.text = ""
		return
	var best_eta := INF
	var best_horde: Horde = null
	for horde in _horde_manager.get_all_hordes():
		if horde.state != GameEnums.HordeState.ATTRACTED:
			continue
		if not _fog_of_war_manager.is_visible(horde.hex_coord):
			continue
		var eta := _horde_manager.get_eta_seconds(horde)
		if eta < best_eta:
			best_eta = eta
			best_horde = horde
	if not best_horde:
		_label.text = ""
		return
	_label.text = "⚠ Horde approaching (%d) — ETA %s" % [best_horde.size, _format_eta(best_eta)]

func _format_eta(seconds: float) -> String:
	var total := int(roundf(seconds))
	return "%02d:%02d" % [total / 60, total % 60]
