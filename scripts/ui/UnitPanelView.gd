class_name UnitPanelView
extends ScrollContainer

## Selection-driven HUD panel — the training-and-orders counterpart to
## BuildMenuView, reading UnitCommandController's current selection instead
## of arming a placement mode. Four states (a fifth, "nothing selected", is
## deliberately not a rendered state at all — see _render_idle()'s own doc
## comment):
##   - A building that can train units (Garrison today) selected: one Train
##     button per UnitCatalog definition (tier-locked/unaffordable ones
##     shown disabled with UnitManager.get_training_error()'s reason as a
##     tooltip — same "queryable rejection reason" convention BuildMenuView's
##     cost tooltip and BuildPlacementController's ghost color both already
##     lean on), PLUS a Repair section if the building is ruined.
##   - Any OTHER building selected (Town Hall, Foundry, a damaged
##     Workhouse, ...): just its name/HP/state and — real bug fixed, player
##     report ("Same goes for all the buildings" re: no way to select/repair
##     one) — a Repair button once it's actually ruined. Every building is
##     now selectable, not just training ones (UnitCommandController's own
##     doc comment has the full story).
##   - A wall segment selected (also a first — walls had no selection path
##     at all before): tier/HP/breached state and the same kind of Repair
##     button.
##   - A unit selected: its stats (HP, rank, current order) plus Hold /
##     Garrison / Patrol (click-to-record waypoints on the map, Confirm
##     here) / Retrain buttons, all wired straight back into
##     UnitCommandController — this view never calls UnitManager/
##     UnitOrderController/BuildingManager/WallManager directly, same "dumb
##     display, controller owns the actual call" split BuildMenuView keeps
##     with BuildPlacementController. `_building_manager`/`_wall_manager`
##     below are the one exception, and only ever used to LISTEN for live
##     state changes (repair completing, HP changing) — same read-only
##     pattern `_unit_manager`'s own roster-change listeners already use,
##     never to issue a command themselves.

var _unit_command_controller: UnitCommandController
var _unit_manager: UnitManager
var _building_manager: BuildingManager
var _wall_manager: WallManager

var _list: VBoxContainer

func _ready() -> void:
	custom_minimum_size = Vector2(260, 220)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  ## No dialog should ever need a horizontal scrollbar — see TechTreeView's own note on this.
	HUDStyles.style_panel(self)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_list)
	_render_idle()

func setup(unit_command_controller: UnitCommandController, unit_manager: UnitManager, building_manager: BuildingManager = null, wall_manager: WallManager = null) -> void:
	_unit_command_controller = unit_command_controller
	_unit_manager = unit_manager
	_building_manager = building_manager
	_wall_manager = wall_manager
	if _unit_command_controller:
		_unit_command_controller.unit_selected.connect(_on_unit_selected)
		_unit_command_controller.building_instance_selected.connect(_on_building_selected)
		_unit_command_controller.wall_segment_selected.connect(_on_wall_selected)
		_unit_command_controller.selection_cleared.connect(_on_selection_cleared)
		_unit_command_controller.patrol_recording_changed.connect(_on_patrol_recording_changed)
	if _unit_manager:
		_unit_manager.unit_trained.connect(_on_roster_changed)
		_unit_manager.unit_removed.connect(_on_roster_changed)
		_unit_manager.unit_retrained.connect(_on_roster_changed)
		# User request (playtest round 5, training queue): a freshly-queued
		# job (training_started, fires the instant it's accepted/paid for —
		# unit_trained itself doesn't fire until the queue actually finishes)
		# should appear in the panel immediately, and its "ready in N days"
		# countdown needs to tick down once per real day_completed, not just
		# whenever the roster happens to change for an unrelated reason.
		_unit_manager.training_started.connect(_on_training_started)
		TickManager.day_completed.connect(_on_day_completed)
	if _building_manager:
		_building_manager.repair_started.connect(_on_building_stats_changed)
		_building_manager.building_repaired.connect(_on_building_stats_changed)
		_building_manager.building_ruined.connect(_on_building_stats_changed)
		# Adversarial code-review finding (this pass's own verification
		# step): HP/Population/"if overrun"/Upkeep were only ever computed
		# once at render time — combat damage and starvation/regrowth both
		# silently mutate the live BuildingInstance without either of the
		# three signals above firing, so a panel left open across either
		# event kept showing stale numbers. Reuses the same handler (its
		# body already just checks "is the affected instance the one
		# currently selected" — that check doesn't care WHY it changed).
		_building_manager.building_damaged.connect(_on_building_stats_changed)
		_building_manager.building_population_changed.connect(_on_building_stats_changed)
	if _wall_manager:
		_wall_manager.repair_started.connect(_on_wall_repair_changed)
		_wall_manager.wall_segment_repaired.connect(_on_wall_repair_changed)
		_wall_manager.wall_segment_breached.connect(_on_wall_repair_changed)

