class_name UpdateClient
extends RefCounted

signal progress(message: String, fraction: float)

var _http: HTTPRequest
var _host: Node
## Boot「使用本地内容」：取消进行中的验版/下载。
var abort_requested := false


func _init(host: Node, http: HTTPRequest) -> void:
	_host = host
	_http = http


func request_abort() -> void:
	abort_requested = true
	if _http != null:
		_http.cancel_request()


static func format_bytes(n: int) -> String:
	var v := float(n)
	if v < 1024.0:
		return "%d B" % n
	if v < 1024.0 * 1024.0:
		return "%.1f KB" % (v / 1024.0)
	if v < 1024.0 * 1024.0 * 1024.0:
		return "%.2f MB" % (v / (1024.0 * 1024.0))
	return "%.2f GB" % (v / (1024.0 * 1024.0 * 1024.0))


static func format_speed(bps: float) -> String:
	if bps <= 0.0:
		return "—"
	return "%s/s" % format_bytes(int(bps))


func _log(msg: String) -> void:
	## Survives into Android logcat as "godot" / script prints.
	print("[UpdateClient] %s" % msg)


func http_get_text(url: String, timeout_sec: float = 30.0) -> Dictionary:
	if abort_requested:
		return {"ok": false, "text": "", "error": "aborted", "aborted": true}
	_http.timeout = timeout_sec
	_http.use_threads = true
	_disconnect_http_completed()
	var err := _http.request(url)
	if err != OK:
		return {"ok": false, "text": "", "error": "request failed: %s" % error_string(err)}
	var args: Array = await _http.request_completed
	if abort_requested:
		return {"ok": false, "text": "", "error": "aborted", "aborted": true}
	var result: int = args[0]
	var response_code: int = args[1]
	var body: PackedByteArray = args[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "text": "", "error": "http result %s" % result}
	if response_code < 200 or response_code >= 300:
		return {"ok": false, "text": "", "error": "HTTP %s" % response_code}
	return {"ok": true, "text": body.get_string_from_utf8(), "error": ""}


func _disconnect_http_completed() -> void:
	var conns: Array = _http.request_completed.get_connections()
	for c in conns:
		var callable: Callable = c["callable"]
		if _http.request_completed.is_connected(callable):
			_http.request_completed.disconnect(callable)


func http_get_bytes(url: String, timeout_sec: float = 300.0, label: String = "", file_i: int = 1, file_n: int = 1, base_frac: float = 0.2, span_frac: float = 0.6) -> Dictionary:
	## Progress via per-frame poll; completion via Dictionary (not bare bool — GDScript lambda trap)
	## + use_threads on HTTPRequest (Android: bytes-full without request_completed hang).
	_http.timeout = timeout_sec
	_http.use_threads = true
	_disconnect_http_completed()
	var state: Dictionary = {
		"done": false,
		"result": -1,
		"code": 0,
		"body": PackedByteArray(),
	}
	var on_done := func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		state["done"] = true
		state["result"] = result
		state["code"] = response_code
		state["body"] = body
		_log("http_get_bytes done code=%s bytes=%s url=%s" % [response_code, body.size(), url])
	_http.request_completed.connect(on_done, CONNECT_ONE_SHOT)
	_log("http_get_bytes start %s" % url)
	var err := _http.request(url)
	if err != OK:
		_disconnect_http_completed()
		return {"ok": false, "bytes": PackedByteArray(), "error": "request failed: %s" % error_string(err)}
	var last_got := 0
	var last_ms := Time.get_ticks_msec()
	var speed_ema := 0.0
	var full_since_ms := -1
	var started_ms := Time.get_ticks_msec()
	var name := label if not label.is_empty() else url.get_file()
	while not bool(state["done"]) and is_instance_valid(_host):
		await _host.get_tree().process_frame
		if abort_requested:
			_log("http_get_bytes aborted: %s" % name)
			_http.cancel_request()
			_disconnect_http_completed()
			return {"ok": false, "bytes": PackedByteArray(), "error": "aborted", "aborted": true}
		if bool(state["done"]):
			break
		var got := maxi(_http.get_downloaded_bytes(), 0)
		var total := _http.get_body_size()
		var now_ms := Time.get_ticks_msec()
		var dt := maxf((now_ms - last_ms) / 1000.0, 0.001)
		var dbytes := float(maxi(got - last_got, 0))
		var inst := dbytes / dt
		if dbytes > 0.0:
			speed_ema = lerpf(speed_ema, inst, 0.35) if speed_ema > 0.0 else inst
		last_got = got
		last_ms = now_ms
		var file_frac := 0.0
		if total > 0:
			file_frac = clampf(float(got) / float(total), 0.0, 1.0)
		elif got > 0:
			file_frac = 0.5
		var overall := base_frac + span_frac * ((float(file_i - 1) + file_frac) / float(maxi(file_n, 1)))
		var size_txt := format_bytes(got)
		if total > 0:
			size_txt = "%s / %s" % [format_bytes(got), format_bytes(total)]
		var phase := "下载"
		if total > 0 and got >= total and not bool(state["done"]):
			phase = "收尾"
			if full_since_ms < 0:
				full_since_ms = now_ms
				_log("bytes full (%s/%s) waiting request_completed…" % [got, total])
			elif now_ms - full_since_ms > 5000:
				_log("STALL: full body 5s without request_completed — cancel")
				_http.cancel_request()
				_disconnect_http_completed()
				return {
					"ok": false,
					"bytes": PackedByteArray(),
					"error": "download stall after 100%% (no request_completed): %s" % name,
				}
		progress.emit(
			"%s %s\n文件 %d/%d · %s · 网速 %s" % [phase, name, file_i, file_n, size_txt, format_speed(speed_ema)],
			overall
		)
		if now_ms - started_ms > int(timeout_sec * 1000.0) + 5000:
			_log("STALL: overall timeout")
			_http.cancel_request()
			_disconnect_http_completed()
			return {"ok": false, "bytes": PackedByteArray(), "error": "download timeout: %s" % name}
	if not bool(state["done"]):
		return {"ok": false, "bytes": PackedByteArray(), "error": "host invalid during download"}
	progress.emit("下载完成 %s" % name, base_frac + span_frac * (float(file_i) / float(maxi(file_n, 1))))
	var out_result: int = int(state["result"])
	var out_code: int = int(state["code"])
	var out_body: PackedByteArray = state["body"]
	if out_result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "bytes": PackedByteArray(), "error": "http result %s" % out_result}
	if out_code < 200 or out_code >= 300:
		return {"ok": false, "bytes": PackedByteArray(), "error": "HTTP %s" % out_code}
	return {"ok": true, "bytes": out_body, "error": ""}


