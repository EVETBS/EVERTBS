class_name DebugSessionLog
extends RefCounted
## Session NDJSON debug log (mobile-safe user:// + desktop H: mirror).

const SESSION_ID := "59aff0"
const USER_PATH := "user://debug-59aff0.log"
const DESKTOP_PATH := "H:/debug-59aff0.log"
const EXPORT_NAME := "debug-59aff0.log"
const ALIVE_PATH := "user://debug-59aff0.alive"

static var _in_log := false
static var _scaffold_on := false
static var _board: Node = null


static func user_path() -> String:
	return USER_PATH


static func append(hypothesis_id: String, location: String, message: String, data: Dictionary = {}) -> void:
	if _in_log:
		return
	_in_log = true
	var payload := {
		"sessionId": SESSION_ID,
		"hypothesisId": hypothesis_id,
		"location": location,
		"message": message,
		"data": data,
		"timestamp": Time.get_ticks_msec(),
		"unix": Time.get_unix_time_from_system(),
		"runId": str(data.get("runId", "pre-fix")),
	}
	var line := JSON.stringify(payload)
	_append_to(USER_PATH, line)
	#（半暴露到 logcat，adb 不用先点导出）26.10.22 15:50 s
	var shown := line
	if shown.length() > 700:
		shown = shown.substr(0, 700)
	print("[EVERTBSDBG] %s" % shown)
	#（半暴露到 logcat，adb 不用先点导出）26.10.22 15:50 e
	## Desktop / host mirror for Cursor debug ingest (fails silently on Android).
	if OS.has_feature("windows") or OS.has_feature("linux") or OS.has_feature("macos"):
		_append_to(DESKTOP_PATH, line)
		#（本会话寻路与特效锚点证据）26.10.22 20:10 s
		_append_to("H:/debug-111fa6.log", line)
		#（本会话寻路与特效锚点证据）26.10.22 20:10 e
	_in_log = false


static func _append_to(path: String, line: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(line)
	#（续写立刻落盘，进程被杀掉仍留得住上一行）26.10.22 13:08 s
	f.flush()
	#（续写立刻落盘，进程被杀掉仍留得住上一行）26.10.22 13:08 e
	f.close()


static func install_scaffold() -> void:
	if _scaffold_on:
		return
	_scaffold_on = true
	var prior := ""
	var unclean := FileAccess.file_exists(ALIVE_PATH)
	if unclean:
		prior = FileAccess.get_file_as_string(ALIVE_PATH).strip_edges()
	var prior_bytes := 0
	if FileAccess.file_exists(USER_PATH):
		var existing := FileAccess.open(USER_PATH, FileAccess.READ)
		if existing:
			prior_bytes = existing.get_length()
			existing.close()
	var stamp := "%s mem=%d" % [_version_text(), OS.get_static_memory_usage()]
	var alive := FileAccess.open(ALIVE_PATH, FileAccess.WRITE)
	if alive:
		alive.store_string(stamp)
		alive.flush()
		alive.close()
	#（启动续写，不覆盖旧日志）26.10.22 13:08 s
	append("BOOT", "debug_session_log.install_scaffold", "continue", {
		"prior_bytes": prior_bytes,
		"unclean": unclean,
		"prior": prior,
		"version": _version_text(),
		"mem": OS.get_static_memory_usage(),
		"runId": "crash-scaffold",
	})
	#（启动续写，不覆盖旧日志）26.10.22 13:08 e
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var node := Scaffold.new()
		node.name = "DebugScaffold"
		(loop as SceneTree).root.add_child(node)
	OS.add_logger(ErrorHook.new())


static func bind_board(board: Node) -> void:
	_board = board


static func mark_clean(reason: String) -> void:
	if FileAccess.file_exists(ALIVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ALIVE_PATH))
	append("BOOT", "debug_session_log.mark_clean", "clean_exit", {
		"reason": reason,
		"runId": "crash-scaffold",
	})


static func _version_text() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


class ErrorHook extends Logger:
	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		_error_type: int,
		script_backtraces: Array
	) -> void:
		var bt := ""
		for entry in script_backtraces:
			bt += str(entry)
		#（脚本错误写入同一条续写日志）26.10.22 13:08 s
		DebugSessionLog.append("ERR", file, rationale, {
			"fn": function,
			"line": line,
			"code": code,
			"bt": bt,
			"runId": "crash-scaffold",
		})
		#（脚本错误写入同一条续写日志）26.10.22 13:08 e