func _on_unit_selected(instance: UnitInstance) -> void:
	_render_unit_panel(instance)

func _on_building_selected(instance: BuildingInstance) -> void:
	_render_building_panel(instance)

func _on_wall_selected(segment: WallSegment) -> void:
	_render_wall_panel(segment)

func _on_selection_cleared() -> void:
	_render_idle()

## Re-renders whatever's currently selected so the panel stays live —
## covers both the patrol-waypoint counter changing while recording and a
## training/roster change (a unit dying, a fresh one trained) invalidating
## the buttons already drawn.
func _on_patrol_recording_changed(_is_recording: bool, _waypoint_count: int) -> void:
	_refresh_current_selection()

func _on_roster_changed(_instance: UnitInstance) -> void:
	_refresh_current_selection()

## Training queue (playtest round 5) — a fresh job appearing, or one day's
## worth of countdown ticking off an existing one, both need the currently-
## selected building's panel (if any) to redraw with the new numbers.
## `_refresh_current_selection()` itself already no-ops harmlessly if
## nothing/a non-training-building is selected right now.
func _on_training_started(_unit_type: GameEnums.UnitType, _coord: Vector2i, _days: int) -> void:
	_refresh_current_selection()

func _on_day_completed(_day_number: int) -> void:
	_refresh_current_selection()

## Broadened past its original "repair state changed" scope (adversarial
## code-review finding, this pass's own verification step) — a repair
## starting/finishing, a fresh ruin, combat damage, or a starvation/
## regrowth population change should all immediately refresh whatever
## stats this panel is showing rather than leaving them stale until the
## player deselects and reselects. `_extra` absorbs whatever payload each
## of the four source signals happens to carry (an HP delta, a population
## count, or nothing) — this handler only ever cares WHICH instance
## changed, never why.
func _on_building_stats_changed(instance: BuildingInstance, _extra: Variant = null) -> void:
	if _unit_command_controller and _unit_command_controller.get_selected_building() == instance:
		_refresh_current_selection()

func _on_wall_repair_changed(segment: WallSegment, _extra: Variant = null) -> void:
	if _unit_command_controller and _unit_command_controller.get_selected_wall() == segment:
		_refresh_current_selection()

func _refresh_current_selection() -> void:
	if not _unit_command_controller:
		return
	var unit := _unit_command_controller.get_selected_unit()
	if unit:
		_render_unit_panel(unit)
		return
	var building := _unit_command_controller.get_selected_building()
	if building:
		_render_building_panel(building)
		return
	var wall := _unit_command_controller.get_selected_wall()
	if wall:
		_render_wall_panel(wall)

## Also re-shows the panel — the only caller that wants it hidden again
## (_render_idle()) sets `visible = false` itself right after calling this,
## so that override always wins for the idle case.
func _clear_list() -> void:
	visible = true
	for child in _list.get_children():
		child.queue_free()

## User request (playtest round 4): the idle hint window "serves no purpose
## since you can get to all the windows and options by selecting the
## buildings or units directly" — this panel now just hides itself entirely
## with nothing selected, instead of showing an always-on instructional
## label. `_on_selection_cleared()`/`setup()` still route here; the whole
## ScrollContainer (this class extends it) simply goes invisible rather than
## rendering empty content, same "nothing to show, so show nothing" contract
## the other toggleable HUD panels (SaveLoadView/TechTreeView/
## DisplayOptionsView) already use for their own closed state.
func _render_idle() -> void:
	_clear_list()
	visible = false

