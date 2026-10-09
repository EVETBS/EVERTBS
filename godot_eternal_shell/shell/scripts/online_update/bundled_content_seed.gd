class_name BundledContentSeed
extends RefCounted

## Copy ship-with-shell content into user:// when runtime packs are missing / older.
## Android: res://bundled_content (exported into APK).
## Windows fat Setup: Inno may already have written user://; this is a fallback.
##
## seed_meta.json:
##   packs: [{ "path": "packs/logic.pck", "sha256"?: "...", "size"?: N }, ...]
## Legacy: packRel: "packs/game.pck" (+ optional sha256/size on root).

const BUNDLED_ROOT := "res://bundled_content"
const SEED_META_PATH := "res://bundled_content/seed_meta.json"
const CHUNK_BYTES := 1024 * 1024


static func ensure_async(host: Node, status_cb: Callable = Callable()) -> Dictionary:
	UpdateConfig.ensure_dirs()
	if not FileAccess.file_exists(SEED_META_PATH):
		return {"ok": true, "seeded": false, "reason": "no bundled seed_meta"}

	var meta_f := FileAccess.open(SEED_META_PATH, FileAccess.READ)
	if meta_f == null:
		return {"ok": false, "seeded": false, "reason": "cannot read seed_meta"}
	var meta = JSON.parse_string(meta_f.get_as_text())
	meta_f.close()
	if typeof(meta) != TYPE_DICTIONARY:
		return {"ok": false, "seeded": false, "reason": "seed_meta JSON invalid"}

	var seed_ver := str(meta.get("version", "")).strip_edges()
	var entry := str(meta.get("entry", UpdateConfig.DEFAULT_ENTRY)).strip_edges()
	if entry.is_empty():
		entry = UpdateConfig.DEFAULT_ENTRY

	var pack_rels: Array[String] = []
	## Optional expected sha256 per rel (from seed_meta packs[].sha256).
	var pack_sha: Dictionary = {}
	var packs_raw = meta.get("packs", null)
	if typeof(packs_raw) == TYPE_ARRAY and (packs_raw as Array).size() > 0:
		for item in packs_raw:
			if typeof(item) == TYPE_DICTIONARY:
				var p := str(item.get("path", "")).replace("\\", "/").strip_edges()
				if not p.is_empty():
					pack_rels.append(p)
					var sh := str(item.get("sha256", "")).strip_edges().to_lower()
					if not sh.is_empty():
						pack_sha[p] = sh
			elif typeof(item) == TYPE_STRING:
				var ps := str(item).replace("\\", "/").strip_edges()
				if not ps.is_empty():
					pack_rels.append(ps)
	if pack_rels.is_empty():
		var legacy := str(meta.get("packRel", "")).replace("\\", "/").strip_edges()
		if legacy.is_empty():
			legacy = "packs/game.pck"
		pack_rels.append(legacy)
		var legacy_sha := str(meta.get("sha256", "")).strip_edges().to_lower()
		if not legacy_sha.is_empty():
			pack_sha[legacy] = legacy_sha

	var missing_bundled: Array[String] = []
	for rel in pack_rels:
		var bundled_pack := BUNDLED_ROOT.path_join(rel)
		if not FileAccess.file_exists(bundled_pack):
			missing_bundled.append(rel)
	if missing_bundled.size() == pack_rels.size():
		return {"ok": true, "seeded": false, "reason": "no bundled pack file"}
	if not missing_bundled.is_empty():
		push_warning("[BundledContentSeed] missing bundled packs: %s" % ", ".join(missing_bundled))

	var local_ver := ""
	var applied_path := UpdateConfig.applied_version_path()
	if FileAccess.file_exists(applied_path):
		var af := FileAccess.open(applied_path, FileAccess.READ)
		if af:
			var data = JSON.parse_string(af.get_as_text())
			af.close()
			if typeof(data) == TYPE_DICTIONARY:
				local_ver = str(data.get("version", "")).strip_edges()

	var all_present := true
	for rel in pack_rels:
		if rel in missing_bundled:
			continue
		if not FileAccess.file_exists(UpdateConfig.runtime_file_path(rel)):
			all_present = false
			break

	## Same version string can still ship new pack bytes (content ver stuck while
	## logic.pck changes). Prefer sha256 from seed_meta; mismatch → re-seed
	## ONLY when local is not newer than seed (never wipe HF hot-update).
	var sha_mismatch := false
	if all_present and not pack_sha.is_empty():
		for rel2 in pack_rels:
			if rel2 in missing_bundled:
				continue
			if not pack_sha.has(rel2):
				continue
			var expect: String = str(pack_sha[rel2])
			var got: String = Sha256Util.file_sha256(UpdateConfig.runtime_file_path(rel2)).to_lower()
			if got.is_empty() or got != expect:
				sha_mismatch = true
				print("[BundledContentSeed] sha mismatch %s expect=%s got=%s" % [rel2, expect, got])
				break

	## RELEASE_AND_HOTUPDATE: local applied > seed → keep HF packs (no downgrade).
	if all_present and not local_ver.is_empty() and not seed_ver.is_empty():
		if ContentVersionGate.compare(local_ver, seed_ver) > 0:
			print("[BundledContentSeed] boot.seed reason=keep_newer_applied local=%s seed=%s sha_mismatch=%s" % [
				local_ver, seed_ver, "1" if sha_mismatch else "0"
			])
			return {"ok": true, "seeded": false, "reason": "keep newer applied (no downgrade)"}

	if all_present and not sha_mismatch and not local_ver.is_empty() and not seed_ver.is_empty():
		if ContentVersionGate.compare(seed_ver, local_ver) <= 0:
			print("[BundledContentSeed] boot.seed reason=local_already_ge_seed local=%s" % local_ver)
			return {"ok": true, "seeded": false, "reason": "local already >= seed"}

	if status_cb.is_valid():
		status_cb.call("正在解压内置内容…", 0.05)

	var copied := 0
	var total_to_copy := pack_rels.size() - missing_bundled.size()
	for rel in pack_rels:
		if rel in missing_bundled:
			continue
		var bundled_pack := BUNDLED_ROOT.path_join(rel)
		var dest_pack := UpdateConfig.runtime_file_path(rel)
		var dest_dir := dest_pack.get_base_dir()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest_dir))
		var copy_ok := await _copy_chunked(host, bundled_pack, dest_pack, status_cb, copied, total_to_copy)
		if not copy_ok:
			return {"ok": false, "seeded": false, "reason": "copy pack failed: %s" % rel}
		copied += 1

	var payload := {
		"version": seed_ver if not seed_ver.is_empty() else "bundled",
		"entry": entry,
		"appliedAt": Time.get_datetime_string_from_system(true),
		"platform": UpdateConfig.get_platform_id(),
		"source": "bundled_content_seed",
		"packs": pack_rels,
	}
	var wf := FileAccess.open(applied_path, FileAccess.WRITE)
	if wf == null:
		return {"ok": false, "seeded": false, "reason": "cannot write applied_version"}
	wf.store_string(JSON.stringify(payload, "\t"))
	wf.close()

	_prune_orphan_packs(pack_rels)

	if status_cb.is_valid():
		status_cb.call("内置内容已就绪 %s" % payload["version"], 0.12)
	print("[BundledContentSeed] boot.seed reason=reseed ver=%s packs=%s" % [seed_ver, str(copied)])
	return {"ok": true, "seeded": true, "reason": "ok", "version": seed_ver, "entry": entry}


