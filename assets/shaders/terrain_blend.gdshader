shader_type canvas_item;

// Real per-pixel gradient blend between a sub-hex ground cell's own texture
// (TEXTURE/UV, Sprite2D's normal binding) and a differing neighboring
// cell's texture (secondary_texture) — the actual answer to "terrain
// should blend smoothly across biome boundaries, we might need some sort
// of gradient" rather than SubHexGroundView's previous hard-edged sprite
// mosaic (still the base layer this shader sits on top of; a uniform
// interior cell gets blend_weight=0 and renders pixel-identical to before).
//
// SubHexGroundView.gd computes blend_weight/blend_direction/secondary_texture
// per sub-cell from its own already-sampled 7x7 real-terrain grid (how many
// of its 4-connected neighbors differ in biome, and which direction they
// sit in) — this shader only does the actual per-pixel color mixing, not
// the neighbor analysis.

uniform sampler2D secondary_texture: filter_nearest;
uniform float blend_weight: hint_range(0.0, 1.0) = 0.0;
uniform vec2 blend_direction = vec2(0.0, 0.0);  // unit vector (in UV space) pointing from this cell's center toward the dominant differing neighbor; zero vector = uniform full-strength blend, no directional bias.
uniform float blend_softness: hint_range(0.05, 1.0) = 0.5;  // how much of the cell's own far side stays fully un-blended before the gradient starts ramping in.

void fragment() {
	vec4 base_color = texture(TEXTURE, UV);
	// Godot's shader compiler rejects a plain `return` inside fragment()
	// ("Using 'return' in the 'fragment' processor function is incorrect")
	// — found live, not in any doc skimmed beforehand. Branch around the
	// blend work instead rather than early-exiting.
	if (blend_weight > 0.0) {
		vec4 secondary_color = texture(secondary_texture, UV);
		float mix_factor = blend_weight;
		if (blend_direction != vec2(0.0)) {
			// Project this pixel's offset from cell-center onto
			// blend_direction: 0 at the cell's far edge (away from the
			// differing neighbor), 1 at the near edge (toward it) — a real
			// spatial gradient, not a flat tint over the whole sub-cell.
			float edge_factor = clamp(dot(UV - vec2(0.5), blend_direction) + 0.5, 0.0, 1.0);
			mix_factor *= mix(1.0 - blend_softness, 1.0, edge_factor);
		}
		COLOR = mix(base_color, secondary_color, clamp(mix_factor, 0.0, 1.0));
	} else {
		COLOR = base_color;
	}
}