func fetch_version_json_from_candidates(urls: PackedStringArray) -> Dictionary:
	for base in urls:
		UpdateConfig.apply_remote_base_url(base)
		progress.emit("检查版本…", 0.05)
		var res := await http_get_text(UpdateConfig.version_url())
		if res.get("ok", false):
			var data = JSON.parse_string(res["text"])
			if typeof(data) == TYPE_DICTIONARY and not bool(data.get("pointerOnly", false)):
				return {"ok": true, "data": data, "error": ""}
		progress.emit("源失败: %s" % res.get("error", ""), 0.05)
	## GitHub pointer = static discovery only (RELEASE_AND_HOTUPDATE §2.3).
	## Never use pointer's content version for compare — re-resolve from baseUrl (HF).
	progress.emit("尝试 GitHub 指针…", 0.08)
	var ptr := await http_get_text(UpdateConfig.GITHUB_POINTER_VERSION_URL)
	if ptr.get("ok", false):
		var data2 = JSON.parse_string(ptr["text"])
		if typeof(data2) == TYPE_DICTIONARY:
			var ptr_base := str(data2.get("baseUrl", "")).strip_edges()
			if ptr_base.is_empty() and UpdateConfig.DEFAULT_BASE_URLS.size() > 0:
				ptr_base = UpdateConfig.DEFAULT_BASE_URLS[0]
			if not ptr_base.is_empty():
				UpdateConfig.apply_remote_base_url(ptr_base)
				progress.emit("指针 → 回拉权威 version…", 0.09)
				var res_hf := await http_get_text(UpdateConfig.version_url())
				if res_hf.get("ok", false):
					var data_hf = JSON.parse_string(res_hf["text"])
					if typeof(data_hf) == TYPE_DICTIONARY and not bool(data_hf.get("pointerOnly", false)):
						return {"ok": true, "data": data_hf, "error": ""}
				progress.emit("指针 baseUrl 验版失败: %s" % res_hf.get("error", ""), 0.09)
	return {"ok": false, "data": {}, "error": "all version sources failed"}


func read_applied_version() -> String:
	var path := UpdateConfig.applied_version_path()
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if typeof(data) == TYPE_DICTIONARY and data.has("version"):
		return str(data["version"])
	return txt.strip_edges()


