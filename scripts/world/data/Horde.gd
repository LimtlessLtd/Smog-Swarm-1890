class_name Horde
extends Resource

## One roaming zombie horde (design doc Phase 5.2/5.10) — a mobile entity
## with a hex position, a strength (`size`), and a behavioral state. Saved
## directly, same as WallSegment: nothing here references another live
## Resource, so there's no need for a separate save-entry wrapper the way
## BuildingInstance needs BuildingSaveEntry.
##
## Only GameEnums.HordeState.WANDERING is actually produced/transitioned to
## right now (see HordeManager) — ATTRACTED (drawn toward industrial noise
## or a lit vision source) and ATTACKING (besieging a specific wall
## segment/hex) are the rest of Phase 5.10's state machine, blocked on
## Phase 5.2's still-nonexistent noise tracking and Phase 5.4's
## still-nonexistent CombatEngine respectively. The enum values exist now so
## wiring them up later is additive, not a breaking rename.

@export var hex_coord: Vector2i = Vector2i.ZERO
@export var size: int = 0
@export var state: GameEnums.HordeState = GameEnums.HordeState.WANDERING
@export var id: int = 0

## Current drift path (Phase 5.5's HexPathfinder) — `hex_coord` itself is
## excluded, so the next hex to step into is `path[0]`. Deliberately NOT
## @export: it's cheap for HordeManager to replan from scratch after a load
## (same reasoning Zone of Control coverage uses for not saving itself —
## see LogisticsNetwork), and a mid-path point in time isn't meaningful
## state worth persisting anyway.
var path: Array[Vector2i] = []

func _init(p_hex_coord: Vector2i = Vector2i.ZERO, p_size: int = 0, p_id: int = 0, p_state: GameEnums.HordeState = GameEnums.HordeState.WANDERING) -> void:
	hex_coord = p_hex_coord
	size = p_size
	id = p_id
	state = p_state
