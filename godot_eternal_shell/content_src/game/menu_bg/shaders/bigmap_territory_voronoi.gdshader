shader_type spatial;
// Closed link-faces: always fill. Outside faces: per-site influence.
// Constant-width stroke at faction junctions AND fill↔void boundary.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, world_vertex_coords;

uniform sampler2D site_pos_tex : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D site_col_tex : hint_default_white, filter_nearest, repeat_disable;
uniform sampler2D closed_mask_tex : hint_default_black, filter_linear, repeat_disable;
uniform int use_closed_mask = 0;
uniform int site_count = 0;
uniform vec4 cluster_center = vec4(0.0);
uniform float cluster_r = 80.0; // per-site influence radius outside closed faces
uniform float fill_a = 0.05;
uniform float border_a = 0.2;
uniform float border_w = 2.4;
uniform float jagged = 0.42;
uniform float edge_base = 0.92;
uniform float noise_scale = 1.0;
uniform vec2 quad_half = vec2(200.0, 200.0);
// Conservative candidate lists per grid cell (territory_site_grid.gd). Same results as full scans.
uniform int use_grid = 0;
uniform sampler2D grid_cell_tex : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D grid_list_tex : hint_default_black, filter_nearest, repeat_disable;
uniform vec2 grid_origin = vec2(0.0);
uniform float grid_cell = 40.0;
uniform ivec2 grid_dims = ivec2(1, 1);
uniform int grid_list_w = 2048;

varying vec3 v_wpos;

vec4 fetch_pos(int i) { return texelFetch(site_pos_tex, ivec2(i, 0), 0); }
vec4 fetch_col(int i) { return texelFetch(site_col_tex, ivec2(i, 0), 0); }
int fetch_list(int k) { return int(texelFetch(grid_list_tex, ivec2(k % grid_list_w, k / grid_list_w), 0).r + 0.5); }

float coast_noise(vec2 p, float ang) {
	return sin(ang * 5.0) * 0.45 + sin(ang * 11.0 + 1.7) * 0.30 + sin(ang * 3.0 - 0.4) * 0.25
		+ sin(ang * 17.0 + 2.1) * 0.15
		+ sin(p.x * 0.08 + p.y * 0.11) * 0.20 + sin(p.x * 0.19 - p.y * 0.07 + 0.9) * 0.15;
}
float seam_noise(vec2 p) {
	return sin(p.x * 0.22 + p.y * 0.17) * 0.40
		+ sin(p.x * 0.41 - p.y * 0.29 + 1.1) * 0.30
		+ sin((p.x + p.y) * 0.33 + 2.4) * 0.20
		+ sin(p.x * 0.09 - p.y * 0.48 + 0.6) * 0.25;
}

void vertex() { v_wpos = VERTEX; }

