class_name SaveGameData
extends Resource

## Single aggregating save-file Resource. Populated
## by SaveLoadManager pulling state out of each runtime manager — they're
## Nodes, which ResourceSaver can't serialize directly — and fed back into
## those same managers on load. Terrain/props and Zone of Control are
## deliberately absent because both regenerate/recompute byte-identically
## from what IS saved here (fixed map seeds; ZoC re-derives from buildings
## + supply lines) — see each field's own comment below for what does and
## doesn't belong here and why.

@export var save_format_version: int = 1

## Campaign metadata: saves are grouped by a player-named Campaign, with
## multiple manual slots per campaign.
@export var campaign_name: String = ""
@export var slot_name: String = ""
@export var saved_at: String = ""

## BuildingManager — see BuildingSaveEntry for why this isn't
## just a saved Array[BuildingInstance].
@export var buildings: Array[BuildingSaveEntry] = []
@export var next_building_id: int = 1

## ResourceManager stockpile + per-resource storage caps.
@export var resource_stockpile: Dictionary = {}     # GameEnums.ResourceType -> float
@export var resource_storage_caps: Dictionary = {}  # GameEnums.ResourceType -> float

## LogisticsNetwork — supply line segments + severed state only.
## Zone of Control coverage itself is NOT saved: LogisticsNetwork.recompute()
## re-derives it fresh from the restored buildings and these segments.
@export var supply_lines: Array[SupplyLineSegment] = []

## TickManager (autoload) — current day, progress through it, and speed.
@export var current_day: int = 1
@export var elapsed_in_day: float = 0.0
@export var speed_index: int = 1

## FogOfWarManager — the one piece of state here that looks
## derived but isn't: explored/visible memory is earned by play and can't be
## recomputed from buildings alone (recompute() only ever re-derives the
## currently-VISIBLE set, never which hexes are merely EXPLORED).
@export var fog_state: Dictionary = {}  # Vector2i -> GameEnums.FogState

## TechManager — the researched set plus whichever node (if any)
## is currently in progress and how many days it has left. TechCatalog
## itself is static seed data and never needs saving, same as
## BuildingCatalog.
@export var researched_techs: Array[StringName] = []
@export var active_tech_id: StringName = &""
@export var tech_days_remaining: int = 0

## DiscontentManager — per-hex Discontent values only; which
## hexes group into which Civilian Region is NOT saved, same reasoning as
## Zone of Control itself: it recomputes fresh from LogisticsNetwork on load.
@export var discontent_by_hex: Dictionary = {}  # Vector2i -> float

## InfestationManager — design_doc.md §2.1's one mutable number per hex.
## `infestation` and `is_cleared` are absent because both are DERIVED (D1, D2)
## and saving either would let it drift from the count; `total_zombie_pop` is
## absent because it is static baked terrain data that rebuilds identically on
## every boot. Zombies standing on a hex as a roaming Horde are counted through
## `hordes` below, not duplicated here.
##
## An EMPTY dictionary loaded from a pre-infestation save means "this save
## predates the model", not "the world is empty" — InfestationManager keeps its
## worldgen rings in that case. There is no save-format-version reader to tell
## the two apart (SAVE_FORMAT_VERSION is written and never read), so the empty
## case has to carry that meaning itself.
@export var resident_zombies_by_hex: Dictionary = {}  # Vector2i -> int

## WallManager — every placed WallSegment saves directly (see
## its own class doc comment for why no separate save-entry wrapper is
## needed, unlike BuildingSaveEntry).
@export var wall_segments: Array[WallSegment] = []
@export var next_wall_id: int = 1

## ReclamationManager — which hexes have been drained; see that
## class's own doc comment for why this is the one piece of terrain state
## that needs persisting despite the "terrain regenerates byte-identically
## from a fixed seed, no saving needed" baseline every other terrain field
## here follows.
@export var drained_hexes: Array[Vector2i] = []

## HordeManager — every roaming horde's position/size/state.
## In-flight drift paths are NOT saved (see Horde.path's own doc comment);
## HordeManager replans fresh after a load, same as Zone of Control coverage
## not saving itself.
@export var hordes: Array[Horde] = []
@export var next_horde_id: int = 1

## UnitManager — every trained unit's type/hex/HP/order, same
## save-entry-not-full-instance convention BuildingSaveEntry uses (re-looks
## up the live UnitDefinition from UnitCatalog by type on load).
@export var units: Array[UnitSaveEntry] = []
@export var next_unit_id: int = 1

## UnitManager — rally-point configuration per training
## building, independent of which units currently exist.
@export var unit_rally_points: Dictionary = {}  # Vector2i -> Vector2i

## TerritoryController — which hexes are currently territorially
## lost. Same "terrain regenerates byte-identically from a fixed seed, EXCEPT
## the one piece a runtime system can mutate" pattern ReclamationManager's
## own drained_hexes already established — District.is_contested lives on a
## freshly-regenerated HexCell on every boot, so which hexes this controller
## flipped needs its own explicit save, or a reload would silently un-lose
## every fallen district.
@export var lost_territory_hexes: Array[Vector2i] = []