class Scaffold extends Node:
	var _acc := 0.0
	var _max_dt := 0.0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _notification(what: int) -> void:
		if what == NOTIFICATION_WM_CLOSE_REQUEST:
			DebugSessionLog.mark_clean("wm_close")

	func _process(delta: float) -> void:
		_acc += delta
		_max_dt = maxf(_max_dt, delta)
		if _acc < 1.0:
			return
		var max_dt := _max_dt
		_acc = 0.0
		_max_dt = 0.0
		var alive := -1
		var units_n := -1
		var board := DebugSessionLog._board
		if board != null and is_instance_valid(board) and board.get("units") is Array:
			var arr: Array = board.units
			units_n = arr.size()
			alive = 0
			for u in arr:
				if u is Dictionary and bool((u as Dictionary).get("alive", false)):
					alive += 1
		DebugSessionLog.append("BEAT", "debug_session_log.Scaffold", "heartbeat", {
			"alive": alive,
			"units": units_n,
			"mem": OS.get_static_memory_usage(),
			"fps": Engine.get_frames_per_second(),
			"max_dt_ms": snappedf(max_dt * 1000.0, 0.1),
			"version": DebugSessionLog._version_text(),
			"runId": "crash-scaffold",
		})


static func read_text() -> String:
	var chunks: PackedStringArray = []
	if FileAccess.file_exists(USER_PATH):
		chunks.append(FileAccess.get_file_as_string(USER_PATH))
	if FileAccess.file_exists(DESKTOP_PATH):
		var desk := FileAccess.get_file_as_string(DESKTOP_PATH)
		if not desk.is_empty() and (chunks.is_empty() or desk != chunks[0]):
			chunks.append(desk)
	return "\n".join(chunks).strip_edges()


const CLIP_MAX_BYTES := 256 * 1024


static func _try_clipboard(text: String) -> bool:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		return false
	#（大日志不进剪贴板）26.10.22 12:45 s
	if text.to_utf8_buffer().size() > CLIP_MAX_BYTES:
		return false
	#（大日志不进剪贴板）26.10.22 12:45 e
	DisplayServer.clipboard_set(text)
	return DisplayServer.clipboard_get().length() > 0


static func export_now() -> Dictionary:
	## Copy to Downloads + clipboard. Returns {ok, path, bytes, lines, error, clipboard}.
	var text := read_text()
	if text.is_empty():
		return {
			"ok": false,
			"path": "",
			"bytes": 0,
			"lines": 0,
			"error": "尚无日志（请先在本机操作产生触摸/镜头事件）",
			"clipboard": false,
		}
	var lines := text.count("\n") + 1
	var bytes := text.to_utf8_buffer().size()
	var dest_dir := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if dest_dir.is_empty():
		dest_dir = OS.get_user_data_dir()
	var dest := dest_dir.path_join(EXPORT_NAME)
	var out := FileAccess.open(dest, FileAccess.WRITE)
	if out == null:
		dest = ProjectSettings.globalize_path(USER_PATH)
		var clip_ok_fb := _try_clipboard(text)
		return {
			"ok": true,
			"path": dest,
			"bytes": bytes,
			"lines": lines,
			"error": "无法写入下载目录，已尽量复制到剪贴板；源路径见 path",
			"clipboard": clip_ok_fb,
		}
	out.store_string(text)
	out.close()
	var clip_ok := _try_clipboard(text)
	return {
		"ok": true,
		"path": dest,
		"bytes": bytes,
		"lines": lines,
		"error": "",
		"clipboard": clip_ok,
	}


static func format_result(res: Dictionary) -> String:
	if not bool(res.get("ok", false)):
		return str(res.get("error", "导出失败"))
	var parts: PackedStringArray = [
		"已导出 debug 日志",
		"路径: %s" % str(res.get("path", "")),
		"约 %d 字节 / %d 行" % [int(res.get("bytes", 0)), int(res.get("lines", 0))],
	]
	if bool(res.get("clipboard", false)):
		parts.append("全文已尽量复制到剪贴板")
	var err := str(res.get("error", ""))
	if not err.is_empty():
		parts.append(err)
	return "\n".join(parts)