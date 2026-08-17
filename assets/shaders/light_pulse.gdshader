shader_type canvas_item;
render_mode blend_add;  // Glows against the ground instead of drawing as a flat translucent dot — a ShaderMaterial's render_mode is the only way to get additive blending here, since a CanvasItem can only carry ONE `material` at a time and this shader already owns that slot.

// Slow alpha pulse for BuildingEffectsVisuals.build_light_glow() — a
// lit_at_night building (Gas Streetlamp, Watchtower, Searchlight Tower;
// same BuildingDefinition.lit_at_night field FogOfWarManager already reads
// for night vision) gets a soft glow that breathes instead of a static
// blob, "light animations... so they look that little bit more alive"
// (user request). GPU-driven via TIME, no per-frame GDScript/Tween needed —
// same pattern fog_overlay.gdshader already established for this project's
// other TIME-animated overlays.

uniform float pulse_speed = 1.5;
uniform float min_alpha = 0.35;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	float pulse = min_alpha + (1.0 - min_alpha) * (0.5 + 0.5 * sin(TIME * pulse_speed));
	COLOR = vec4(tex_color.rgb, tex_color.a * pulse);
}
