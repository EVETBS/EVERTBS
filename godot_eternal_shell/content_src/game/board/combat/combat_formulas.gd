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

## Autochess missile DR. Paper damage stays the board's four-type sum.
## dr = min(1, S/Er, (S/Er * Ev/Vt) ^ exp). DRF <= 1 is already the exponent.
static func missile_damage_factor(
	signature: float,
	target_speed: float,
	explosion_radius: float,
	explosion_velocity: float,
	drf: float,
	drs: float = 5.5
) -> float:
	var er := maxf(explosion_radius, 1.0)
	var ev := maxf(explosion_velocity, 1.0)
	var sig := maxf(signature, 1.0)
	var sig_ratio := sig / er
	if drf <= 0.0:
		return minf(1.0, sig_ratio)
	var drf_exp := drf
	if drf > 1.0:
		var base := drs if drs > 1.0 else 5.5
		drf_exp = log(drf) / log(base)
	var vt := maxf(target_speed, 0.0001)
	return minf(1.0, minf(sig_ratio, pow(sig_ratio * (ev / vt), drf_exp)))

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
	skip_max_loss: bool = false,
	max_loss_ratio: float = 0.1,
	armor_resist_add: int = 0
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
	if rem > 0.0 and armor > 0.0 and armor_resist_add != 0:
		var base_f := 1.0 - clampf(float(resist), 0.0, 100.0) / 100.0
		var arm_f := 1.0 - clampf(float(resist + armor_resist_add), 0.0, 100.0) / 100.0
		if base_f > 0.0001:
			var raw_left := rem / base_f
			var armor_budget := raw_left * arm_f
			da = minf(armor, armor_budget)
			armor -= da
			var raw_after := 0.0
			if arm_f > 0.0001:
				raw_after = maxf(0.0, armor_budget - da) / arm_f
			rem = raw_after * base_f
		else:
			da = minf(armor, rem)
			armor -= da
			rem -= da
	elif rem > 0.0 and armor > 0.0:
		da = minf(armor, rem)
		armor -= da
		rem -= da
	if rem > 0.0 and structure > 0.0:
		dh = minf(structure, rem)
		structure -= dh
		rem -= dh
	# capital-style max loss on absorbed (guard redirect skips on bearer). Base ratio 0.1.
	var loss_ratio := maxf(0.0, max_loss_ratio)
	if not skip_max_loss:
		max_s = maxf(1.0, max_s - ds * loss_ratio)
		max_a = maxf(1.0, max_a - da * loss_ratio)
		max_h = maxf(1.0, max_h - dh * loss_ratio)
	shield = minf(shield, max_s)
	armor = minf(armor, max_a)
	structure = minf(structure, max_h)
	return {
		"shield": shield, "armor": armor, "structure": structure,
		"max_s": max_s, "max_a": max_a, "max_h": max_h,
		"absorbed": taken - rem, "killed": structure <= 0.0
	}
