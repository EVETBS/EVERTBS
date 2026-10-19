extends RefCounted
class_name ProceduralStarmap
## TopDog-style planar Poisson + MST + density edges. No Y jitter. Degree cap 8.

const MAX_DEGREE := 8

static func generate(opts: Dictionary) -> Dictionary:
	var n: int = int(opts.get("star_count", 20))
	var density: float = float(opts.get("lane_density", 1.0))
	var spacing: float = float(opts.get("avg_spacing", 120.0))
	var station_frac: float = clampf(float(opts.get("station_frac", 0.35)), 0.0, 1.0)
	var resource_frac: float = clampf(float(opts.get("resource_frac", 0.35)), 0.0, 1.0)
	var factions: int = clampi(int(opts.get("faction_count", 3)), 2, 8)
	var seed_v: int = int(opts.get("seed", 0))
	if station_frac + resource_frac > 1.0:
		var ssum := station_frac + resource_frac
		station_frac /= ssum
		resource_frac /= ssum
	var rng := RandomNumberGenerator.new()
	if seed_v == 0:
		rng.randomize()
	else:
		rng.seed = seed_v
	var min_dist: float = spacing * 0.72
	var radius: float = spacing * sqrt(float(n)) * 0.55
	var pts: Array = _poisson(rng, n, radius, min_dist)
	while pts.size() < n:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	pts = pts.slice(0, n)
	var edges: Array = _mst_then_dense(pts, density, rng)
	var degree: PackedInt32Array = PackedInt32Array()
	degree.resize(n)
	for e0 in edges:
		var a0 := int(e0[0])
		var b0 := int(e0[1])
		degree[a0] = degree[a0] + 1
		degree[b0] = degree[b0] + 1
	var station_n: int = maxi(factions, int(round(float(n) * station_frac)))
	station_n = mini(station_n, n)
	var resource_n: int = int(round(float(n) * resource_frac))
	resource_n = mini(resource_n, n - station_n)
	var station_w := PackedFloat32Array()
	station_w.resize(n)
	for i in n:
		station_w[i] = _deadend_weight(int(degree[i]), station_frac, -0.10)
	var station_pick: Array = _weighted_take(range(n), station_w, station_n, rng)
	var station_set: Dictionary = {}
	for sid0 in station_pick:
		station_set[int(sid0)] = true
	var rest: Array = []
	var resource_w := PackedFloat32Array()
	for i2 in n:
		if station_set.has(i2):
			continue
		rest.append(i2)
		resource_w.append(_deadend_weight(int(degree[i2]), resource_frac, 0.10))
	var resource_pick: Array = _weighted_take(rest, resource_w, resource_n, rng)
	var resource_set: Dictionary = {}
	for sid1 in resource_pick:
		resource_set[int(sid1)] = true
	var kinds: Array = []
	kinds.resize(n)
	for i3 in n:
		if station_set.has(i3):
			kinds[i3] = "station_system"
		elif resource_set.has(i3):
			kinds[i3] = "resource_system"
		else:
			kinds[i3] = "normal"
	var n_m := 1
	var n_n := 1
	var n_b := 1
	var n_r := 1
	var n_t := 1
	var systems: Array = []
	for i4 in n:
		var links: Array = []
		for e in edges:
			if int(e[0]) == i4:
				links.append("s%d" % int(e[1]))
			elif int(e[1]) == i4:
				links.append("s%d" % int(e[0]))
		var deg := int(degree[i4])
		var nm := ""
		if str(kinds[i4]) == "station_system":
			nm = "B%d" % n_b
			n_b += 1
		elif str(kinds[i4]) == "resource_system" and deg == 1:
			nm = "T%d" % n_t
			n_t += 1
		elif str(kinds[i4]) == "resource_system":
			nm = "R%d" % n_r
			n_r += 1
		elif deg >= 5:
			nm = "M%d" % n_m
			n_m += 1
		else:
			nm = "N%d" % n_n
			n_n += 1
		systems.append({
			"id": "s%d" % i4,
			"name": nm,
			"pos": [float(pts[i4].x), float(pts[i4].y)],
			"links": links,
			"kind": kinds[i4],
		})
	return {
		"viewer_faction": 1,
		"cell_count": 12,
		"ring_inner": 12.0,
		"ring_outer": 26.0,
		"empty_system_scale": 0.62,
		"ring_phase_bias_deg": 37.5,
		"systems": systems,
		"opening_stations": {},
		"pilots": [],
		"gen": {"seed": rng.seed, "star_count": n, "lane_density": density, "avg_spacing": spacing},
	}

