class_name EventManager
extends Node

## Shared event queue — typed event records (source hex, category,
## severity, message) that every alert source registers against instead of
## each downstream consumer (AlertManager's audio/auto-pause, MainHUD's
## toast, AttackAlertRenderer's pulsing under-attack marker) wiring its own
## bespoke signal to every individual source. Sits ABOVE BuildingManager/
## WallManager/CombatCoordinator/TerritoryController/ResourceManager/
## StrategicOverlayManager, the same "orchestration layer reads from many,
## referenced by none of them" role CombatCoordinator/FogOfWarManager play
## over what THEY sit above — none of the six managers below know this
## class exists.
##
## Wired sources:
##   - WallManager.wall_segment_breached -> COMBAT/CRITICAL.
##   - CombatCoordinator.engagement_resolved -> COMBAT/CRITICAL if the unit
##     was destroyed, COMBAT/WARNING otherwise — but the WARNING is raised
##     once per unit per day, not once per round. Combat became CONTINUOUS
##     when ResidentDefenseController started resolving a round every
##     WAVE_INTERVAL_SECONDS for a unit standing on infested ground
##     (design_doc.md §2.1), so "under attack" now fires for as long as the
##     player holds the line; the same "raise on the transition INTO the bad
##     state, not every day it persists" shape the food-band and
##     resource-shortfall trackers below already use. A CRITICAL death is
##     never suppressed.
##   - BuildingManager.building_ruined -> COMBAT/CRITICAL.
##   - TerritoryController.territory_lost -> TERRITORY/CRITICAL;
##     territory_recaptured -> TERRITORY/INFO (good news doesn't need to
##     interrupt play — see AlertManager's own doc comment on what INFO
##     means for auto-pause).
##   - StrategicOverlayManager.horde_spotted -> COMBAT/CRITICAL, but only
##     for hordes already deemed marker-worthy (size >= HordeMarkerRenderer.MIN_SIZE)
##     — reusing that filter rather than re-deriving "is this horde
##     dangerous enough to interrupt play" a second time here.
##   - BuildingManager.food_satisfaction_changed -> ECONOMY event on
##     crossing INTO a worse band (100% / 75% / 50%), not re-raised every
##     day it stays there; the tracker resets once satisfaction recovers
##     back to >= 100%, so a future decline can raise again.
##   - ResourceManager.upkeep_shortfall -> ECONOMY/WARNING on the transition
##     INTO shortfall for that resource type (not re-raised every day it
##     stays short); ResourceManager.resources_changed clears the tracked
##     flag once that resource's stockpile rises back above zero.
##
## GameEnums.EventCategory.UNREST/NARRATIVE exist as documented, unused
## hooks for Discontent and a future CampaignManager — see that enum's own
## doc comment.

signal event_raised(event: GameEvent)

const MAX_HISTORY: int = 50

## Mirrored here rather than re-derived from BuildingManager — crossing
## DOWN into a worse band raises an event; recovering to >= 1.0 resets the
## tracker so a future decline can raise again.
const FOOD_BAND_HUNGRY: float = 1.0
const FOOD_BAND_SEVERE: float = 0.75
const FOOD_BAND_STARVING: float = 0.5

@export var building_manager_path: NodePath
@export var wall_manager_path: NodePath
@export var combat_coordinator_path: NodePath
@export var territory_controller_path: NodePath
@export var resource_manager_path: NodePath
@export var strategic_overlay_manager_path: NodePath  ## Optional — without it, a spotted large horde simply raises no event (StrategicOverlayManager itself is unaffected either way).

var _history: Array[GameEvent] = []
var _food_band: int = 0                              # 0 fine, 1 hungry (<100%), 2 severe (<75%), 3 starving (<50%)
var _resource_shortfall_active: Dictionary = {}       # GameEnums.ResourceType -> bool
## UnitInstance.id -> true, for units already warned about since the last day
## rolled over. Keyed by id rather than by the instance so a destroyed unit's
## entry can be dropped without holding a reference to it.
var _unit_under_attack: Dictionary = {}

func _ready() -> void:
	if building_manager_path != NodePath():
		var building_manager: BuildingManager = get_node(building_manager_path)
		building_manager.building_ruined.connect(_on_building_ruined)
		building_manager.food_satisfaction_changed.connect(_on_food_satisfaction_changed)
	if wall_manager_path != NodePath():
		var wall_manager: WallManager = get_node(wall_manager_path)
		wall_manager.wall_segment_breached.connect(_on_wall_segment_breached)
	if combat_coordinator_path != NodePath():
		var combat_coordinator: CombatCoordinator = get_node(combat_coordinator_path)
		combat_coordinator.engagement_resolved.connect(_on_engagement_resolved)
	if territory_controller_path != NodePath():
		var territory_controller: TerritoryController = get_node(territory_controller_path)
		territory_controller.territory_lost.connect(_on_territory_lost)
		territory_controller.territory_recaptured.connect(_on_territory_recaptured)
	if resource_manager_path != NodePath():
		var resource_manager: ResourceManager = get_node(resource_manager_path)
		resource_manager.upkeep_shortfall.connect(_on_upkeep_shortfall)
		resource_manager.resources_changed.connect(_on_resources_changed)
	if strategic_overlay_manager_path != NodePath():
		var strategic_overlay_manager: StrategicOverlayManager = get_node(strategic_overlay_manager_path)
		strategic_overlay_manager.horde_spotted.connect(_on_horde_spotted)
	# Clears the per-unit "already warned" set — see _unit_under_attack.
	TickManager.day_completed.connect(_on_day_completed)

