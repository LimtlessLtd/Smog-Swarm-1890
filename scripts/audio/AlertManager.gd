class_name AlertManager
extends Node

## Design doc Phase 6.2's "Audio & Desktop Notification Alert System" — the
## consumer that turns EventManager's typed queue into something the player
## actually notices: a synthesized chime (AlertTones) and — the real point
## of it, for a game that spends most of its time running at up to 1000x —
## auto-pausing the simulation (TickManager.set_speed_index(0), the same
## "0x" tier the speed buttons already use) so nothing serious rolls past
## unnoticed while the player's away. MainHUD's own toast plumbing is an
## independent second listener on the same EventManager.event_raised signal
## — this class doesn't reach into the HUD, same "multiple independent
## listeners off one signal" precedent BuildingManager.civilians_starved
## already has (DiscontentManager + HordeManager, neither aware of the
## other).
##
## **Decided (matches the design doc's own enumerated auto-pause trigger
## list, not just the headline "wall breach" case):** every event severity
## above INFO auto-pauses — GameEnums.EventSeverity.WARNING (a unit takes a
## hit and survives, food dips under 100%, a resource stockpile hits zero)
## equally with CRITICAL (a unit/building destroyed, a wall breached,
## territory lost, a large horde spotted, starvation). INFO (territory
## recaptured, today's only INFO source) is deliberately exempt — good news
## doesn't need to interrupt play. Not spammy in practice: EventManager
## itself already collapses each of these to "fires once per meaningful
## transition" (a threshold newly crossed, a one-shot combat contact, a
## fresh breach) rather than re-raising every tick a condition merely
## persists — see EventManager's own doc comment for exactly which signal
## backs which event.
##
## Desktop OS-level notifications (the class name's other half) are NOT
## implemented — Godot has no cross-platform "toast in the system tray" API
## without a third-party plugin, and this project has no such dependency
## anywhere else. In-app is the whole notification surface today (the audio
## + auto-pause here, the visible toast in MainHUD, the pulsing map marker
## in StrategicOverlayManager) — genuinely sufficient for a windowed desktop
## game the player is looking at, not a stand-in for a future OS integration
## that isn't otherwise planned.
##
## Sunset/sunrise chimes ("Church bell toll"/"rooster call" at the design
## doc's own 2-minute mark) poll TimeCycleManager once a second — no
## "N seconds before a phase flip" signal exists to hang a one-shot callback
## off directly. Each direction has its own "armed" flag so the chime fires
## exactly once per approach: crossing into Day re-arms the sunset warning
## (there's a fresh nightfall ahead to warn about), crossing into Night
## re-arms the sunrise warning, symmetrically.
##
## **Real-time cooldown on top of that (user request, this pass):** the
## "once per approach" gate above is correct in GAME time, but at high
## TickManager speeds a whole 40-minute day compresses into a few real
## seconds (2.4s at 1000x) — sunset and sunrise then legitimately alternate
## fast enough to sound like a near-continuous chime. `_try_play_chime()`
## additionally floors how often a chime can actually SOUND to once per
## `CHIME_MIN_REAL_INTERVAL_MS`, measured against `Time.get_ticks_msec()`
## (real OS time, deliberately NOT `TickManager`/game time — unaffected by
## Engine.time_scale, unlike everything else in this class) — a legitimate
## new crossing while still on cooldown just plays no sound at all rather
## than queuing or delaying one; the "armed" flags above are untouched by
## this, so the very next crossing after cooldown still gets checked fresh.
## Scoped to these two chimes only — EventManager-driven alert tones
## (_on_event_raised(), below) are a different, higher-stakes category
## (they gate auto-pause) and stay unthrottled.

@export var event_manager_path: NodePath

const NIGHTFALL_WARNING_SECONDS: float = 120.0  ## Design doc's own "2-minute mark".
const PHASE_CHECK_INTERVAL_SECONDS: float = 1.0
const CHIME_MIN_REAL_INTERVAL_MS: int = 30000  ## User request: day/night alarms shouldn't sound more than once every 30 real-world seconds, however fast the in-game clock is running.

