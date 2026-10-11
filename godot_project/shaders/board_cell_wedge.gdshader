shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, ambient_light_disabled, fog_disabled, blend_mix;

// INSTANCE_CUSTOM (0..1 pack): a0/TAU, span/TAU, inner/r_scale, outer/r_scale
// cell_data rows: 1=work/show, 2=fill, 3=edge (RGBAF)
uniform sampler2D cell_data : filter_nearest, hint_default_black;
uniform float data_width = 1.0;
uniform float rim_thick = 0.70;
uniform float r_scale = 64.0;
uniform int is_rim = 0;

varying float v_instance_id;

void vertex() {
	v_instance_id = float(INSTANCE_ID);
	float TAU_F = 6.28318530718;
	float a0 = INSTANCE_CUSTOM.x * TAU_F;
	float a1 = a0 + INSTANCE_CUSTOM.y * TAU_F;
	float inner = INSTANCE_CUSTOM.z * r_scale;
	float outer = INSTANCE_CUSTOM.w * r_scale;
	float ang = mix(a0, a1, UV.x);
	float r;
	float y;
	if (is_rim == 1) {
		r = mix(outer, outer + rim_thick, UV.y);
		y = 0.03;
	} else {
		r = mix(inner, outer, UV.y);
		y = 0.02;
	}
	if (outer < 0.05 || INSTANCE_CUSTOM.y < 0.0001) {
		VERTEX = vec3(0.0, -9999.0, 0.0);
	} else {
		VERTEX = vec3(sin(ang) * r, y, -cos(ang) * r);
	}
}

void fragment() {
	float id = v_instance_id;
	float u = (id + 0.5) / max(data_width, 1.0);
	vec4 p1 = texture(cell_data, vec2(u, 0.375));
	vec4 fill = texture(cell_data, vec2(u, 0.625));
	vec4 edge = texture(cell_data, vec2(u, 0.875));
	float work_n = p1.z;
	float show = p1.w;
	float arc_t = UV.x;
	float rad_t = UV.y;
	if (show < 0.5) {
		ALPHA = 0.0;
		ALBEDO = vec3(0.0);
	} else {
		if (length(fill.rgb) < 0.001) {
			fill = vec4(0.45, 0.55, 0.75, 0.70);
			edge = vec4(1.0);
			work_n = 1.0;
		}
		if (is_rim == 1) {
			float spread = 1.0 - work_n;
			float from_mid = abs(arc_t - 0.5) * 2.0;
			ALBEDO = (work_n >= 0.999 || from_mid <= spread) ? edge.rgb : vec3(1.0);
			ALPHA = 1.0;
		} else {
			ALBEDO = mix(fill.rgb * 0.55, fill.rgb, rad_t);
			ALPHA = mix(0.0, min(fill.a, 0.70), rad_t);
		}
	}
}