## Training panel (a `can_train_units` building, Garrison today) and the
## general building-info panel (everything else) share one function —
## both need the same header/repair section, and a training building can
## itself be ruined and need repair same as any other, so branching inside
## one panel avoids duplicating that shared section across two.
func _render_building_panel(instance: BuildingInstance) -> void:
	_clear_list()
	var definition := instance.definition
	var header := Label.new()
	var tag := " (RUINED)" if instance.is_ruined else (" (UNDER CONSTRUCTION)" if instance.is_under_construction else "")
	header.text = "%s%s" % [definition.display_name, tag]
	HUDStyles.style_label(header, true)
	_list.add_child(header)

	if not instance.is_ruined:
		var stats := Label.new()
		stats.text = "HP %d/%d" % [int(instance.current_hp), int(definition.get_max_hp())]
		HUDStyles.style_label(stats)
		_list.add_child(stats)
		# Economy stats (daily output/upkeep) would misleadingly suggest a
		# construction site is already producing — it isn't, see
		# BuildingManager._on_day_completed()'s own is_under_construction skip.
		if not instance.is_under_construction:
			_add_building_economy_stats(instance)

	_add_repair_button(
		instance.is_ruined,
		func() -> String: return _unit_command_controller.get_selected_building_repair_error(),
		_unit_command_controller.repair_selected_building
	)
	_add_demolish_button(
		func() -> String: return _unit_command_controller.get_selected_building_demolish_error(),
		_unit_command_controller.demolish_selected_building,
		instance.is_under_construction
	)

	# User report (playtest round 6): "you shouldn't be able to build units
	# from a garrison that is under construction... while under
	# construction they shouldn't be able to do anything" — same
	# is_under_construction/is_ruined gate _add_building_economy_stats()
	# above already applies, extended to the training grid/queue too
	# rather than showing a Train section for a building that would just
	# reject every card with "must finish construction" anyway.
	if definition.can_train_units and not instance.is_under_construction and not instance.is_ruined:
		var coord := instance.hex_coord
		var train_header := Label.new()
		train_header.text = "Train at %s" % coord
		HUDStyles.style_label(train_header, true)
		_list.add_child(train_header)
		if _unit_manager:
			# User request (playtest round 4, #8): "you should be able to see
			# what the unit looks like, how much it costs and the upkeep" —
			# same HUDStyles.build_card() shape BuildMenuView's own building
			# cards use (see that function's own doc comment), not a
			# text-only Button. A GridContainer (2 columns), not the plain
			## HBoxContainer BuildMenuView's wider bottom bar affords — this
			# panel is a narrow top-left corner box (UNIT_PANEL_SIZE) with no
			# horizontal scrolling (_ready()'s own "no dialog should ever
			# need a horizontal scrollbar" rule) — 2 columns keeps every
			# card fully visible via ordinary vertical scrolling instead.
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 6)
			grid.add_theme_constant_override("v_separation", 6)
			_list.add_child(grid)
			for unit_definition in UnitCatalog.get_all_definitions():
				var error := _unit_manager.get_training_error(unit_definition.unit_type, coord)
				var enabled := error.is_empty()
				var details := "%s\n%s" % [_role_name(unit_definition.role), (error if not enabled else _unit_card_details(unit_definition))]
				grid.add_child(HUDStyles.build_card(
					"%s (T%d)" % [unit_definition.display_name, unit_definition.tier],
					UnitVisuals.unit_texture(unit_definition.unit_type),
					details,
					_on_train_pressed.bind(coord, unit_definition.unit_type),
					enabled,
					110.0, 36.0,
				))
			_add_training_queue(coord)

