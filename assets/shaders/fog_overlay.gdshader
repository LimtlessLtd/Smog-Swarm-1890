shader_type canvas_item;

// Animated fog/haze overlay drawn on top of a hex's ground (HexCellView, one
// per land hex, at FogVisuals.TERRAIN_OVERLAY_Z_INDEX) — replaces the old flat
// modulate-only fog tint with visible motion, per user request ("fog of war
// should be cloudy misty animations moving over an area to indicate to the
// user they have no vision there... obscured tiles need to have visibly
// different overlay animations"). One shader, two looks selected by
// `fog_mode` (FogVisuals.gd owns exactly two shared ShaderMaterial instances,
// one per mode, reused across every tile rather than one material per hex):
//   0 = UNSEEN  — dense, fast-drifting mist. Never-scouted: reads as thick
//       cloud cover, not just a dark tile.
//   1 = EXPLORED — sparse, slow-drifting haze, terrain still readable under it.
// No VISIBLE mode: FogVisuals.overlay_material() returns null for it, and
// callers simply don't add/show this overlay there at all.
//
// THIS SHADER'S ALPHA IS THE ONLY THING HIDING THE TERRAIN. It used to lean on
// the hex view's own `modulate` to do the darkening and only add motion on top,
// which stopped working the moment terrain moved to TerrainMeshView: that mesh
// is a single world-wide layer, not a child of any hex, so no per-hex modulate
// can reach it. It also never worked the way that comment claimed even for the
// hex's own tile — assigning COLOR unconditionally in fragment() discards the
// vertex color Godot folds `modulate` into, so this overlay was ALWAYS drawing
// at full strength regardless of the tint on the node above it.
//
// Hence: UNSEEN is fully opaque (the noise varies the cloud's COLOR, never its
// alpha), and EXPLORED has an alpha FLOOR rather than fading to nothing where
// the noise happens to be thin. Alpha that dips toward 0 is exactly how the
// whole baked corridor stayed legible at day 1 through "unseen" fog.

uniform int fog_mode = 0;

// Scales the final alpha. 1.0 for land, where the fog's job is to hide.
// SeaView uses a lower value: where the sea is, is public knowledge (the same
// reasoning CoastlineOutlineView records for drawing the coastline through
// fog), so its haze only needs to stop unexplored water reading brighter than
// the explored land beside it. Applied as a multiply rather than a separate
// shader so land and sea cannot drift apart in look.
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

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
	float n = clamp(drifting_fbm(uv, TIME * speed), 0.0, 1.0);

	// The noise drives COLOR, between a cloud-shadow tone and a lit-mist one.
	// UNSEEN's shadow is near-black rather than black so thick cloud still
	// reads as cloud rather than as a hole punched in the map.
	vec3 shadow = fog_mode == 0 ? vec3(0.05, 0.06, 0.07) : vec3(0.0);
	vec3 mist_color = fog_mode == 0 ? vec3(0.72, 0.75, 0.78) : vec3(0.5, 0.53, 0.56);

	// EXPLORED_FLOOR reproduces exactly what FogVisuals.tint_color(EXPLORED)'s
	// 0.45 multiply used to do to the tile beneath (1.0 - 0.45), so remembered
	// terrain keeps the brightness it had before this overlay took over the
	// darkening; the noise only thickens the haze from there.
	float alpha = fog_mode == 0 ? 1.0 : mix(0.55, 0.75, n);
	COLOR = vec4(mix(shadow, mist_color, n), alpha * opacity);
}
