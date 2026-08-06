class_name SaveGameData
extends Resource

## Single aggregating save-file Resource (design doc Phase 2.8.2). Populated
## by SaveLoadManager pulling state out of each runtime manager — they're
## Nodes, which ResourceSaver can't serialize directly — and fed back into
## those same managers on load. See Phase 2.8.1 for what does and doesn't
## belong here and why: terrain/props and Zone of Control are deliberately
## absent because both regenerate/recompute byte-identically from what IS
## saved here (fixed map seeds; ZoC re-derives from buildings + supply lines).

@export var save_format_version: int = 1

## Campaign metadata (Phase 2.8.3, decided): saves are grouped by a
## player-named Campaign, with multiple manual slots per campaign.
@export var campaign_name: String = ""
@export var slot_name: String = ""
@export var saved_at: String = ""

## BuildingManager (Phase 2.1) — see BuildingSaveEntry for why this isn't
## just a saved Array[BuildingInstance].
@export var buildings: Array[BuildingSaveEntry] = []
@export var next_building_id: int = 1

## ResourceManager (Phase 2.2) stockpile + per-resource storage caps.
@export var resource_stockpile: Dictionary = {}     # GameEnums.ResourceType -> float
@export var resource_storage_caps: Dictionary = {}  # GameEnums.ResourceType -> float

## LogisticsNetwork (Phase 2.3) — supply line segments + severed state only.
## Zone of Control coverage itself is NOT saved: LogisticsNetwork.recompute()
## re-derives it fresh from the restored buildings and these segments.
@export var supply_lines: Array[SupplyLineSegment] = []

## TickManager (autoload) — current day, progress through it, and speed.
@export var current_day: int = 1
@export var elapsed_in_day: float = 0.0
@export var speed_index: int = 1

## FogOfWarManager (Phase 2.6) — the one piece of state here that looks
## derived but isn't: explored/visible memory is earned by play and can't be
## recomputed from buildings alone (recompute() only ever re-derives the
## currently-VISIBLE set, never which hexes are merely EXPLORED).
@export var fog_state: Dictionary = {}  # Vector2i -> GameEnums.FogState

## TechManager (Phase 2.9) — the researched set plus whichever node (if any)
## is currently in progress and how many days it has left. Flagged as a
## future addition back when Phase 2.8 was written, before Phase 2.9 existed
## to have state to save; TechCatalog itself is static seed data and never
## needs saving, same as BuildingCatalog.
@export var researched_techs: Array[StringName] = []
@export var active_tech_id: StringName = &""
@export var tech_days_remaining: int = 0
