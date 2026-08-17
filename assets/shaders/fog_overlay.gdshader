shader_type canvas_item;

// Animated fog/haze overlay drawn on top of a hex's ground (HexCellView for
// Strategic zoom, TacticalHexView for Tactical) — replaces the old flat
// modulate-only fog tint with visible motion, per user request ("fog of war
// should be cloudy misty animations moving over an area to indicate to the
// user they have no vision there... obscured tiles need to have visibly
// different overlay animations"). One shader, two looks selected by
// `fog_mode` (FogVisuals.gd owns exactly two shared ShaderMaterial instances,
// one per mode, reused across every tile rather than one material per hex):
//   0 = UNSEEN  — dense, fast-drifting mist. Never-scouted: reads as thick
//       cloud cover, not just a dark tile.
//   1 = EXPLORED — sparse, slow-drifting haze. Remembered terrain still
//       dimly visible underneath (HexCellView/TacticalHexView's own
//       modulate tint already darkens it) — this only needs to signal "no
//       LIVE vision right now", not hide the memory entirely.
// No VISIBLE mode: FogVisuals.overlay_material() returns null for it, and
// callers simply don't add/show this overlay there at all.

uniform int fog_mode = 0;

// Sampled in WORLD space (see vertex() below), not UV: the overlay Polygon2D
// this shader is assigned to has no texture, and an untextured Polygon2D
// with no explicit `uv` array reports the SAME degenerate UV at every
// vertex — every pixel then samples the noise field at one identical point,
// so the whole tile pulsed as one flat flickering color instead of showing
// any spatial cloud shape (a real user report: "just glowing or flashing
// grey to black... no clouds or mist"). World-space coordinates are real
// and continuous instead, with the added benefit that every hex's fog
// samples the SAME large noise field rather than each hex replaying an
// identical per-tile pattern — clouds actually drift seamlessly from one
// hex into its neighbor.
varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Cheap hash-based value noise — no texture asset needed, keeps this
// self-contained the way the rest of this project's procedural visuals are.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Three octaves, each drifting a bit faster than the last in the same
// direction — reads as layered moving cloud rather than one pattern
// flickering in place.
float drifting_fbm(vec2 p, float t) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		vec2 shift = vec2(t * 0.05, t * 0.025) * float(i + 1);
		value += amp * value_noise(p + shift);
		p *= 2.0;
		amp *= 0.5;
	}
	return value;
}

void fragment() {
	// 1 world unit isn't a useful noise frequency on its own (HexCoord.HEX_SIZE
	// is 512) — this scale puts roughly 5-6 noise cells across one hex's own
	// width, the same density the old (broken) UV*6.0 approach intended.
	vec2 uv = world_pos * 0.006;
	float speed = fog_mode == 0 ? 1.0 : 0.3;
	float density = fog_mode == 0 ? 0.95 : 0.45;
	vec3 mist_color = fog_mode == 0 ? vec3(0.72, 0.75, 0.78) : vec3(0.5, 0.53, 0.56);
	float n = drifting_fbm(uv, TIME * speed);
	COLOR = vec4(mist_color, clamp(n, 0.0, 1.0) * density);
}