func write_applied_version(version: String, entry: String) -> void:
	UpdateConfig.ensure_dirs()
	var path := UpdateConfig.applied_version_path()
	var payload := {
		"version": version,
		"entry": entry,
		"appliedAt": Time.get_datetime_string_from_system(true),
		"platform": UpdateConfig.get_platform_id(),
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_log("write_applied_version FAILED path=%s" % path)
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	_log("write_applied_version ok %s" % version)


func plan_downloads(files: Array, platform_id: String) -> Dictionary:
	## { items: Array, bytes: int, count: int }
	var items: Array = []
	var bytes := 0
	for item in files:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var path := str(item.get("path", ""))
		if path.is_empty():
			continue
		if not UpdateConfig.is_manifest_path_wanted(path, platform_id):
			continue
		var kind := str(item.get("kind", "pack"))
		var need := true
		if kind == "data" and _data_presence_complete(item):
			need = false
			_log("skip data pack (presence complete): %s" % path)
		else:
			var expect_hash: String = str(item.get("sha256", "")).to_lower()
			var local_path := UpdateConfig.runtime_file_path(path)
			if FileAccess.file_exists(local_path) and not expect_hash.is_empty():
				if Sha256Util.file_sha256(local_path).to_lower() == expect_hash:
					need = false
		if need:
			items.append(item)
			bytes += int(item.get("size", 0))
	return {"items": items, "bytes": bytes, "count": items.size()}


func _data_presence_complete(item: Dictionary) -> bool:
	## RELEASE_AND_HOTUPDATE §2.1 — skip data.pck when all requiredRelPaths exist on disk.
	var req: Variant = item.get("requiredRelPaths", [])
	if typeof(req) != TYPE_ARRAY or (req as Array).is_empty():
		return false
	for rel_v in req as Array:
		var rel := str(rel_v).replace("\\", "/").lstrip("/")
		if rel.is_empty():
			return false
		var runtime := UpdateConfig.CONTENT_RUNTIME_DIR.path_join("data").path_join(rel)
		if not FileAccess.file_exists(runtime):
			return false
	return true


func force_fetch_and_apply_data_pack(files: Array, platform_id: String) -> Dictionary:
	## Editor escape hatch: download data.pck ignoring presence, mount it, force-reseed ships/equipment.
	var data_item: Dictionary = {}
	for item in files:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if str(item.get("kind", "")) != "data":
			continue
		var path := str(item.get("path", ""))
		if path.is_empty() or not UpdateConfig.is_manifest_path_wanted(path, platform_id):
			continue
		data_item = item
		break
	if data_item.is_empty():
		return {"ok": false, "error": "manifest has no kind=data pack"}
	var path: String = str(data_item.get("path", ""))
	var expect_hash: String = str(data_item.get("sha256", "")).to_lower()
	var local_path := UpdateConfig.runtime_file_path(path)
	progress.emit("强制拉取默认舰船/装备数据…", 0.1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(local_path.get_base_dir()))
	var url := UpdateConfig.file_url(path)
	var got := await http_get_bytes(url, 300.0, path.get_file(), 1, 1, 0.1, 0.7)
	if not got.get("ok", false):
		return {"ok": false, "error": "download %s: %s" % [path, got.get("error", "")]}
	var bytes: PackedByteArray = got["bytes"]
	if not expect_hash.is_empty():
		var h := Sha256Util.bytes_sha256(bytes).to_lower()
		if h != expect_hash:
			return {"ok": false, "error": "sha256 mismatch %s" % path}
	var wf := FileAccess.open(local_path, FileAccess.WRITE)
	if wf == null:
		return {"ok": false, "error": "cannot write %s" % local_path}
	wf.store_buffer(bytes)
	wf.close()
	progress.emit("挂载 data.pck…", 0.85)
	var abs_path := ProjectSettings.globalize_path(local_path)
	var mounted := ProjectSettings.load_resource_pack(abs_path, true)
	if not mounted:
		mounted = ProjectSettings.load_resource_pack(local_path, true)
	if not mounted:
		return {"ok": false, "error": "load_resource_pack failed: %s" % abs_path}
	var seed_res: Dictionary = ContentRuntimeData.force_reseed_ships_equipment_unmanned()
	_log("force_reseed wrote=%s" % seed_res.get("wrote", 0))
	progress.emit("默认数据已覆盖本地", 1.0)
	return {"ok": true, "error": "", "wrote": int(seed_res.get("wrote", 0))}


func download_manifest_files(files: Array, platform_id: String) -> Dictionary:
	var plan := plan_downloads(files, platform_id)
	var wanted: Array = plan["items"]
	var total := wanted.size()
	if total == 0:
		progress.emit("无需下载，本地已完整", 0.8)
		return {"ok": true, "error": "", "downloaded": 0}
	var total_bytes: int = int(plan["bytes"])
	progress.emit(
		"准备下载 %d 个文件 · 约 %s" % [total, format_bytes(total_bytes)],
		0.2
	)
	var downloaded := 0
	var i := 0
	for item in wanted:
		if abort_requested:
			return {"ok": false, "error": "aborted", "aborted": true, "downloaded": downloaded}
		i += 1
		var path: String = str(item.get("path", ""))
		var expect_hash: String = str(item.get("sha256", "")).to_lower()
		var local_path := UpdateConfig.runtime_file_path(path)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(local_path.get_base_dir()))
		var url := UpdateConfig.file_url(path)
		var got := await http_get_bytes(url, 300.0, path.get_file(), i, total, 0.2, 0.65)
		if not got.get("ok", false):
			var err_payload := {
				"ok": false,
				"error": "download %s: %s" % [path, got.get("error", "")],
				"downloaded": downloaded,
			}
			if got.get("aborted", false):
				err_payload["aborted"] = true
				err_payload["error"] = "aborted"
			return err_payload
		var bytes: PackedByteArray = got["bytes"]
		progress.emit("校验 %s…" % path.get_file(), 0.2 + 0.65 * (float(i) / float(total)) - 0.01)
		if not expect_hash.is_empty():
			var h := Sha256Util.bytes_sha256(bytes).to_lower()
			if h != expect_hash:
				_log("sha256 mismatch %s got=%s expect=%s" % [path, h, expect_hash])
				return {"ok": false, "error": "sha256 mismatch %s" % path, "downloaded": downloaded}
		progress.emit("写入 %s…" % path.get_file(), 0.2 + 0.65 * (float(i) / float(total)))
		var wf := FileAccess.open(local_path, FileAccess.WRITE)
		if wf == null:
			return {"ok": false, "error": "cannot write %s" % local_path, "downloaded": downloaded}
		wf.store_buffer(bytes)
		wf.close()
		_log("wrote %s (%s bytes)" % [local_path, bytes.size()])
		downloaded += 1
	return {"ok": true, "error": "", "downloaded": downloaded}


