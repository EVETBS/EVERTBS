shader_type spatial;
// depth_draw_never: translucent 底图 must not occlude with a square depth plate.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, world_vertex_coords;

uniform int site_count : hint_range(0, 8) = 0;
uniform vec4 site_pos_0; // xyz = XZ, w = faction id (float)
uniform vec4 site_pos_1;
uniform vec4 site_pos_2;
uniform vec4 site_pos_3;
uniform vec4 site_pos_4;
uniform vec4 site_pos_5;
uniform vec4 site_pos_6;
uniform vec4 site_pos_7;
uniform vec4 site_col_0;
uniform vec4 site_col_1;
uniform vec4 site_col_2;
uniform vec4 site_col_3;
uniform vec4 site_col_4;
uniform vec4 site_col_5;
uniform vec4 site_col_6;
uniform vec4 site_col_7;
uniform vec4 cluster_center; // xyz centroid
uniform float cluster_r = 80.0;
uniform float fill_a = 0.05;
uniform float border_a = 0.2;
uniform float border_w = 2.2;
uniform float jagged = 0.42;
uniform float edge_base = 0.92;
uniform vec4 border_col_b = vec4(0.92, 0.94, 0.98, 1.0);
// Half-extents of the hosting QuadMesh in world XZ (from center).
uniform vec2 quad_half = vec2(200.0, 200.0);

varying vec3 v_wpos;

vec4 spos(int i) {
	if (i == 0) return site_pos_0;
	if (i == 1) return site_pos_1;
	if (i == 2) return site_pos_2;
	if (i == 3) return site_pos_3;
	if (i == 4) return site_pos_4;
	if (i == 5) return site_pos_5;
	if (i == 6) return site_pos_6;
	return site_pos_7;
}

vec4 scol(int i) {
	if (i == 0) return site_col_0;
	if (i == 1) return site_col_1;
	if (i == 2) return site_col_2;
	if (i == 3) return site_col_3;
	if (i == 4) return site_col_4;
	if (i == 5) return site_col_5;
	if (i == 6) return site_col_6;
	return site_col_7;
}

float coast_noise(vec2 p, float ang) {
	return sin(ang * 5.0) * 0.45 + sin(ang * 11.0 + 1.7) * 0.30 + sin(ang * 3.0 - 0.4) * 0.25
		+ sin(ang * 17.0 + 2.1) * 0.15
		+ sin(p.x * 0.08 + p.y * 0.11) * 0.20 + sin(p.x * 0.19 - p.y * 0.07 + 0.9) * 0.15;
}

/// Higher-frequency junction noise (boundary seams).
float seam_noise(vec2 p) {
	return sin(p.x * 0.22 + p.y * 0.17) * 0.40
		+ sin(p.x * 0.41 - p.y * 0.29 + 1.1) * 0.30
		+ sin((p.x + p.y) * 0.33 + 2.4) * 0.20
		+ sin(p.x * 0.09 - p.y * 0.48 + 0.6) * 0.25;
}

void vertex() {
	v_wpos = VERTEX;
}

void fragment() {
	if (site_count <= 0) {
		discard;
	}
	vec2 p = v_wpos.xz;
	vec2 cc = cluster_center.xz;
	vec2 from_c = p - cc;
	float ang = atan(from_c.y, from_c.x);
	float n = coast_noise(p, ang);
	// Outer silhouette tracks jagged hard (gain 2.6) so the HUD spin is obvious even with one faction.
	float reach = cluster_r * (edge_base + jagged * 2.6 * n);

	// Kill square QuadMesh frame: never draw near the mesh AABB edge.
	vec2 local = abs(p - cc);
	vec2 margin = max(quad_half - vec2(6.0), vec2(1.0));
	if (local.x > margin.x || local.y > margin.y) {
		discard;
	}

	// Outer silhouette uses plain nearest site.
	float best0 = 1.0e20;
	int bi0 = 0;
	for (int i = 0; i < 8; i++) {
		if (i >= site_count) break;
		float d = distance(p, spos(i).xz);
		if (d < best0) {
			best0 = d;
			bi0 = i;
		}
	}
	if (best0 > reach) {
		discard;
	}

	// Junction ownership: domain-warp sample so faction seams follow jagged strongly.
	// Gain ~28 world units at jagged=1 → spin is very visible on borders.
	float warp = jagged * 28.0;
	float sn = seam_noise(p);
	float sn2 = seam_noise(p + vec2(23.0, -11.0));
	vec2 pw = p + warp * vec2(sn, sn2);

	float best = 1.0e20;
	int bi = 0;
	for (int i = 0; i < 8; i++) {
		if (i >= site_count) break;
		float d = distance(pw, spos(i).xz);
		if (d < best) {
			best = d;
			bi = i;
		}
	}
	float fac = spos(bi).w;

	float second_diff = 1.0e20;
	for (int j = 0; j < 8; j++) {
		if (j >= site_count) break;
		if (abs(spos(j).w - fac) < 0.5) {
			continue;
		}
		float d2 = distance(pw, spos(j).xz);
		second_diff = min(second_diff, d2);
	}

	// Edge metric wobble: zero-crossing moves further with jagged.
	float nedge = seam_noise(p * 1.15) * 0.65 + coast_noise(p * 1.3, ang + 0.7) * 0.35;
	float edge = (second_diff - best) - jagged * 16.0 * nedge;
	float thr = border_w * (1.0 + jagged * 4.0 * abs(nedge));

	vec4 fill = scol(bi);
	vec3 rgb = fill.rgb;
	float a = fill_a;

	// Soft outer rim (less jagged-coupled than seams).
	float outer_edge = reach - best0;
	if (outer_edge < border_w * 1.4) {
		a = max(a, border_a * 0.85);
		rgb = mix(fill.rgb, border_col_b.rgb, 0.35);
	}
	if (outer_edge < border_w * 0.55) {
		a = max(a, border_a);
		rgb = mix(fill.rgb, border_col_b.rgb, 0.7);
	}

	// Faction borders — width + path both track jagged.
	if (second_diff < 1.0e19 && edge < thr) {
		a = max(a, border_a);
		rgb = fill.rgb;
	}
	if (second_diff < 1.0e19 && edge < thr * 0.42) {
		a = max(a, border_a);
		rgb = mix(fill.rgb, border_col_b.rgb, 0.65);
	}
	ALBEDO = rgb;
	ALPHA = a;
}