## User request (playtest round 5): "there should be a visible unit
## building queue so that we can see how long is remaining on units under
## construction and how many units of what types we have under
## construction" — every `UnitManager.get_pending_training()` entry queued
## AT THIS building (matched by coord; a second Garrison elsewhere has its
## own independent queue, not shown here), oldest-first, straight off the
## same list `_process_pending_training()` itself ticks down — this can't
## show a different number than what will actually finish. Skipped
## entirely (not even an empty header) when nothing's queued, same "don't
## show a section with nothing to say" restraint the Population/zombie
## lines above already keep for a building with no housing capacity.
func _add_training_queue(coord: Vector2i) -> void:
	if not _unit_manager:
		return
	var jobs := []
	for job in _unit_manager.get_pending_training():
		if job["coord"] == coord:
			jobs.append(job)
	if jobs.is_empty():
		return

	var queue_header := Label.new()
	queue_header.text = "Training Queue (%d)" % jobs.size()
	HUDStyles.style_label(queue_header, true)
	_list.add_child(queue_header)

	for job in jobs:
		var definition := UnitCatalog.get_definition(job["unit_type"])
		var display_name := definition.display_name if definition else "Unit"
		var days: int = job["days_remaining"]
		var line := Label.new()
		line.text = "%s — ready in %d day%s" % [display_name, days, "" if days == 1 else "s"]
		HUDStyles.style_label(line, false, true)
		_list.add_child(line)

## User request ("when selecting a building, we should see various
## statistics... how much upkeep it costs, how many population it has
## inside and if it were to fall to zombie attacks how many zombies it
## would produce (its the same number)", later "please include energy in
## the building stats panel") — under an intact building's HP:
## current/capacity population, the exact casualty count
## BuildingManager.damage_building() would actually convert to a horde if
## this building fell right now (building_ruined's own `lost_population`
## payload IS `instance.current_population` at the moment it ruins — see
## that signal's doc comment — so this is read straight off the same
## field, not a separate estimate that could drift from the real
## mechanic), recurring daily upkeep, and Energy. Population/zombie lines
## are skipped entirely for a building with no housing capacity at all
## (population_provided == 0 — industry/agriculture/defense buildings),
## same "don't show a stat that's always trivially zero" restraint
## `can_train_units` already gets below.
func _add_building_economy_stats(instance: BuildingInstance) -> void:
	var definition := instance.definition
	_add_production_stat(instance)
	if definition.population_provided > 0:
		var population_stats := Label.new()
		population_stats.text = "Population: %d / %d" % [instance.current_population, definition.population_provided]
		HUDStyles.style_label(population_stats)
		_list.add_child(population_stats)

		var zombie_stats := Label.new()
		zombie_stats.text = "If overrun: %d zombies" % instance.current_population
		HUDStyles.style_label(zombie_stats, false, true)  # Muted — a warning to read, not the headline stat.
		_list.add_child(zombie_stats)

	var upkeep_text := _recurring_upkeep_display(instance)
	if not upkeep_text.is_empty():
		var upkeep_stats := Label.new()
		upkeep_stats.text = "Upkeep: %s / day" % upkeep_text
		HUDStyles.style_label(upkeep_stats, false, true)
		_list.add_child(upkeep_stats)

	_add_energy_stat(definition)

## User report (playtest round 6): "selecting a building should tell you
## what it does, e.g. brickworks produce X bricks per day, Iron Foundry
## produces X iron per day" — the same effective-output preview
## BuildMenuView._describe_effect() already shows BEFORE a building is
## placed, now shown for a real, already-placed instance too. Reads
## BuildingInstance.get_effective_output() (soil-fertility-scaled for farms,
## via BuildingManager.get_hex_cell()) rather than the flat
## definition.daily_output, so this can't disagree with what
## BuildingManager._compute_daily_totals() is actually crediting the colony
## today. ENERGY is a one-time grid draw/contribution, not a daily flow —
## handled separately by _add_energy_stat() below, same split
## _recurring_upkeep_display() already keeps.
func _add_production_stat(instance: BuildingInstance) -> void:
	var cell: HexCell = _building_manager.get_hex_cell(instance.hex_coord) if _building_manager else null
	var output := instance.get_effective_output(cell)
	var parts: Array[String] = []
	for resource_type in output:
		if resource_type == GameEnums.ResourceType.ENERGY:
			continue
		var amount := float(output[resource_type])
		if amount > 0.0:
			parts.append("+%s %s/day" % [String.num(amount, 1), ResourceVisuals.display_name(resource_type)])
	if parts.is_empty():
		return
	var production_stats := Label.new()
	production_stats.text = "Produces: %s" % ", ".join(parts)
	HUDStyles.style_label(production_stats)
	_list.add_child(production_stats)

