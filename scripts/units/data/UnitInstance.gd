class_name UnitInstance
extends Resource

## A single trained unit: a reference to its UnitDefinition template, the
## hex it currently occupies, a unique id assigned by UnitManager, and its
## current HP. Mirrors BuildingInstance's shape/role, with one difference:
## combat HP lives here now rather than being a "later-phase concern" the
## way BuildingInstance's own doc comment defers it — Phase 5.4 (this
## phase) is specifically the one introducing combat math (CombatEngine),
## so a unit needs somewhere to record damage from turn one.
##
## No local_position (Phase 2.5's Tactical-view exact-placement field on
## BuildingInstance) yet — a trained unit sits at hex granularity until
## Phase 5.5's tactical-scale movement / Phase 5.6's orders give it a reason
## to occupy a precise point within a hex.

@export var definition: UnitDefinition
@export var hex_coord: Vector2i = Vector2i.ZERO
@export var id: int = 0
@export var current_hp: float = 0.0

func _init(p_definition: UnitDefinition = null, p_hex_coord: Vector2i = Vector2i.ZERO, p_id: int = 0, p_current_hp: float = -1.0) -> void:
	definition = p_definition
	hex_coord = p_hex_coord
	id = p_id
	# -1.0 is "not specified" (a fresh training) — seed at the definition's
	# full health. A save-restore path passes the actual saved value
	# instead, same -1-sentinel convention BuildingInstance/WallSegment use.
	current_hp = p_current_hp if p_current_hp >= 0.0 else (p_definition.max_hp if p_definition else 0.0)

func is_destroyed() -> bool:
	return current_hp <= 0.0
