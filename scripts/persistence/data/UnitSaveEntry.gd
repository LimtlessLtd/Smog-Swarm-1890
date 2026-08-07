class_name UnitSaveEntry
extends Resource

## One trained unit's saveable footprint (design doc Phase 2.8.1's own
## convention, applied to Phase 5.4's units) — deliberately NOT a full
## UnitInstance snapshot, same reasoning as BuildingSaveEntry: unit_type +
## hex_coord + id are persisted so UnitManager can re-look-up the live
## UnitDefinition from UnitCatalog by type on load instead of saving a
## definition copy. current_hp, order/move_target/patrol_waypoints (Phase
## 5.6), kill_count (Phase 5.7), and local_position (Phase 2.5.4) are the
## exceptions saved alongside them — genuinely mutable per-instance state
## that can't be re-derived from the definition. The in-flight movement
## path itself (UnitInstance.path) is NOT saved, same as Horde.path — cheap
## for UnitOrderController to replan from scratch, and a patrol always
## restarts its loop from leg 0 after a load rather than resuming mid-leg
## (UnitInstance.patrol_target_index isn't saved either).

@export var unit_type: GameEnums.UnitType = GameEnums.UnitType.TRUNCHEONEER
@export var hex_coord: Vector2i = Vector2i.ZERO
@export var id: int = 0
@export var current_hp: float = 0.0
@export var order: GameEnums.UnitOrderType = GameEnums.UnitOrderType.HOLD
@export var move_target: Vector2i = Vector2i.ZERO
@export var patrol_waypoints: Array[Vector2i] = []
@export var kill_count: int = 0
@export var local_position: Vector2 = Vector2.ZERO  ## Phase 2.5.4.

func _init(p_unit_type: GameEnums.UnitType = GameEnums.UnitType.TRUNCHEONEER, p_hex_coord: Vector2i = Vector2i.ZERO, p_id: int = 0, p_current_hp: float = 0.0, p_order: GameEnums.UnitOrderType = GameEnums.UnitOrderType.HOLD, p_move_target: Vector2i = Vector2i.ZERO, p_patrol_waypoints: Array[Vector2i] = [], p_kill_count: int = 0, p_local_position: Vector2 = Vector2.ZERO) -> void:
	unit_type = p_unit_type
	hex_coord = p_hex_coord
	id = p_id
	current_hp = p_current_hp
	order = p_order
	move_target = p_move_target
	patrol_waypoints = p_patrol_waypoints
	kill_count = p_kill_count
	local_position = p_local_position