## Adversarial code-review finding, HIGH severity (this pass's own
## verification step): a plain `definition.daily_upkeep` read left the
## Upkeep line silently missing for Terraced Tenement/Workhouse — this
## tree's only two housing types — because their real recurring cost
## (Food, proportional to population) is never written into daily_upkeep
## at all; BuildingManager._on_day_completed() instead computes it as a
## COLONY-WIDE aggregate (`total_population * FOOD_PER_POPULATION`, see
## that method's own `food_demand` line) entirely separately from the
## per-instance daily_upkeep loop. Folding that same formula in here
## (using `current_population`, what's ACTUALLY being paid for today, not
## `population_provided`'s baseline capacity — matching the "live state,
## not baseline" framing the Population/zombie lines above already use)
## is what actually makes "how much upkeep it costs" true for a housing
## building instead of silently implying it's free to run. Excludes
## ResourceType.ENERGY from `daily_upkeep` itself — see _add_energy_stat()
## for why that's shown as its own separate, distinctly-labeled line
## rather than folded in here as if it were a recurring cost.
func _recurring_upkeep_display(instance: BuildingInstance) -> String:
	var upkeep: Dictionary = {}
	for resource_type in instance.definition.daily_upkeep:
		if resource_type == GameEnums.ResourceType.ENERGY:
			continue
		upkeep[resource_type] = upkeep.get(resource_type, 0.0) + float(instance.definition.daily_upkeep[resource_type])
	if instance.current_population > 0:
		var food := GameEnums.ResourceType.FOOD
		upkeep[food] = upkeep.get(food, 0.0) + instance.current_population * BuildingManager.FOOD_PER_POPULATION
	return _format_upkeep(upkeep)

## User request ("please include energy in the building stats panel") — a
## deliberately separate line from "Upkeep: ... / day" above, not folded
## into it: BuildingDefinition.daily_upkeep/daily_output's own doc
## comments are explicit that an ENERGY entry in either dict is a ONE-TIME
## grid draw/contribution settled once at construction/repair
## (BuildingManager._apply_construction_energy()), never a recurring daily
## flow — labeling it "/ day" alongside genuine recurring costs would
## misstate what it actually does, the exact mistake _recurring_upkeep_display()
## above is careful to avoid. Shows whichever side actually applies (a
## consumer's draw or a producer's contribution — no building both draws
## and contributes today, but nothing here assumes that stays true).
func _add_energy_stat(definition: BuildingDefinition) -> void:
	var energy := GameEnums.ResourceType.ENERGY
	var draw := float(definition.daily_upkeep.get(energy, 0.0))
	var output := float(definition.daily_output.get(energy, 0.0))
	if draw <= 0.0 and output <= 0.0:
		return
	var energy_stats := Label.new()
	if output > 0.0:
		energy_stats.text = "Energy: +%s (one-time grid contribution)" % String.num(output, 1)
	else:
		energy_stats.text = "Energy: -%s (one-time grid draw)" % String.num(draw, 1)
	HUDStyles.style_label(energy_stats, false, true)
	_list.add_child(energy_stats)

## Dedicated formatter for the Upkeep line — HUDStyles.format_resource_dict()
## (used for training/retrain cost display, where every value is a whole
## number by design) trims trailing ".0" but still shows real precision for a
## genuinely fractional value, which would otherwise understate e.g. a
## Houses instance's real 1.2 Food/day (12 population *
## BuildingManager.FOOD_PER_POPULATION) as "1 Food" if truncated via int().
## One decimal place is exactly enough precision for every value this
## project's upkeep numbers ever take — a flat per-building constant, or
## population times the single FOOD_PER_POPULATION constant — without the
## noise of a full float.
func _format_upkeep(upkeep: Dictionary) -> String:
	var text := ""
	var first := true
	for resource_type in upkeep:
		if not first:
			text += ", "
		text += "%s %s" % [String.num(float(upkeep[resource_type]), 1), ResourceVisuals.display_name(resource_type)]
		first = false
	return text

