shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, ambient_light_disabled, fog_disabled, blend_add;

uniform sampler2D curtain_data : filter_nearest, hint_default_black;
uniform float data_width = 1.0;
varying float v_instance_id;
varying float v_ang_u;
varying float v_v;

vec3 aurora(float p) {
	vec3 s0 = vec3(0.15, 0.95, 0.35);
	vec3 s1 = vec3(0.20, 0.90, 0.80);
	vec3 s2 = vec3(0.25, 0.45, 1.0);
	vec3 s3 = vec3(0.55, 0.25, 0.95);
	float seg = clamp(p, 0.0, 0.999) * 4.0;
	float i = floor(seg);
	float f = seg - i;
	vec3 a = s0;
	vec3 b = s1;
	if (i < 0.5) { a = s0; b = s1; }
	else if (i < 1.5) { a = s1; b = s2; }
	else if (i < 2.5) { a = s2; b = s3; }
	else { a = s3; b = s0; }
	return mix(a, b, f);
}

void vertex() {
	v_instance_id = float(INSTANCE_ID);
	v_ang_u = VERTEX.z;
	v_v = UV.y;
	float u = (v_instance_id + 0.5) / max(data_width, 1.0);
	vec4 p0 = texture(curtain_data, vec2(u, 0.16666667));
	vec4 p1 = texture(curtain_data, vec2(u, 0.5));
	vec4 p2 = texture(curtain_data, vec2(u, 0.83333333));
	float vis = p0.w;
	// p0.z = seam angle; p2.w = gap half-angle (transparent interval)
	float ah = max(p2.w, 0.004);
	float ang = p0.z + VERTEX.z * ah;
	float inner = p1.x;
	float outer = p1.y;
	float h0 = p1.z;
	float h1 = p1.w;
	float r = mix(inner, outer, UV.x);
	float t = clamp(UV.y, 0.0, 1.0);
	float y = mix(h0, h1, t);
	if (vis < 0.5) {
		VERTEX = vec3(0.0, -999.0, 0.0);
	} else {
		VERTEX = vec3(sin(ang) * r, y, -cos(ang) * r);
	}
}

void fragment() {
	float u = (v_instance_id + 0.5) / max(data_width, 1.0);
	vec4 p0 = texture(curtain_data, vec2(u, 0.16666667));
	vec4 p2 = texture(curtain_data, vec2(u, 0.83333333));
	if (p0.w < 0.5) {
		discard;
	}
	float mode = p2.x;
	float phase = p2.y;
	float t = v_v;
	float fade = pow(sin(clamp(t, 0.0, 1.0) * 3.14159265), 2.8);
	float soft_u = 0.14;
	float rad_fade = smoothstep(0.0, soft_u, UV.x) * smoothstep(0.0, soft_u, 1.0 - UV.x);
	float ang_fade = 1.0 - smoothstep(0.55, 1.0, abs(v_ang_u));
	float a = fade * rad_fade * ang_fade;
	if (a < 0.01) {
		discard;
	}
	vec3 rgb;
	float base_a;
	if (mode < 0.5) {
		rgb = vec3(0.40, 0.70, 1.0);
		base_a = 0.50;
	} else if (mode < 1.5) {
		rgb = vec3(1.0, 0.90, 0.30);
		base_a = 0.50;
	} else {
		float p = fract(phase + t * 0.35);
		rgb = aurora(p);
		base_a = 0.58;
	}
	ALBEDO = rgb * (base_a * a);
	ALPHA = 1.0;
}
