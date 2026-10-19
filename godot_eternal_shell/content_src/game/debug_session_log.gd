class_name DebugSessionLog
extends RefCounted
## Session NDJSON debug log (mobile-safe user:// + desktop H: mirror).

const SESSION_ID := "59aff0"
const USER_PATH := "user://debug-59aff0.log"
const DESKTOP_PATH := "H:/debug-59aff0.log"
const EXPORT_NAME := "debug-59aff0.log"


static func user_path() -> String:
	return USER_PATH


static func append(hypothesis_id: String, location: String, message: String, data: Dictionary = {}) -> void:
	var payload := {
		"sessionId": SESSION_ID,
		"hypothesisId": hypothesis_id,
		"location": location,
		"message": message,
		"data": data,
		"timestamp": Time.get_ticks_msec(),
		"runId": str(data.get("runId", "pre-fix")),
	}
	var line := JSON.stringify(payload)
	_append_to(USER_PATH, line)
	## Desktop / host mirror for Cursor debug ingest (fails silently on Android).
	if OS.has_feature("windows") or OS.has_feature("linux") or OS.has_feature("macos"):
		_append_to(DESKTOP_PATH, line)


static func _append_to(path: String, line: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(line)
	f.close()


static func read_text() -> String:
	var chunks: PackedStringArray = []
	if FileAccess.file_exists(USER_PATH):
		chunks.append(FileAccess.get_file_as_string(USER_PATH))
	if FileAccess.file_exists(DESKTOP_PATH):
		var desk := FileAccess.get_file_as_string(DESKTOP_PATH)
		if not desk.is_empty() and (chunks.is_empty() or desk != chunks[0]):
			chunks.append(desk)
	return "\n".join(chunks).strip_edges()


static func _try_clipboard(text: String) -> bool:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		return false
	DisplayServer.clipboard_set(text)
	if text.length() > 200000:
		return true
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