func _render_wall_panel(segment: WallSegment) -> void:
	_clear_list()
	var header := Label.new()
	header.text = "Wall segment%s%s" % [" (Gate)" if segment.is_gate else "", " (BREACHED)" if segment.is_breached() else ""]
	HUDStyles.style_label(header, true)
	_list.add_child(header)

	var tier_name := WallCatalog.get_display_name(segment.tier)
	var stats := Label.new()
	stats.text = "%s — HP %d/%d" % [tier_name, int(segment.current_hp), int(segment.get_max_hp())]
	HUDStyles.style_label(stats)
	_list.add_child(stats)

	_add_repair_button(
		segment.is_breached(),
		func() -> String: return _unit_command_controller.get_selected_wall_repair_error(),
		_unit_command_controller.repair_selected_wall
	)
	_add_demolish_button(
		func() -> String: return _unit_command_controller.get_selected_wall_demolish_error(),
		_unit_command_controller.demolish_selected_wall
	)

## Shared by both panels above — a Repair button only even APPEARS once the
## thing is actually damaged enough to repair (`is_ruined`/`is_breached()`,
## matching BuildingManager.get_repair_error()/WallManager.get_repair_error()'s
## own first check each), disabled with the real rejection reason as a
## tooltip otherwise (same queryable-rejection convention as every other
## action button in this view).
func _add_repair_button(is_damaged: bool, error_getter: Callable, repair_action: Callable) -> void:
	if not is_damaged or not _unit_command_controller:
		return
	var button := Button.new()
	button.text = "Repair"
	var error: String = error_getter.call()
	button.disabled = not error.is_empty()
	button.tooltip_text = error if not error.is_empty() else "Repair this."
	button.pressed.connect(func() -> void: repair_action.call())
	HUDStyles.style_button(button)
	_list.add_child(button)

## User request ("there should also be a demolish button on every building
## (and wall) where you get 50% of the resources used to build it back
## except energy where you always get 100%..."). Unlike Repair (only even
## appears once something is actually damaged), Demolish is always shown —
## "every building (and wall)", not just damaged ones — disabled with the
## real rejection reason as a tooltip when it doesn't apply right now
## (today, only a ruin sitting in still-contested territory), same
## queryable-rejection convention _add_repair_button() above already
## follows. No confirmation dialog — this project has no such UI pattern
## anywhere else to reuse, and the action is framed as a refund, not a
## pure loss.
## `full_refund` (user report: "you get 100% of your resources back if you
## manage to demolish a building thats not yet built") — only ever true for
## an under-construction building (see BuildingManager.demolish_building()'s
## own doc comment); every other caller (a finished building, or a wall,
## which has no construction-site concept at all) leaves it at the existing
## partial-refund default.
func _add_demolish_button(error_getter: Callable, demolish_action: Callable, full_refund: bool = false) -> void:
	if not _unit_command_controller:
		return
	var button := Button.new()
	button.text = "Demolish"
	var error: String = error_getter.call()
	button.disabled = not error.is_empty()
	if not error.is_empty():
		button.tooltip_text = error
	else:
		button.tooltip_text = "Demolish this for a full refund." if full_refund else "Demolish this for a partial refund."
	button.pressed.connect(func() -> void: demolish_action.call())
	HUDStyles.style_button(button)
	_list.add_child(button)

func _on_train_pressed(coord: Vector2i, unit_type: GameEnums.UnitType) -> void:
	if _unit_command_controller:
		_unit_command_controller.train_at_selected_building(coord, unit_type)

