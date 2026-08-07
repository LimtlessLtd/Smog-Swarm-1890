class_name GameEvent
extends RefCounted

## A single typed event record (design doc Phase 6.2's EventManager) — the
## shared shape every alert source (combat, territory, economy today;
## Phase 2.11's Discontent and Phase 7.2's narrative beats once those exist)
## raises through EventManager.raise_event() instead of each downstream
## consumer (AlertManager's audio/auto-pause, MainHUD's toast,
## StrategicOverlayManager's pulsing under-attack marker) wiring its own
## bespoke signal to every individual source.
##
## Deliberately RefCounted, not a Resource like UnitInstance/Horde/
## WallSegment/BuildingInstance — these are transient notifications, not
## persistent simulation state SaveLoadManager needs to round-trip. Nothing
## here saves an event log across a save/load; EventManager.get_recent_events()
## is scoped to "what's happened recently this session" for a future log UI,
## not a durable record.
##
## `hex_coord` follows the same "Vector2i.ZERO means no specific hex"
## convention BuildingManager.placement_rejected already established for its
## own "no hex grid map wired" case — colony-wide events (a resource
## stockpile running dry) have no single hex to point at.

var category: GameEnums.EventCategory
var severity: GameEnums.EventSeverity
var hex_coord: Vector2i
var message: String
var day: int  ## TickManager.current_day at the moment this was raised — a future event-log UI's own timestamp.

func _init(p_category: GameEnums.EventCategory = GameEnums.EventCategory.ECONOMY, p_severity: GameEnums.EventSeverity = GameEnums.EventSeverity.INFO, p_hex_coord: Vector2i = Vector2i.ZERO, p_message: String = "", p_day: int = 0) -> void:
	category = p_category
	severity = p_severity
	hex_coord = p_hex_coord
	message = p_message
	day = p_day
