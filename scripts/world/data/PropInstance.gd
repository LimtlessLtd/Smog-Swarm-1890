class_name PropInstance
extends Resource

## A single scatter-decoration placed within one hex's Tactical view — a
## tree, bush, rock or reed clump. Purely cosmetic (no gameplay data): the
## hex's own biome/soil/district fields remain the single source of truth,
## this just dresses the ground at close zoom. Generated fresh on demand by
## LocalDetailGenerator rather than stored/saved, so it never needs to be
## kept in sync with anything.

@export var prop_type: GameEnums.PropType = GameEnums.PropType.TREE
@export var local_position: Vector2 = Vector2.ZERO  ## Offset from the hex's own center.
@export var rotation: float = 0.0
@export var scale: float = 1.0

func _init(p_prop_type: GameEnums.PropType = GameEnums.PropType.TREE, p_local_position: Vector2 = Vector2.ZERO) -> void:
	prop_type = p_prop_type
	local_position = p_local_position