func _render_unit_panel(instance: UnitInstance) -> void:
	_clear_list()
	var definition := instance.definition

	var header := Label.new()
	header.text = "%s (T%d %s)" % [definition.display_name, definition.tier, _role_name(definition.role)]
	HUDStyles.style_label(header, true)
	_list.add_child(header)

	var stats := Label.new()
	stats.text = "HP %d/%d — %s — %s" % [int(instance.current_hp), int(definition.max_hp), _rank_name(UnitMorale.get_rank(instance)), _order_name(instance.order)]
	HUDStyles.style_label(stats)
	_list.add_child(stats)

	# User request (playtest round 5): "a selected unit should display any
	# move commands it is currently obeying and any patrol waypoints it has
	# set" — a dedicated line under the HP/order summary above, not just
	# "Moving"/"Patrolling" with no destination. Refreshed live off
	# UnitCommandController's own `unit_selected` re-emit whenever an order
	# actually changes (see that controller's own `_on_unit_order_issued()`
	# doc comment) — right-clicking a new destination updates this
	# immediately, not just at the moment of selection.
	var order_detail := _describe_current_order(instance)
	if not order_detail.is_empty():
		var order_label := Label.new()
		order_label.text = order_detail
		order_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		HUDStyles.style_label(order_label, false, true)
		_list.add_child(order_label)

	var hold_button := Button.new()
	hold_button.text = "Hold"
	hold_button.pressed.connect(_unit_command_controller.order_hold)
	HUDStyles.style_button(hold_button)
	_list.add_child(hold_button)

	var garrison_button := Button.new()
	garrison_button.text = "Garrison"
	garrison_button.pressed.connect(_unit_command_controller.order_garrison)
	HUDStyles.style_button(garrison_button)
	_list.add_child(garrison_button)

	if _unit_command_controller.is_recording_patrol():
		var recording_label := Label.new()
		recording_label.text = "Recording patrol — %d waypoint(s). Left-click the map to add, right-click/Esc to cancel." % _unit_command_controller.get_patrol_waypoint_count()
		HUDStyles.style_label(recording_label)
		_list.add_child(recording_label)
		var confirm_button := Button.new()
		confirm_button.text = "Confirm Patrol"
		confirm_button.disabled = _unit_command_controller.get_patrol_waypoint_count() == 0
		confirm_button.pressed.connect(_unit_command_controller.confirm_patrol_recording)
		HUDStyles.style_button(confirm_button)
		_list.add_child(confirm_button)
	else:
		var patrol_button := Button.new()
		patrol_button.text = "Patrol… (click waypoints on map)"
		patrol_button.pressed.connect(_unit_command_controller.begin_patrol_recording)
		HUDStyles.style_button(patrol_button)
		_list.add_child(patrol_button)

	var retrain_header := Label.new()
	retrain_header.text = "Retrain into:"
	HUDStyles.style_label(retrain_header, true)
	_list.add_child(retrain_header)
	# User report (playtest round 6): "remove 'retrain' options... if they
	# are not currently available to do. Only display retraining options
	# that are researched and can be purchased." Used to show EVERY
	# same-role/higher-tier candidate, disabled-with-a-reason when
	# tech-locked or unaffordable; now a candidate that fails
	# get_retrain_error() for any reason is skipped entirely rather than
	# shown greyed out. `any_higher_tier_exists` (role/tier check alone)
	# vs. `any_retrain_available` (also passed get_retrain_error()) are
	# tracked separately so the empty-state message can still tell "this
	# is genuinely the top tier" apart from "a higher tier exists but isn't
	# unlocked/affordable yet" instead of collapsing both into one
	# ambiguous "(top tier for this role)" like before.
	var any_retrain_available := false
	var any_higher_tier_exists := false
	var retrain_grid := GridContainer.new()  # Same card shape as the training grid above — see its own comment.
	retrain_grid.columns = 2
	retrain_grid.add_theme_constant_override("h_separation", 6)
	retrain_grid.add_theme_constant_override("v_separation", 6)
	for candidate in UnitCatalog.get_all_definitions():
		if candidate.role != definition.role or candidate.tier <= definition.tier:
			continue
		any_higher_tier_exists = true
		var error := _unit_manager.get_retrain_error(instance, candidate.unit_type) if _unit_manager else "No UnitManager wired."
		if not error.is_empty():
			continue
		any_retrain_available = true
		var details := "Cost: %s" % HUDStyles.format_resource_dict(_retrain_preview_cost(candidate))
		retrain_grid.add_child(HUDStyles.build_card(
			"%s (T%d)" % [candidate.display_name, candidate.tier],
			UnitVisuals.unit_texture(candidate.unit_type),
			details,
			_on_retrain_pressed.bind(candidate.unit_type),
			true,
			110.0, 36.0,
		))
	if any_retrain_available:
		_list.add_child(retrain_grid)
	else:
		var none_label := Label.new()
		none_label.text = "(higher tier not yet available — check research/resources)" if any_higher_tier_exists else "(top tier for this role)"
		HUDStyles.style_label(none_label)
		_list.add_child(none_label)

