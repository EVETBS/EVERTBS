shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D territory_tex : source_color, filter_linear, repeat_disable;
uniform float fill_a = 0.05;
uniform float border_a = 0.2;

void fragment() {
	vec4 t = texture(territory_tex, UV);
	if (t.a < 0.02) {
		discard;
	}
	// Packed A: ~0.25 fill, ~1.0 border (see TerritoryBaker).
	float fill_w = clamp((0.55 - abs(t.a - 0.25)) * 4.0, 0.0, 1.0);
	float border_w = smoothstep(0.45, 0.85, t.a);
	float a = fill_w * fill_a + border_w * border_a;
	if (a < 0.001) {
		discard;
	}
	ALBEDO = t.rgb;
	ALPHA = a;
}
