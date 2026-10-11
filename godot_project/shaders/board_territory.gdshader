shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix;

uniform vec4 albedo : source_color = vec4(0.75, 0.75, 0.78, 0.05);
uniform float edge_base : hint_range(0.7, 0.98) = 0.90;
uniform float jagged : hint_range(0.0, 0.25) = 0.12;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	vec2 p = v_uv * 2.0 - 1.0;
	float d = length(p);
	float ang = atan(p.y, p.x);
	// Irregular coastal boundary (multi-frequency).
	float n = sin(ang * 5.0) * 0.45 + sin(ang * 11.0 + 1.7) * 0.30 + sin(ang * 3.0 - 0.4) * 0.25
		+ sin(ang * 17.0 + 2.1) * 0.15;
	float rmax = edge_base + jagged * n;
	if (d > rmax) {
		discard;
	}
	// Sharp rim (narrow AA), interior solid alpha.
	float edge_a = 1.0 - smoothstep(rmax - 0.03, rmax, d);
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a * edge_a;
}
