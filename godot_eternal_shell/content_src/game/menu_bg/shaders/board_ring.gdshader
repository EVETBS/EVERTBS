shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, ambient_light_disabled, fog_disabled, blend_mix;

uniform sampler2D sector_tex : filter_nearest, repeat_enable, hint_default_white;
uniform float row_v = 0.25;
uniform float fade_inner = 1.0;

void fragment() {
	vec4 c = texture(sector_tex, vec2(UV.x, row_v));
	if (c.a < 0.04) {
		discard;
	}
	ALBEDO = c.rgb;
	ALPHA = c.a * mix(1.0, UV.y, fade_inner);
}
