extends Node

## Global, cross-cutting UI display-layer toggles (user request: "add
## options so we can enable and disable the overlays"). An autoload rather
## than a Main.tscn sibling wired via NodePath — its consumers span totally
## unrelated scene-tree branches (`StrategicOverlayManager` under
## `WorldRoot`, `MinimapView`/`DisplayOptionsView` under `MainHUD`) that
## share no closer common ancestor than `Main` itself, and every toggle
## needs to reach all of them without threading a NodePath through
## intermediate nodes that have no other reason to know about display
## preferences. Same "cross-cutting singleton" role `TickManager`/
## `TimeCycleManager` already play for simulation state, just for UI state
## instead.
##
## Deliberately NOT part of `SaveGameData` (Phase 2.8) — a display
## preference (do I want to see wall markers right now?) is a client-side
## viewing choice, not campaign state, same reasoning `CameraController`'s
## own zoom/pan position was never saved either.
##
## Reflection-based `set_flag()`/`get_flag()` (GDScript's built-in
## `Object.set()`/`get()` by property name) rather than one hand-written
## setter per flag: every flag here is identical in shape (a bool, toggled
## by a `DisplayOptionsView` checkbox, read by exactly one consumer) with
## nothing per-flag to differentiate — a setter per flag would be eight
## copies of the same three lines. `DisplayOptionsView` iterates a plain
## list of (label, property_name) pairs rather than needing eight
## hand-wired signal connections.

signal changed

## Consulted by `StrategicOverlayManager` — the Strategic hex-tile world
## view's own marker layers (Phase 2.7's building/frontier/wall/unit/horde
## markers, under-attack alerts) plus the new Threat Meter drawn there.
var show_building_markers: bool = true
var show_frontier_markers: bool = true
var show_wall_markers: bool = true
var show_unit_markers: bool = true
var show_horde_markers: bool = true
var show_attack_alerts: bool = true
var show_threat_meter_world: bool = true
## Zone of Control (Phase 2.3), visualized for the first time this pass —
## consulted by `StrategicOverlayManager`'s own ZoC layer.
var show_zoc_world: bool = true

## Consulted by `MinimapView` — the Threat Meter's OTHER surface (Phase
## 6.1's own "hex overview map" reading), independent of the world-view
## flag above so either can be toggled without the other.
var show_threat_meter_minimap: bool = true
## Consulted by `TacticalHexView` — Zone of Control's OTHER surface (the
## Tactical close-up view), independent of the world-view flag above for
## the same reason the Threat Meter's two surfaces are independent.
var show_zoc_tactical: bool = true

func set_flag(property_name: StringName, value: bool) -> void:
	set(property_name, value)
	changed.emit()

func get_flag(property_name: StringName) -> bool:
	return get(property_name)