## Remove .pck/.zip in packs/ that are not in the seed/manifest list (legacy models.pck etc.).
static func _prune_orphan_packs(keep_rels: Array[String]) -> void:
	var keep: Dictionary = {}
	for rel in keep_rels:
		var leaf: String = rel.replace("\\", "/").get_file()
		if not leaf.is_empty():
			keep[leaf] = true
	var packs_dir: String = UpdateConfig.CONTENT_RUNTIME_DIR.path_join("packs")
	var abs_dir: String = ProjectSettings.globalize_path(packs_dir)
	var dir: DirAccess = DirAccess.open(packs_dir)
	if dir == null:
		dir = DirAccess.open(abs_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var fn: String = dir.get_next()
	var removed: PackedStringArray = PackedStringArray()
	while fn != "":
		if not dir.current_is_dir() and (fn.ends_with(".pck") or fn.ends_with(".zip")):
			if not keep.has(fn):
				var path: String = packs_dir.path_join(fn)
				var err: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
				if err != OK:
					err = dir.remove(fn)
				if err == OK:
					removed.append(fn)
		fn = dir.get_next()
	dir.list_dir_end()
	if removed.size() > 0:
		print("[BundledContentSeed] pruned orphan packs: %s" % ", ".join(removed))


static func _copy_chunked(
	host: Node,
	src: String,
	dst: String,
	status_cb: Callable,
	pack_index: int = 0,
	pack_total: int = 1
) -> bool:
	var from := FileAccess.open(src, FileAccess.READ)
	if from == null:
		push_error("[BundledContentSeed] open src failed: %s" % src)
		return false
	var to := FileAccess.open(dst, FileAccess.WRITE)
	if to == null:
		from.close()
		push_error("[BundledContentSeed] open dst failed: %s" % dst)
		return false
	var total := from.get_length()
	var done := 0
	var chunk_i := 0
	var pack_base := 0.05
	var pack_span := 0.07
	if pack_total > 1:
		pack_base = 0.05 + 0.07 * (float(pack_index) / float(pack_total))
		pack_span = 0.07 / float(pack_total)
	while done < total:
		var n: int = mini(CHUNK_BYTES, total - done)
		var buf := from.get_buffer(n)
		if buf.size() != n:
			from.close()
			to.close()
			return false
		to.store_buffer(buf)
		done += n
		chunk_i += 1
		if host != null and is_instance_valid(host) and chunk_i % 4 == 0:
			if status_cb.is_valid() and total > 0:
				var frac := pack_base + pack_span * (float(done) / float(total))
				var label := "正在解压内置内容… %s / %s" % [
					UpdateClient.format_bytes(done),
					UpdateClient.format_bytes(total),
				]
				if pack_total > 1:
					label = "正在解压内置内容（%d/%d）… %s / %s" % [
						pack_index + 1,
						pack_total,
						UpdateClient.format_bytes(done),
						UpdateClient.format_bytes(total),
					]
				status_cb.call(label, frac)
			await host.get_tree().process_frame
	from.close()
	to.close()
	return true