func _on_retrain_pressed(unit_type: GameEnums.UnitType) -> void:
	if _unit_command_controller:
		_unit_command_controller.retrain_selected(unit_type)

func _retrain_preview_cost(definition: UnitDefinition) -> Dictionary:
	var cost: Dictionary = {}
	for resource_type in definition.training_cost:
		cost[resource_type] = float(definition.training_cost[resource_type]) * UnitManager.RETRAIN_COST_FRACTION
	return cost

## "how much it costs and the upkeep" (user request, #8) — training cost is
## one-time (UnitManager.train_unit()'s own spend), daily_upkeep is the
## recurring Gunpowder drain (UnitDefinition.daily_upkeep's own doc
## comment); shown as two separate lines for the same "one-time vs
## recurring" clarity BuildMenuView's own card details already keep for
## buildings (construction cost vs. daily upkeep).
func _unit_card_details(definition: UnitDefinition) -> String:
	var text := "Cost: %s" % HUDStyles.format_resource_dict(definition.training_cost)
	var upkeep := HUDStyles.format_resource_dict(definition.daily_upkeep)
	if not upkeep.is_empty():
		text += "\nUpkeep: %s/day" % upkeep
	return text

func _role_name(role: GameEnums.UnitRole) -> String:
	match role:
		GameEnums.UnitRole.MELEE:
			return "Melee"
		GameEnums.UnitRole.RANGED:
			return "Ranged"
		GameEnums.UnitRole.SPECIAL:
			return "Special"
		_:
			return "?"

func _rank_name(rank: UnitMorale.Rank) -> String:
	match rank:
		UnitMorale.Rank.ELITE:
			return "Elite"
		UnitMorale.Rank.VETERAN:
			return "Veteran"
		_:
			return "Rookie"

func _order_name(order: GameEnums.UnitOrderType) -> String:
	match order:
		GameEnums.UnitOrderType.MOVE:
			return "Moving"
		GameEnums.UnitOrderType.ATTACK_MOVE:
			return "Attack-Moving"
		GameEnums.UnitOrderType.PATROL:
			return "Patrolling"
		GameEnums.UnitOrderType.GARRISON:
			return "Garrisoned"
		_:
			return "Holding"

## "any move commands it is currently obeying and any patrol waypoints it
## has set" (user request, playtest round 5) — MOVE/ATTACK_MOVE shows the
## real destination hex; PATROL shows the FULL waypoint loop with the
## currently-active leg marked, so the player can see the whole route, not
## just where it's headed right now. Empty string for HOLD/GARRISON (no
## destination to report — _render_unit_panel() skips the line entirely
## rather than showing a blank one).
func _describe_current_order(instance: UnitInstance) -> String:
	match instance.order:
		GameEnums.UnitOrderType.MOVE, GameEnums.UnitOrderType.ATTACK_MOVE:
			return "Destination: %s" % instance.move_target
		GameEnums.UnitOrderType.PATROL:
			if not instance.has_patrol_waypoints():
				return ""
			var legs: Array[String] = []
			for i in range(instance.patrol_waypoints.size()):
				var text := "%s" % instance.patrol_waypoints[i]
				if i == instance.patrol_target_index:
					text = "[%s]" % text  ## The leg currently being walked toward.
				legs.append(text)
			return "Patrol route: %s" % " → ".join(legs)
		_:
			return ""
