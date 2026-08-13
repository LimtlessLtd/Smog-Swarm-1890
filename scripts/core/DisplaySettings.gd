extends Node

## Global, cross-cutting UI display-layer toggles. "Add options so we can
## enable and disable the overlays" (user request). An autoload rather than
## a Main.tscn sibling wired via NodePath — its consumers span unrelated
## scene-tree branches (`StrategicOverlayManager` under `WorldRoot`,
## `MinimapView`/`DisplayOptionsView` under `MainHUD`) that share no closer
## common ancestor than `Main` itself, and every toggle needs to reach all
## of them without threading a NodePath through intermediate nodes that
## have no other reason to know about display preferences. Same
## cross-cutting singleton role `TickManager`/`TimeCycleManager` play for
## simulation state, just for UI state instead.
##
## Not part of `SaveGameData` — a display preference (do I want to see wall
## markers right now?) is a client-side viewing choice, not campaign
## state, same reasoning `CameraController`'s own zoom/pan position is
## never saved either.
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
## view's own marker layers (building/frontier/wall/unit/horde markers,
## under-attack alerts) plus the Threat Meter drawn there.
var show_building_markers: bool = true
var show_frontier_markers: bool = true
var show_wall_markers: bool = true
var show_unit_markers: bool = true
var show_horde_markers: bool = true
var show_attack_alerts: bool = true
var show_threat_meter_world: bool = true
## Zone of Control — consulted by `StrategicOverlayManager`'s own ZoC layer.
var show_zoc_world: bool = true
## Elevation/impassable-terrain overlay. "We need to make elevation and
## impassable terrain obvious to the user" (user report) — consulted by
## `StrategicOverlayManager`'s own TerrainLayer. Defaults ON: this is
## safety-relevant information ("can my unit actually walk there"), same
## reasoning every other marker layer here defaults ON.
var show_terrain_hazards: bool = true

## Consulted by `MinimapView` — the Threat Meter's other surface (the hex
## overview map), independent of the world-view flag above so either can
## be toggled without the other.
var show_threat_meter_minimap: bool = true
## Consulted by `TacticalHexView` — Zone of Control's other surface (the
## Tactical close-up view), independent of the world-view flag above for
## the same reason the Threat Meter's two surfaces are independent.
var show_zoc_tactical: bool = true

func set_flag(property_name: StringName, value: bool) -> void:
	set(property_name, value)
	changed.emit()

func get_flag(property_name: StringName) -> bool:
	return get(property_name)
