class_name UpdateBootstrap
extends RefCounted

signal status(message: String, fraction: float)
signal finished(ok: bool, entry: String, message: String)
signal confirm_requested(
	remote_version: String,
	local_version: String,
	notes: String,
	download_bytes: int,
	file_count: int
)

var _client: UpdateClient
var _awaiting_confirm := false
var _user_accepted := false
var _aborted := false


func _init(client: UpdateClient) -> void:
	_client = client
	_client.progress.connect(func(msg: String, frac: float): status.emit(msg, frac))


func abort() -> void:
	## Boot「使用本地内容」：取消验版/下载；确认等待中按「不更新」结束。
	_aborted = true
	_client.request_abort()
	if _awaiting_confirm:
		respond_confirm(false)


func respond_confirm(accepted: bool) -> void:
	_user_accepted = accepted
	_awaiting_confirm = false


func _fail_if_aborted() -> bool:
	if _aborted or _client.abort_requested:
		finished.emit(false, "", "aborted")
		return true
	return false


func run() -> void:
	UpdateConfig.ensure_dirs()
	status.emit("Checking for updates…", 0.02)
	var seed_host: Node = _client._host
	var seed_res: Dictionary = await BundledContentSeed.ensure_async(
		seed_host,
		func(msg: String, frac: float) -> void:
			status.emit(msg, frac)
	)
	if _fail_if_aborted():
		return
	if not seed_res.get("ok", false):
		finished.emit(false, "", "内置内容解压失败: %s" % seed_res.get("reason", ""))
		return
	if seed_res.get("seeded", false):
		status.emit("内置内容已就绪", 0.12)

	var ver_res := await _client.fetch_version_json_from_candidates(UpdateConfig.candidate_base_urls())
	if _fail_if_aborted():
		return
	if not ver_res.get("ok", false):
		if _client.has_local_content_ready():
			var local_v := _client.read_applied_version()
			status.emit("Offline — using local %s" % local_v, 0.5)
			var offline_entry := await _mount_local_and_get_entry()
			if offline_entry.get("ok", false):
				finished.emit(true, str(offline_entry["entry"]), "offline")
				return
		finished.emit(false, "", "Version check failed: %s" % ver_res.get("error", ""))
		return

	var remote: Dictionary = ver_res["data"]
	var protocol := int(remote.get("protocol", 1))
	if protocol != UpdateConfig.PROTOCOL_SUPPORTED:
		finished.emit(false, "", "Unsupported protocol %s — install a new shell" % protocol)
		return

	var compat := str(remote.get("shellCompatibilityId", UpdateConfig.SHELL_COMPATIBILITY_ID))
	if not compat.is_empty() and compat != UpdateConfig.SHELL_COMPATIBILITY_ID:
		finished.emit(
			false,
			"",
			"shellCompatibilityId mismatch (%s ≠ %s) — install a new shell" % [compat, UpdateConfig.SHELL_COMPATIBILITY_ID]
		)
		return

	if remote.has("baseUrl") and not UpdateConfig.lock_base_url_from_override():
		UpdateConfig.apply_remote_base_url(str(remote["baseUrl"]))
	elif UpdateConfig.lock_base_url_from_override():
		status.emit("baseUrl locked by bootstrap_override", 0.11)

	var remote_ver := str(remote.get("version", "")).strip_edges()
	var entry := str(remote.get("entry", UpdateConfig.DEFAULT_ENTRY)).strip_edges()
	if entry.is_empty():
		entry = UpdateConfig.DEFAULT_ENTRY
	var notes := str(remote.get("notes", ""))

	var local_ver := _client.read_applied_version()
	var cmp := 1
	if not local_ver.is_empty():
		cmp = ContentVersionGate.compare(remote_ver, local_ver)

	var platform_id := UpdateConfig.get_platform_id()
	status.emit("Remote %s · local %s · platform %s" % [remote_ver, local_ver if local_ver else "(none)", platform_id], 0.12)

	var update_available := local_ver.is_empty() or cmp > 0
	if cmp == 0:
		status.emit("Already latest: %s" % remote_ver, 0.15)
	elif cmp < 0:
		status.emit("Remote behind local — keep %s" % local_ver, 0.15)
		update_available = false

	status.emit("Fetching manifest…", 0.18)
	var man_res := await _client.http_get_text(UpdateConfig.manifest_url())
	if _fail_if_aborted():
		return
	if not man_res.get("ok", false):
		if _client.has_local_content_ready() and not update_available:
			var m := await _mount_local_and_get_entry()
			if m.get("ok", false):
				finished.emit(true, str(m["entry"]), "manifest offline fallback")
				return
		finished.emit(false, "", "manifest failed: %s" % man_res.get("error", ""))
		return

	var man_data = JSON.parse_string(man_res["text"])
	if typeof(man_data) != TYPE_DICTIONARY:
		finished.emit(false, "", "manifest JSON invalid")
		return
	var files: Array = man_data.get("files", [])

	# Equal version but missing / corrupt packs → repair needing confirm
	var needs_repair := false
	if cmp == 0:
		for item in files:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var path := str(item.get("path", ""))
			var kind := str(item.get("kind", "pack"))
			if kind != "pack":
				continue
			if not UpdateConfig.is_manifest_path_wanted(path, platform_id):
				continue
			var local_path := UpdateConfig.runtime_file_path(path)
			if not FileAccess.file_exists(local_path):
				needs_repair = true
				break
			var expect_hash: String = str(item.get("sha256", "")).to_lower()
			if not expect_hash.is_empty():
				if Sha256Util.file_sha256(local_path).to_lower() != expect_hash:
					needs_repair = true
					break

	var should_download := update_available or needs_repair
	if should_download:
		var reason := "新版本可用" if update_available else "本地内容不完整，需要修复下载"
		var plan := _client.plan_downloads(files, platform_id)
		var dl_bytes: int = int(plan["bytes"])
		var dl_count: int = int(plan["count"])
		## Version-only bump（pack sha 未变）：无需弹窗下载，直接盖 applied 版号。
		if update_available and not needs_repair and dl_count == 0:
			status.emit("版本对齐 %s（无需下载包）" % remote_ver, 0.45)
		else:
			status.emit("%s：%s → %s（等待确认）" % [reason, local_ver if local_ver else "(无)", remote_ver], 0.2)
			var accepted := await _await_user_confirm(
				remote_ver,
				local_ver,
				notes if not notes.is_empty() else reason,
				dl_bytes,
				dl_count
			)
			if _fail_if_aborted():
				return
			if not accepted:
				if _client.has_local_content_ready():
					status.emit("已跳过更新，进入本地内容 %s" % local_ver, 0.5)
					var skip_mount := await _mount_local_and_get_entry()
					if skip_mount.get("ok", false):
						var e := str(skip_mount.get("entry", entry))
						finished.emit(true, e, "skipped update")
						return
				finished.emit(false, "", "已取消更新（无可用本地内容）")
				return

			status.emit("正在更新到 %s…" % remote_ver, 0.25)
			var dl := await _client.download_manifest_files(files, platform_id)
			if _aborted or _client.abort_requested or dl.get("aborted", false):
				finished.emit(false, "", "aborted")
				return
			if not dl.get("ok", false):
				finished.emit(false, "", str(dl.get("error", "download failed")))
				return

	var mount := _client.mount_packs(files, platform_id)
	if not mount.get("ok", false):
		if files.is_empty():
			finished.emit(false, "", "No content packs in manifest yet (version %s)" % remote_ver)
			return
		# After skip path we shouldn't be here without packs; try local
		if _client.has_local_content_ready():
			var lm := await _mount_local_and_get_entry()
			if lm.get("ok", false):
				finished.emit(true, str(lm["entry"]), "mount fallback local")
				return
		finished.emit(false, "", str(mount.get("error", "mount failed")))
		return

	if not _client.entry_resource_exists(entry):
		finished.emit(
			false,
			"",
			"挂载后找不到入口 %s（pack 可能损坏或 entry 写错）" % entry
		)
		return

	# Stamp applied version only after mount + entry OK (avoid "假最新").
	if should_download:
		_client.write_applied_version(remote_ver, entry)
	elif local_ver.is_empty() and not remote_ver.is_empty():
		_client.write_applied_version(remote_ver, entry)

	status.emit("正在进入游戏…", 1.0)
	finished.emit(true, entry, "ok")


