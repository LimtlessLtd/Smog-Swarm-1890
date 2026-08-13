class_name ResourceManager
extends Node

## Owns the colony's global resource stockpile. A pure
## economy ledger — it knows nothing about buildings, hexes or logistics.
## BuildingManager pushes daily production/upkeep totals in through
## apply_daily_flow(); later systems (combat ammo spend, campaign costs) can
## call spend()/add() directly the same way. Keeping this system ignorant of
## *why* resources move, only *that* they do, is what lets it stay a single
## reusable ledger for the rest of the game.

signal resources_changed(stockpile: Dictionary)
signal upkeep_shortfall(resource_type: GameEnums.ResourceType, shortfall: float)

const STARTING_STOCKPILE: Dictionary = {
	GameEnums.ResourceType.FOOD: 100.0,
	GameEnums.ResourceType.ENERGY: 50.0,
	GameEnums.ResourceType.GUNPOWDER: 20.0,
	GameEnums.ResourceType.RESEARCH_POINTS: 0.0,
	GameEnums.ResourceType.WOOD: 150.0,
	GameEnums.ResourceType.BRICKS: 100.0,
	GameEnums.ResourceType.CAST_IRON: 40.0,
	GameEnums.ResourceType.REINFORCED_CONCRETE: 0.0,
}

var _stockpile: Dictionary = {}     # GameEnums.ResourceType -> float
var _storage_caps: Dictionary = {}  # GameEnums.ResourceType -> float (INF = uncapped)

func _ready() -> void:
	for resource_type in STARTING_STOCKPILE:
		_stockpile[resource_type] = STARTING_STOCKPILE[resource_type]
		_storage_caps[resource_type] = INF

func get_amount(resource_type: GameEnums.ResourceType) -> float:
	return _stockpile.get(resource_type, 0.0)

func get_full_stockpile() -> Dictionary:
	return _stockpile.duplicate()

func get_storage_cap(resource_type: GameEnums.ResourceType) -> float:
	return _storage_caps.get(resource_type, INF)

## Exposed for SaveLoadManager alongside get_full_stockpile() —
## caps drift from their STARTING_STOCKPILE default via add_storage_cap()
## (e.g. a Grain Silo's storage_bonus), so they need saving just like the
## stockpile itself.
func get_full_storage_caps() -> Dictionary:
	return _storage_caps.duplicate()

## Restores stockpile + caps from a save, replacing whatever
## _ready() seeded from STARTING_STOCKPILE.
func load_state(stockpile: Dictionary, storage_caps: Dictionary) -> void:
	_stockpile = stockpile.duplicate()
	_storage_caps = storage_caps.duplicate()
	resources_changed.emit(get_full_stockpile())

func set_storage_cap(resource_type: GameEnums.ResourceType, cap: float) -> void:
	_storage_caps[resource_type] = cap
	_stockpile[resource_type] = minf(get_amount(resource_type), cap)
	# A cap change is a meaningful change to anything watching resources_changed
	# (e.g. the resource bar shows "amount/cap") even when the
	# stockpile amount itself doesn't move.
	resources_changed.emit(get_full_stockpile())

func add_storage_cap(resource_type: GameEnums.ResourceType, bonus: float) -> void:
	set_storage_cap(resource_type, get_storage_cap(resource_type) + bonus)

func can_afford(costs: Dictionary) -> bool:
	for resource_type in costs:
		if get_amount(resource_type) < float(costs[resource_type]):
			return false
	return true

## Deducts `costs` if (and only if) every entry is affordable. Returns
## whether the spend happened, so callers can fail placement/actions cleanly.
func spend(costs: Dictionary) -> bool:
	if not can_afford(costs):
		return false
	for resource_type in costs:
		_stockpile[resource_type] = get_amount(resource_type) - float(costs[resource_type])
	resources_changed.emit(get_full_stockpile())
	return true

func add(resource_type: GameEnums.ResourceType, amount: float) -> void:
	_stockpile[resource_type] = minf(get_amount(resource_type) + amount, get_storage_cap(resource_type))
	resources_changed.emit(get_full_stockpile())

## An unconditional decrement — distinct from spend(), which enforces
## can_afford() and refuses the WHOLE transaction if it isn't. The Energy
## grid-allocation ledger needs this: a power PRODUCER
## ruining while its capacity is still allocated to live consumers should
## show as a real deficit (a negative stockpile) — the same honest "you're
## short" signal any other resource running low already gives, not
## silently blocked or floored to zero the way a player-initiated spend()
## should be. No storage-cap clamp either, for the same reason add() clamps
## at the cap but this doesn't clamp at 0 — the cap models a maximum, not a
## minimum. Not intended for ordinary player-facing costs; use spend() for
## those.
func remove(resource_type: GameEnums.ResourceType, amount: float) -> void:
	_stockpile[resource_type] = get_amount(resource_type) - amount
	resources_changed.emit(get_full_stockpile())

## Called once per in-game day (by BuildingManager, driven off
## TickManager.day_completed) with the totals every placed building consumed
## and produced that day. Upkeep is applied first; a resource that can't
## fully cover its upkeep drains to zero and reports `upkeep_shortfall`
## rather than going negative — future morale/combat systems can hang
## penalties off that signal once they exist.
func apply_daily_flow(consumed: Dictionary, produced: Dictionary) -> void:
	for resource_type in consumed:
		var have := get_amount(resource_type)
		var need := float(consumed[resource_type])
		if have < need:
			upkeep_shortfall.emit(resource_type, need - have)
			_stockpile[resource_type] = 0.0
		else:
			_stockpile[resource_type] = have - need
	for resource_type in produced:
		add(resource_type, float(produced[resource_type]))
	resources_changed.emit(get_full_stockpile())
