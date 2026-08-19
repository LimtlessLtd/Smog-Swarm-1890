shader_type canvas_item;

// Turns a baked greyscale relief tile into light and shadow.
//
// The tiles bake_fine_relief.py writes are a single channel: 128 is flat
// ground, above it is lit, below it is shadowed. Drawing that directly would
// wash the map grey, and the two blend modes that would work on it natively
// are both wrong here -- MUL darkens everything by half because neutral is
// 0.5, and MIX paints flat grey over terrain that should be untouched.
//
// So neutral becomes fully TRANSPARENT and only the departure from it is
// drawn: shadow toward `shadow_color`, light toward `light_color`, alpha
// proportional to how far from flat the pixel is. Flat ground therefore
// renders as literally nothing, and only real slopes modulate the terrain art
// underneath.
//
// Done on the GPU rather than by rebuilding each tile as RGBA on load: a tile
// is 333x333, tiles stream in as the camera pans, and per-pixel conversion in
// GDScript measured around a quarter of a second per tile -- a visible hitch
// per tile, for work a fragment shader does for free.
//
// Note the texture is sampled as .r, not as a luminance: an 8-bit greyscale
// PNG loads with its single channel replicated, so .r is the shade value.

// Scales the whole effect. Exposed so the strategic-zoom fallback layer and
// the tactical fine tiles can be balanced against each other without two
// shaders, and so the user can be given a strength slider later without
// touching the bake.
uniform float strength : hint_range(0.0, 2.0) = 1.0;

// Deliberately not pure black/white. Terrain shading that goes to black reads
// as a hole rather than as a shaded slope, and pure white blows out the biome
// texture underneath; a cool shadow and a warm light also do more to suggest a
// sun direction than a neutral pair would.
uniform vec3 shadow_color = vec3(0.05, 0.07, 0.12);
uniform vec3 light_color = vec3(1.0, 0.98, 0.92);

// Asymmetric because the eye reads darkening as depth more readily than it
// reads brightening, so an equal pair looks top-heavy in the highlights.
uniform float shadow_gain : hint_range(0.0, 1.0) = 0.55;
uniform float light_gain : hint_range(0.0, 1.0) = 0.38;

void fragment() {
	float shade = texture(TEXTURE, UV).r;
	// Signed departure from flat: -1 fully shadowed, 0 flat, +1 fully lit.
	float signed_shade = (shade - 0.5) * 2.0;
	bool lit = signed_shade >= 0.0;
	float magnitude = abs(signed_shade);
	vec3 tint = lit ? light_color : shadow_color;
	float gain = lit ? light_gain : shadow_gain;
	COLOR = vec4(tint, magnitude * gain * strength);
}