func mount_packs(files: Array, platform_id: String) -> Dictionary:
	var packs: Array = []
	for item in files:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var path := str(item.get("path", ""))
		var kind := str(item.get("kind", "pack"))
		if not UpdateConfig.is_manifest_path_wanted(path, platform_id):
			continue
		if kind != "pack" and kind != "data":
			continue
		var local := UpdateConfig.runtime_file_path(path)
		if kind == "data" and not FileAccess.file_exists(local) and _data_presence_complete(item):
			_log("skip mount data pack (presence complete, no local pck): %s" % path)
			continue
		var order := int(item.get("mountOrder", 10))
		packs.append({"path": path, "order": order})
	packs.sort_custom(func(a, b): return int(a["order"]) < int(b["order"]))
	if packs.is_empty():
		return {"ok": false, "error": "no pack entries for this platform in manifest"}
	for p in packs:
		var local2 := UpdateConfig.runtime_file_path(str(p["path"]))
		if not FileAccess.file_exists(local2):
			return {"ok": false, "error": "missing pack %s" % local2}
		var abs_path := ProjectSettings.globalize_path(local2)
		progress.emit("挂载 %s" % p["path"], 0.9)
		_log("load_resource_pack local=%s abs=%s" % [local2, abs_path])
		var ok := ProjectSettings.load_resource_pack(abs_path, true)
		if not ok:
			# Fallback: some builds accept user:// directly
			ok = ProjectSettings.load_resource_pack(local2, true)
		if not ok:
			_log("load_resource_pack FAILED")
			return {"ok": false, "error": "load_resource_pack failed: %s" % abs_path}
		_log("load_resource_pack OK")
		if str(p["path"]).contains("audio"):
			_log("audio pack mounted: %s" % p["path"])
	return {"ok": true, "error": ""}


func has_local_content_ready() -> bool:
	## applied_version alone is not enough — need at least one pack on disk.
	var applied := read_applied_version()
	if applied.is_empty():
		return false
	var packs_dir := UpdateConfig.CONTENT_RUNTIME_DIR.path_join("packs")
	var dir := DirAccess.open(packs_dir)
	if dir == null:
		return false
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and (fn.ends_with(".pck") or fn.ends_with(".zip")):
			dir.list_dir_end()
			return true
		fn = dir.get_next()
	dir.list_dir_end()
	return false


func entry_resource_exists(entry: String) -> bool:
	if entry.is_empty():
		return false
	return ResourceLoader.exists(entry)