func _await_user_confirm(
	remote_ver: String,
	local_ver: String,
	notes: String,
	download_bytes: int,
	file_count: int
) -> bool:
	_awaiting_confirm = true
	_user_accepted = false
	confirm_requested.emit(remote_ver, local_ver, notes, download_bytes, file_count)
	var host: Node = _client._host
	while _awaiting_confirm and is_instance_valid(host):
		await host.get_tree().process_frame
	return _user_accepted


func _mount_local_and_get_entry() -> Dictionary:
	var path := UpdateConfig.applied_version_path()
	var entry := UpdateConfig.DEFAULT_ENTRY
	var listed: Array[String] = []
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var data = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(data) == TYPE_DICTIONARY:
				if data.has("entry"):
					entry = str(data["entry"])
				var packs_v = data.get("packs", [])
				if typeof(packs_v) == TYPE_ARRAY:
					for item in packs_v:
						var rel := ""
						if typeof(item) == TYPE_DICTIONARY:
							rel = str(item.get("path", "")).replace("\\", "/").strip_edges()
						else:
							rel = str(item).replace("\\", "/").strip_edges()
						if rel.is_empty():
							continue
						if not rel.begins_with("packs/"):
							rel = "packs/%s" % rel.get_file()
						listed.append(rel)
	if not listed.is_empty():
		for rel2 in listed:
			var full2 := UpdateConfig.runtime_file_path(rel2)
			if not FileAccess.file_exists(full2):
				return {"ok": false, "entry": entry, "error": "missing pack %s" % rel2.get_file()}
			var abs2 := ProjectSettings.globalize_path(full2)
			if not ProjectSettings.load_resource_pack(abs2, true):
				if not ProjectSettings.load_resource_pack(full2, true):
					return {"ok": false, "entry": entry, "error": "mount failed %s" % abs2}
		return {"ok": true, "entry": entry}
	var packs_dir := UpdateConfig.CONTENT_RUNTIME_DIR.path_join("packs")
	var dir := DirAccess.open(packs_dir)
	if dir:
		dir.list_dir_begin()
		var fn := dir.get_next()
		var any := false
		while fn != "":
			if not dir.current_is_dir() and (fn.ends_with(".pck") or fn.ends_with(".zip")):
				any = true
				var full := packs_dir.path_join(fn)
				var abs_path := ProjectSettings.globalize_path(full)
				if not ProjectSettings.load_resource_pack(abs_path, true):
					if not ProjectSettings.load_resource_pack(full, true):
						return {"ok": false, "entry": entry, "error": "mount failed %s" % abs_path}
			fn = dir.get_next()
		if not any:
			return {"ok": false, "entry": entry, "error": "no local packs"}
	else:
		return {"ok": false, "entry": entry, "error": "no packs dir"}
	return {"ok": true, "entry": entry}