static func _deadend_weight(degree: int, frac: float, delta: float) -> float:
	var w := frac
	if degree == 1:
		w = frac + delta
	return clampf(w, 0.0, 1.0)


static func _weighted_take(candidates: Array, weights: PackedFloat32Array, count: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array = []
	var w: Array = []
	for i in candidates.size():
		pool.append(int(candidates[i]))
		var wt := 0.0
		if i < weights.size():
			wt = float(weights[i])
		w.append(maxf(wt, 0.0))
	var picked: Array = []
	var ntake := mini(count, pool.size())
	for _k in ntake:
		var sum := 0.0
		for x in w:
			sum += float(x)
		var j := pool.size() - 1
		if sum <= 0.0001:
			j = rng.randi_range(0, pool.size() - 1)
		else:
			var roll := rng.randf() * sum
			var acc := 0.0
			for i2 in pool.size():
				acc += float(w[i2])
				if roll <= acc:
					j = i2
					break
		picked.append(pool[j])
		pool.remove_at(j)
		w.remove_at(j)
	return picked


static func _poisson(rng: RandomNumberGenerator, n: int, radius: float, min_dist: float) -> Array:
	var pts: Array = []
	var guard := 0
	while pts.size() < n and guard < n * 80:
		guard += 1
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var p := Vector2(cos(a) * r, sin(a) * r)
		var ok := true
		for q in pts:
			if p.distance_to(q) < min_dist:
				ok = false
				break
		if ok:
			pts.append(p)
	return pts

static func _mst_then_dense(pts: Array, density: float, rng: RandomNumberGenerator) -> Array:
	var n := pts.size()
	var edges: Array = []
	var in_tree: PackedByteArray = PackedByteArray()
	in_tree.resize(n)
	in_tree.fill(0)
	in_tree[0] = 1
	var linked := 1
	while linked < n:
		var best_a := -1
		var best_b := -1
		var best_d := INF
		for i in n:
			if in_tree[i] == 0:
				continue
			for j in n:
				if in_tree[j] != 0:
					continue
				var d: float = pts[i].distance_squared_to(pts[j])
				if d < best_d:
					best_d = d
					best_a = i
					best_b = j
		if best_a < 0:
			break
		edges.append([best_a, best_b])
		in_tree[best_b] = 1
		linked += 1
	var deg: PackedInt32Array = PackedInt32Array()
	deg.resize(n)
	deg.fill(0)
	for e in edges:
		deg[int(e[0])] += 1
		deg[int(e[1])] += 1
	var candidates: Array = []
	for i in n:
		for j in range(i + 1, n):
			candidates.append({"a": i, "b": j, "d": pts[i].distance_squared_to(pts[j])})
	candidates.sort_custom(func(x, y): return float(x["d"]) < float(y["d"]))
	var extra_budget: int = int(round(float(n) * clampf(density, 0.25, 3.0) * 0.55))
	var added := 0
	var have: Dictionary = {}
	for e in edges:
		have["%d_%d" % [mini(int(e[0]), int(e[1])), maxi(int(e[0]), int(e[1]))]] = true
	for c in candidates:
		if added >= extra_budget:
			break
		var a: int = int(c["a"])
		var b: int = int(c["b"])
		var key := "%d_%d" % [mini(a, b), maxi(a, b)]
		if have.has(key):
			continue
		if deg[a] >= MAX_DEGREE or deg[b] >= MAX_DEGREE:
			continue
		edges.append([a, b])
		have[key] = true
		deg[a] += 1
		deg[b] += 1
		added += 1
	return edges

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