var _tone_player: AudioStreamPlayer
var _sunset_chime_armed: bool = true
var _sunrise_chime_armed: bool = true
var _last_chime_real_ms: int = -CHIME_MIN_REAL_INTERVAL_MS  ## Negative headroom so the very first chime of a session is never suppressed by the cooldown.

## User request ("remove all the sounds for now") — every AudioStreamPlayer
## in this project (this class's own `_tone_player`, plus
## BuildPlacementController's and WallPlacementController's own
## `_reject_player`) plays on the default "Master" bus; none of the three
## ever set `.bus` to anything else. Muting that one bus here, once, at
## boot silences all of them centrally without deleting AlertTones' own
## tone-synthesis code or touching those two other files at all — every
## `_play()`/`.play()` call site keeps running exactly as before, it just
## produces no audible sound. Deliberately NOT deleting the code (the
## report's own "for now" framing) — flip this back off and every existing
## call site works again unchanged. See BackgroundExecutionManager's own
## doc comment for why bus-muting as a concept already has precedent in
## this project (it explicitly does NOT do this while unfocused, for a
## different reason — simulation/audio staying "live" in the background —
## this is an unconditional, always-on mute instead, not tied to focus).
const _MUTE_ALL_SOUND: bool = true

func _ready() -> void:
	# Same reasoning as TickManager/TimeCycleManager: keep watching for
	# phase-warning chimes even across a future SceneTree pause — this is
	# background-alerting infrastructure, not gameplay that should freeze.
	process_mode = Node.PROCESS_MODE_ALWAYS

	if _MUTE_ALL_SOUND:
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)

	_tone_player = AudioStreamPlayer.new()
	add_child(_tone_player)

	if event_manager_path != NodePath():
		var event_manager: EventManager = get_node(event_manager_path)
		event_manager.event_raised.connect(_on_event_raised)

	TimeCycleManager.phase_changed.connect(_on_phase_changed)

	var phase_timer := Timer.new()
	phase_timer.wait_time = PHASE_CHECK_INTERVAL_SECONDS
	phase_timer.autostart = true
	add_child(phase_timer)
	phase_timer.timeout.connect(_check_phase_warnings)

func _on_event_raised(event: GameEvent) -> void:
	_play(AlertTones.critical_tone() if event.severity == GameEnums.EventSeverity.CRITICAL else AlertTones.warning_tone())
	if event.severity != GameEnums.EventSeverity.INFO and TickManager.speed_index != 0:
		TickManager.set_speed_index(0)

func _check_phase_warnings() -> void:
	if TimeCycleManager.is_day():
		if _sunset_chime_armed and TimeCycleManager.get_seconds_until_nightfall() <= NIGHTFALL_WARNING_SECONDS:
			_try_play_chime(AlertTones.sunset_chime())
			_sunset_chime_armed = false
	else:
		if _sunrise_chime_armed and TimeCycleManager.get_seconds_until_dawn() <= NIGHTFALL_WARNING_SECONDS:
			_try_play_chime(AlertTones.sunrise_chime())
			_sunrise_chime_armed = false

## See this class's own doc comment for why this real-time floor exists on
## top of the (game-time) "armed" gate — a no-op if we're still within
## CHIME_MIN_REAL_INTERVAL_MS of the last chime that actually sounded.
func _try_play_chime(stream: AudioStreamWAV) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_chime_real_ms < CHIME_MIN_REAL_INTERVAL_MS:
		return
	_last_chime_real_ms = now
	_play(stream)

func _on_phase_changed(phase: GameEnums.DayPhase) -> void:
	if phase == GameEnums.DayPhase.DAY:
		_sunset_chime_armed = true   # Freshly dawned — re-arm for the coming nightfall's own warning.
	else:
		_sunrise_chime_armed = true  # Freshly dusked — re-arm for the coming dawn's own warning.

func _play(stream: AudioStreamWAV) -> void:
	_tone_player.stream = stream
	_tone_player.play()
