class_name AlertTones
extends RefCounted

## Code-synthesized UI/alert tones — "synthesize it in code for now, self
## contained no dependency" (user feedback). No audio assets exist anywhere
## in this project — every tone here is raw PCM data generated at runtime
## and handed back as a ready-to-play AudioStreamWAV, the same "code-drawn
## placeholder, swappable for real assets later" convention every
## *Visuals.gd color lookup follows for graphics. Stateless static utility,
## same shape as BuildingVisuals/TerrainVisuals: pure functions in, a
## Resource out, nothing here owns a Node, a Player, or references any
## manager — a caller builds the stream once (e.g. in _ready()) and
## assigns it to its own AudioStreamPlayer.

const _MIX_RATE := 44100
const _AMPLITUDE := 0.35  ## Headroom below full scale — this plays alongside everything else, not as a solo alarm.
const _FADE_FRACTION := 0.3  ## Final fraction of each note that linear-fades to silence, so the cut isn't an audible click.

## Short, low, two-note descending buzz — the negative/"can't do that"
## feedback used wherever a player action is rejected
## (BuildPlacementController's "can't place while zoomed out" nudge, and
## every BuildingManager.placement_rejected reason). Brief and unpleasant
## rather than a jarring alarm — this fires on ordinary misclicks, not a
## crisis; compare critical_tone() below for actual threats.
static func negative_tone() -> AudioStreamWAV:
	return _build_tone([
		{"freq": 220.0, "duration": 0.09},
		{"freq": 155.0, "duration": 0.12},
	])

## AlertManager's calmer, level double-beep for GameEnums.EventSeverity.WARNING
## world events (a unit takes a hit and survives, food dips under 100%, a
## resource stockpile runs dry). Distinct from negative_tone() above (a
## UI-rejection buzz, lower and harsher) and from critical_tone() below
## (this doesn't escalate in pitch) — a different context should sound
## different, not just louder.
static func warning_tone() -> AudioStreamWAV:
	return _build_tone([
		{"freq": 440.0, "duration": 0.1},
		{"freq": 440.0, "duration": 0.1},
	])

## The urgent counterpart for GameEnums.EventSeverity.CRITICAL world events
## (a wall breaches, a unit or building is destroyed, territory is lost, a
## large horde is spotted, the colony starves) — a three-note ascending
## alarm, the most insistent tone in this project, matching how much more
## it costs to miss one of these at 1000x game speed.
static func critical_tone() -> AudioStreamWAV:
	return _build_tone([
		{"freq": 330.0, "duration": 0.12},
		{"freq": 415.0, "duration": 0.12},
		{"freq": 523.0, "duration": 0.18},
	])

## The Nightfall countdown's own sound at its 2-minute warning mark: a
## slow, low two-toll approximation of a church bell toll. A code-
## synthesized square wave, not a sampled bell — same placeholder
## convention as every other tone here.
static func sunset_chime() -> AudioStreamWAV:
	return _build_tone([
		{"freq": 196.0, "duration": 0.4},
		{"freq": 196.0, "duration": 0.5},
	])

## The dawn counterpart — a bright ascending three-note warble
## approximating a rooster call, same placeholder convention.
static func sunrise_chime() -> AudioStreamWAV:
	return _build_tone([
		{"freq": 660.0, "duration": 0.08},
		{"freq": 880.0, "duration": 0.08},
		{"freq": 990.0, "duration": 0.14},
	])

static func _build_tone(segments: Array) -> AudioStreamWAV:
	var pcm := PackedByteArray()
	for segment in segments:
		pcm.append_array(_square_wave(segment["freq"], segment["duration"]))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = _MIX_RATE
	stream.stereo = false
	stream.data = pcm
	return stream

## A simple square wave (cheap, and reads as more of a "buzzer" than a pure
## sine — fitting for a rejection sound) with a linear fade-out over its
## final _FADE_FRACTION, encoded directly as signed 16-bit PCM frames.
static func _square_wave(freq: float, duration: float) -> PackedByteArray:
	var frame_count := int(_MIX_RATE * duration)
	var bytes := PackedByteArray()
	bytes.resize(frame_count * 2)  ## 16-bit mono = 2 bytes per frame.
	var fade_start := int(frame_count * (1.0 - _FADE_FRACTION))
	for i in range(frame_count):
		var t := float(i) / float(_MIX_RATE)
		var wave := 1.0 if sin(TAU * freq * t) >= 0.0 else -1.0
		var envelope := 1.0
		if i >= fade_start and frame_count > fade_start:
			envelope = 1.0 - float(i - fade_start) / float(frame_count - fade_start)
		var sample := int(clampf(wave * _AMPLITUDE * envelope, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, sample)
	return bytes
