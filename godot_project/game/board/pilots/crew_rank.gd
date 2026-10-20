extends RefCounted
class_name CrewRank
## Rank rules run only when the builtin member table is written.
## Runtime reads the ships column and crew-equipment fields.

const TONNAGES: Array[String] = ["frigate", "destroyer", "cruiser", "battlecruiser", "battleship"]
const EFFECT_KEYS: Array[String] = [
	"hp_mul", "shield_mul", "armor_mul", "structure_mul", "cap_mul", "recharge_mul", "resist_mul",
	"speed_mul", "signature_mul", "scan_mul", "mass_mul", "inertia_mul", "prep_mul", "move_mul", "jump_mul", "landing_mul", "move_penalty_mul",
	"build_mul", "work_mul",
	"weapon_damage_mul", "damage_emp_mul", "damage_thermal_mul", "damage_kinetic_mul", "damage_explosive_mul",
	"heal_shield_mul", "heal_armor_mul", "cycle_mul", "cap_cost_mul", "tracking_mul", "optimal_mul", "falloff_mul", "sig_res_mul", "range_cells_mul",
	"explosion_radius_mul", "explosion_velocity_mul", "drf_mul", "explosion_cells_mul",
	"range_mul", "resistance_mul", "pd_damage_mul", "dph_mul", "missile_explosion_mul", "speed_bonus_mul", "cap_convert_mul",
	"bubble_range_mul", "bubble_time_mul", "bubble_cap_mul",
]
const BONUS_LABELS := {
	"hp_mul": "血量", "shield_mul": "护盾", "armor_mul": "装甲", "structure_mul": "结构", "cap_mul": "电容", "recharge_mul": "电容回充秒", "resist_mul": "抗性",
	"speed_mul": "速度", "signature_mul": "签名", "scan_mul": "扫描分辨率", "mass_mul": "质量", "inertia_mul": "惯性",
	"prep_mul": "跨格准备", "move_mul": "同系跨格", "jump_mul": "过门", "landing_mul": "落地僵直", "move_penalty_mul": "移速惩罚",
	"build_mul": "制造时间", "work_mul": "作业值",
	"weapon_damage_mul": "伤害", "damage_emp_mul": "电磁伤害", "damage_thermal_mul": "热能伤害", "damage_kinetic_mul": "动能伤害", "damage_explosive_mul": "爆炸伤害",
	"heal_shield_mul": "回盾", "heal_armor_mul": "回甲", "cycle_mul": "周期", "cap_cost_mul": "耗电", "tracking_mul": "跟踪",
	"optimal_mul": "最优", "falloff_mul": "失准", "sig_res_mul": "签分", "range_cells_mul": "射程格",
	"explosion_radius_mul": "爆炸半径", "explosion_velocity_mul": "爆速", "drf_mul": "DRF", "explosion_cells_mul": "爆炸格数",
	"range_mul": "射程倍率", "resistance_mul": "抗性倍率", "pd_damage_mul": "近防伤害倍率", "dph_mul": "输出倍率",
	"missile_explosion_mul": "导弹爆炸倍率", "speed_bonus_mul": "加力倍率", "cap_convert_mul": "上限损失转化",
	"bubble_range_mul": "泡吸附格", "bubble_time_mul": "泡周期", "bubble_cap_mul": "泡耗电",
}


static func unlock_count(rank: String) -> int:
	match rank:
		"D":
			return 1
		"C":
			return 2
		"B":
			return 3
		_:
			return 999999


static func playable_ship_ids() -> PackedStringArray:
	var out := PackedStringArray()
	var path := "res://data/board/ships.json"
	if not FileAccess.file_exists(path):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	for s in (parsed as Dictionary).get("ships", []):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var def: Dictionary = s
		if bool(def.get("npc_hull", false)) or bool(def.get("npc", false)):
			continue
		var sid := str(def.get("id", "")).strip_edges()
		if sid != "":
			out.append(sid)
	return out


static func member_has_ship(member: Dictionary, ship_id: String) -> bool:
	if ship_id.strip_edges() == "":
		return false
	if member.is_empty():
		return true
	var raw := str(member.get("ships", "")).strip_edges()
	if raw == "":
		return true
	for sid in raw.split("|", false):
		if sid.strip_edges() == ship_id:
			return true
	return false


static func expand_full_unlock_ships(row: Dictionary, playable: PackedStringArray) -> bool:
	var rank := str(row.get("rank", "")).strip_edges().to_upper()
	if rank != "A" and rank != "SR":
		return false
	if playable.is_empty():
		return false
	var have: Dictionary = {}
	for sid in str(row.get("ships", "")).split("|", false):
		var s := sid.strip_edges()
		if s != "":
			have[s] = true
	var missing := false
	for pid in playable:
		if not have.has(pid):
			missing = true
			break
	if not missing and have.size() == playable.size():
		return false
	row["ships"] = "|".join(playable)
	return true


static func unlocked_ids(rank: String, member_id: String, by_ton: Dictionary) -> PackedStringArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(member_id)
	var out := PackedStringArray()
	var n := unlock_count(rank)
	for ton in TONNAGES:
		var pool: Array = by_ton.get(ton, [])
		var copy: Array = pool.duplicate()
		if n >= copy.size():
			for sid in copy:
				out.append(str(sid))
			continue
		for _i in n:
			if copy.is_empty():
				break
			var pick := rng.randi_range(0, copy.size() - 1)
			out.append(str(copy[pick]))
			copy.remove_at(pick)
	return out
