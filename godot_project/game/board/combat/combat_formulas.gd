extends RefCounted
class_name BoardCombatFormulas

static func turret_hit_chance(
	tracking: float,
	sig_res: float,
	falloff_m: float,
	optimal_m: float,
	target_speed: float,
	target_sig: float,
	distance_m: float
) -> float:
	var tracking_term = 0.0
	if tracking > 0.0 and target_sig > 0.0:
		var ang = (target_speed / maxf(distance_m, 1.0)) * (sig_res / target_sig)
		tracking_term = ang / tracking
	var range_term = 0.0
	if falloff_m > 0.0:
		var over = maxf(0.0, distance_m - optimal_m)
		range_term = over / falloff_m
	return pow(0.5, tracking_term * tracking_term + range_term * range_term)

static func roll_quality(rng: RandomNumberGenerator) -> float:
	var u = rng.randf()
	if u < 0.01:
		return 3.0 # wrecking
	# uniform-ish 0.5..1.5
	return 0.5 + rng.randf()

static func apply_layer_damage(
	shield: float, armor: float, structure: float,
	max_s: float, max_a: float, max_h: float,
	raw: float, resist: int,
	skip_max_loss: bool = false
) -> Dictionary:
	var taken = raw * (1.0 - clampf(float(resist), 0.0, 100.0) / 100.0)
	var rem = taken
	var ds = 0.0
	var da = 0.0
	var dh = 0.0
	if rem > 0.0 and shield > 0.0:
		ds = minf(shield, rem)
		shield -= ds
		rem -= ds
	if rem > 0.0 and armor > 0.0:
		da = minf(armor, rem)
		armor -= da
		rem -= da
	if rem > 0.0 and structure > 0.0:
		dh = minf(structure, rem)
		structure -= dh
		rem -= dh
	# capital-style 10% max loss on absorbed (guard redirect skips on bearer)
	if not skip_max_loss:
		max_s = maxf(1.0, max_s - ds * 0.1)
		max_a = maxf(1.0, max_a - da * 0.1)
		max_h = maxf(1.0, max_h - dh * 0.1)
	shield = minf(shield, max_s)
	armor = minf(armor, max_a)
	structure = minf(structure, max_h)
	return {
		"shield": shield, "armor": armor, "structure": structure,
		"max_s": max_s, "max_a": max_a, "max_h": max_h,
		"absorbed": taken - rem, "killed": structure <= 0.0
	}
