class_name AlertTones
extends RefCounted

## Code-synthesized UI/alert tones (design doc Phase 6.2 cross-reference from
## Phase 2.5.7's grilling-session decision: "synthesize it in code for now,
## self contained no dependency"). No audio assets exist anywhere in this
## project — every tone here is raw PCM data generated at runtime and handed
## back as a ready-to-play AudioStreamWAV, the same "code-drawn placeholder,
## swappable for real assets later" convention every `*Visuals.gd` color
## lookup already follows for graphics. Stateless static utility, same shape
## as BuildingVisuals/TerrainVisuals: pure functions in, a Resource out,
## nothing here owns a Node, a Player, or references any manager — a caller
## builds the stream once (e.g. in _ready()) and assigns it to its own
## AudioStreamPlayer.

const _MIX_RATE := 44100
const _AMPLITUDE := 0.35  ## Headroom below full scale — this plays alongside everything else, not as a solo alarm.
const _FADE_FRACTION := 0.3  ## Final fraction of each note that linear-fades to silence, so the cut isn't an audible click.

## Short, low, two-note descending buzz — the negative/"can't do that"
## feedback used wherever a player action is rejected. First caller:
## BuildPlacementController (2.5.7's "can't place while zoomed out" nudge,
## and BuildingManager.placement_rejected's existing reasons). Deliberately
## brief and unpleasant rather than a jarring alarm — this fires on ordinary
## misclicks, not a crisis; compare Phase 6.2's still-unbuilt siren-style
## alerts for actual threats.
static func negative_tone() -> AudioStreamWAV:
	return _build_tone([
		{"freq": 220.0, "duration": 0.09},
		{"freq": 155.0, "duration": 0.12},
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
