class_name UnitSaveEntry
extends Resource

## One trained unit's saveable footprint (design doc Phase 2.8.1's own
## convention, applied to Phase 5.4's units) — deliberately NOT a full
## UnitInstance snapshot, same reasoning as BuildingSaveEntry: unit_type +
## hex_coord + id are persisted so UnitManager can re-look-up the live
## UnitDefinition from UnitCatalog by type on load instead of saving a
## definition copy. current_hp is the one exception saved alongside them —
## genuinely mutable per-instance state (combat damage) that can't be
## re-derived from the definition's fixed max_hp once play has moved it.

@export var unit_type: GameEnums.UnitType = GameEnums.UnitType.TRUNCHEONEER
@export var hex_coord: Vector2i = Vector2i.ZERO
@export var id: int = 0
@export var current_hp: float = 0.0

func _init(p_unit_type: GameEnums.UnitType = GameEnums.UnitType.TRUNCHEONEER, p_hex_coord: Vector2i = Vector2i.ZERO, p_id: int = 0, p_current_hp: float = 0.0) -> void:
	unit_type = p_unit_type
	hex_coord = p_hex_coord
	id = p_id
	current_hp = p_current_hp