## The one entry point every handler below (and any future alert source)
## funnels through — builds the record, trims history to MAX_HISTORY,
## broadcasts it, and hands it back in case a caller wants it directly.
func raise_event(category: GameEnums.EventCategory, severity: GameEnums.EventSeverity, hex_coord: Vector2i, message: String) -> GameEvent:
	var event := GameEvent.new(category, severity, hex_coord, message, TickManager.current_day)
	_history.append(event)
	if _history.size() > MAX_HISTORY:
		_history.pop_front()
	event_raised.emit(event)
	return event

## For a future event-log UI (not built this phase) — the most recent
## `count` events, oldest first.
func get_recent_events(count: int = 10) -> Array[GameEvent]:
	return _history.slice(maxi(0, _history.size() - count), _history.size())

func _on_wall_segment_breached(segment: WallSegment) -> void:
	raise_event(GameEnums.EventCategory.COMBAT, GameEnums.EventSeverity.CRITICAL, segment.hex_a, "Wall breached near %s — zombies are pouring through!" % _coord_string(segment.hex_a))

## A unit under sustained attack warns ONCE, not every round — see this class's
## own doc comment. Death is always raised: it happens once by definition, and
## it is the event the player most needs interrupted for.
func _on_engagement_resolved(instance: UnitInstance, _horde: Horde, _result: Dictionary) -> void:
	var name := instance.definition.display_name if instance.definition else "A unit"
	if instance.is_destroyed():
		_unit_under_attack.erase(instance.id)
		raise_event(GameEnums.EventCategory.COMBAT, GameEnums.EventSeverity.CRITICAL, instance.hex_coord, "%s was wiped out at %s!" % [name, _coord_string(instance.hex_coord)])
		return
	if _unit_under_attack.has(instance.id):
		return
	_unit_under_attack[instance.id] = true
	raise_event(GameEnums.EventCategory.COMBAT, GameEnums.EventSeverity.WARNING, instance.hex_coord, "%s is under attack at %s." % [name, _coord_string(instance.hex_coord)])

## A day is the coarsest interval that still lets a renewed attack on the same
## unit reach the player. Anything finer re-introduces the spam; anything
## coarser (never re-arming) means a unit that survives one skirmish is silent
## for the rest of the campaign.
func _on_day_completed(_day_number: int) -> void:
	_unit_under_attack.clear()

func _on_building_ruined(instance: BuildingInstance, lost_population: int) -> void:
	var name := instance.definition.display_name if instance.definition else "A building"
	var population_note := " (%d civilians lost)" % lost_population if lost_population > 0 else ""
	raise_event(GameEnums.EventCategory.COMBAT, GameEnums.EventSeverity.CRITICAL, instance.hex_coord, "%s destroyed at %s%s!" % [name, _coord_string(instance.hex_coord), population_note])

func _on_territory_lost(coord: Vector2i) -> void:
	raise_event(GameEnums.EventCategory.TERRITORY, GameEnums.EventSeverity.CRITICAL, coord, "Territory lost at %s!" % _coord_string(coord))

func _on_territory_recaptured(coord: Vector2i) -> void:
	raise_event(GameEnums.EventCategory.TERRITORY, GameEnums.EventSeverity.INFO, coord, "Territory recaptured at %s." % _coord_string(coord))

func _on_horde_spotted(horde: Horde) -> void:
	raise_event(GameEnums.EventCategory.COMBAT, GameEnums.EventSeverity.CRITICAL, horde.hex_coord, "A large horde (%d strong) has been spotted near %s!" % [horde.size, _coord_string(horde.hex_coord)])

func _on_food_satisfaction_changed(ratio: float) -> void:
	var band := 0
	if ratio < FOOD_BAND_STARVING:
		band = 3
	elif ratio < FOOD_BAND_SEVERE:
		band = 2
	elif ratio < FOOD_BAND_HUNGRY:
		band = 1
	if band > _food_band:
		var percent := int(round(ratio * 100.0))
		if band == 3:
			raise_event(GameEnums.EventCategory.ECONOMY, GameEnums.EventSeverity.CRITICAL, Vector2i.ZERO, "Food satisfaction has collapsed to %d%% — production is badly hurt!" % percent)
		else:
			raise_event(GameEnums.EventCategory.ECONOMY, GameEnums.EventSeverity.WARNING, Vector2i.ZERO, "Food is running short — satisfaction has dropped to %d%%." % percent)
	_food_band = band

func _on_upkeep_shortfall(resource_type: GameEnums.ResourceType, _shortfall: float) -> void:
	if _resource_shortfall_active.get(resource_type, false):
		return
	_resource_shortfall_active[resource_type] = true
	raise_event(GameEnums.EventCategory.ECONOMY, GameEnums.EventSeverity.WARNING, Vector2i.ZERO, "%s stockpile has run out!" % ResourceVisuals.display_name(resource_type))

func _on_resources_changed(stockpile: Dictionary) -> void:
	for resource_type in _resource_shortfall_active.keys():
		if _resource_shortfall_active[resource_type] and float(stockpile.get(resource_type, 0.0)) > 0.01:
			_resource_shortfall_active[resource_type] = false

func _coord_string(coord: Vector2i) -> String:
	return "(%d, %d)" % [coord.x, coord.y]