void fragment() {
	if (site_count <= 0) discard;
	float ns = max(noise_scale, 0.0001);
	vec2 p = v_wpos.xz;
	vec2 pn = p * ns;
	vec2 cc = cluster_center.xz;
	vec2 local = abs(p - cc);
	if (local.x > max(quad_half.x - 6.0 / ns, 1.0) || local.y > max(quad_half.y - 6.0 / ns, 1.0)) discard;

	float in_closed = 0.0;
	float closed_edge_dist = 1e10;
	if (use_closed_mask > 0) {
		vec2 uv = (p - cc) / max(quad_half * 2.0, vec2(0.001)) + vec2(0.5);
		if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
			vec4 m = texture(closed_mask_tex, uv);
			in_closed = m.r;
			// G stores world distance to closed-face boundary, packed / 256.
			closed_edge_dist = m.g * 256.0;
		}
	}

	int a_off = 0;
	int a_cnt = site_count;
	int b_off = 0;
	int b_cnt = site_count;
	if (use_grid > 0) {
		ivec2 gc = clamp(ivec2(floor((p - grid_origin) / grid_cell)), ivec2(0), grid_dims - ivec2(1));
		vec4 g = texelFetch(grid_cell_tex, gc, 0);
		a_off = int(g.r + 0.5);
		a_cnt = int(g.g + 0.5);
		b_off = int(g.b + 0.5);
		b_cnt = int(g.a + 0.5);
	}

	float best0 = 1e20;
	int bi0 = 0;
	vec2 p0 = vec2(0.0);
	for (int k = 0; k < 512; k++) {
		if (k >= a_cnt) break;
		int i = use_grid > 0 ? fetch_list(a_off + k) : k;
		vec2 sp = fetch_pos(i).xz;
		float d = distance(p, sp);
		if (d < best0) {
			best0 = d;
			bi0 = i;
			p0 = sp;
		}
	}

	float ang = atan((p - p0).y, (p - p0).x);
	float coast = coast_noise(pn, ang);
	float reach = cluster_r * (edge_base + jagged * 0.18 * coast);
	reach = max(reach, cluster_r * 0.82);

	bool filled = in_closed > 0.5 || best0 <= reach;
	if (!filled) discard;

	float warp = jagged * 28.0 / ns;
	vec2 pw = p + warp * vec2(seam_noise(pn), seam_noise(pn + vec2(23.0, -11.0)));

	float best = 1e20;
	int bi = 0;
	vec2 p_best = vec2(0.0);
	for (int k = 0; k < 512; k++) {
		if (k >= b_cnt) break;
		int i = use_grid > 0 ? fetch_list(b_off + k) : k;
		vec2 sp = fetch_pos(i).xz;
		float d = distance(pw, sp);
		if (d < best) {
			best = d;
			bi = i;
			p_best = sp;
		}
	}
	float fac = fetch_pos(bi).w;
	vec3 rgb = fetch_col(bi).rgb;
	float a = fill_a;

	// Soft fade only on influence silhouette (closed interiors stay solid).
	if (in_closed <= 0.5) {
		float outer_edge = reach - best0;
		if (outer_edge < border_w * 1.4) {
			a *= mix(0.35, 1.0, clamp(outer_edge / max(border_w * 1.4, 0.001), 0.0, 1.0));
		}
	}

	float half_w = border_w * 0.5;
	float aa = max(border_w * 0.08, 0.05);
	float stroke = 0.0;

	// 1) Faction color junctions — constant world width.
	if (border_a > 0.001) {
		float second_diff = 1e20;
		vec2 p_second = p_best;
		for (int k = 0; k < 512; k++) {
			if (k >= b_cnt) break;
			int j = use_grid > 0 ? fetch_list(b_off + k) : k;
			if (abs(fetch_pos(j).w - fac) < 0.5) continue;
			vec2 sj = fetch_pos(j).xz;
			float d = distance(pw, sj);
			if (d < second_diff) {
				second_diff = d;
				p_second = sj;
			}
		}
		if (second_diff < 1e19) {
			vec2 n1 = (pw - p_best) / max(best, 1e-4);
			vec2 n2 = (pw - p_second) / max(second_diff, 1e-4);
			float grad = max(length(n2 - n1), 1e-3);
			float dist_to_edge = (second_diff - best) / grad;
			stroke = max(stroke, 1.0 - smoothstep(half_w - aa, half_w + aa, dist_to_edge));
		}
	}

	// 2) Fill ↔ void junction.
	// Influence rim always; closed-face edge only where exterior is colorless (not covered by influence).
	if (border_a > 0.001) {
		float void_dist = 1e10;
		if (in_closed > 0.5) {
			if (best0 > reach) {
				void_dist = closed_edge_dist;
			}
		} else {
			void_dist = reach - best0;
		}
		stroke = max(stroke, 1.0 - smoothstep(half_w - aa, half_w + aa, void_dist));
	}

	if (stroke > 0.001) {
		a = max(a, border_a * stroke);
		rgb = mix(rgb, rgb * 1.15, 0.35 * stroke);
	}

	if (a < 0.001) discard;
	ALBEDO = rgb;
	ALPHA = a;
}
