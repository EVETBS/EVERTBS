extends RefCounted
class_name CustomMemberPack
## Drafts, confirmed SR rows, and one-csv zip packs.

const MemberTableScr := preload("res://game/board/pilots/member_table.gd")
const CrewRankScr := preload("res://game/board/pilots/crew_rank.gd")
const SEQ_PATH := "user://content_runtime/data/board/custom_seq.json"
const MEDIA_DIR := "user://content_runtime/data/board/custom_members"
const CAP_MSG := "加成绝对值相加不能超过%50"

static var last_error := ""
static var _gif_delay: Array = []
static var _gif_bad := ""

static func list_drafts() -> Array:
	var out: Array = []
	DirAccess.make_dir_recursive_absolute(MemberTableScr.DRAFT_DIR)
	var dir := DirAccess.open(MemberTableScr.DRAFT_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [MemberTableScr.DRAFT_DIR, name]))
			if typeof(parsed) == TYPE_DICTIONARY:
				out.append(parsed)
		name = dir.get_next()
	dir.list_dir_end()
	return out


static func save_draft(row: Dictionary) -> void:
	var mid := str(row.get("id", "")).strip_edges()
	if mid == "":
		return
	DirAccess.make_dir_recursive_absolute(MemberTableScr.DRAFT_DIR)
	var f := FileAccess.open("%s/%s.json" % [MemberTableScr.DRAFT_DIR, mid], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(row))


static func delete_draft(member_id: String) -> void:
	var path := "%s/%s.json" % [MemberTableScr.DRAFT_DIR, member_id]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func alloc_local_id() -> String:
	var seq := _read_seq()
	var n := int(seq.get("local", 1))
	if n > 9999:
		last_error = "本机自定义编号已到 9999"
		return ""
	var mid := "00%04d" % n
	var used := _used_ids()
	while used.has(mid):
		n += 1
		if n > 9999:
			last_error = "本机自定义编号已到 9999"
			return ""
		mid = "00%04d" % n
	seq["local"] = n + 1
	_write_seq(seq)
	last_error = ""
	return mid


static func _six_digits(mid: String) -> bool:
	if mid.length() != 6:
		return false
	for i in mid.length():
		var c := mid.unicode_at(i)
		if c < 48 or c > 57:
			return false
	return true


static func fit_bonus(row: Dictionary) -> void:
	#（读入时按比例缩小超限加成）26.10.22 01:52 s
	var keys: PackedStringArray = PackedStringArray()
	var muls: Array = []
	var acc := 0.0
	var dropped_hp := false
	for part in str(row.get("bonus", "")).split("|", false):
		var piece := str(part).strip_edges()
		var cut := piece.find("=")
		if cut <= 0:
			continue
		var key := piece.substr(0, cut).strip_edges()
		var raw := piece.substr(cut + 1).strip_edges()
		if not raw.is_valid_float():
			continue
		#（读入时丢掉血量加成）26.10.22 11:25 s
		if key == "hp_mul":
			dropped_hp = true
			continue
		#（读入时丢掉血量加成）26.10.22 11:25 e
		var mul := float(raw)
		if not is_finite(mul):
			continue
		acc += absf(mul - 1.0)
		keys.append(key)
		muls.append(mul)
	if acc <= 0.5 or keys.is_empty():
		if dropped_hp:
			var kept := PackedStringArray()
			for i in keys.size():
				kept.append("%s=%.4f" % [keys[i], float(muls[i])])
			row["bonus"] = "|".join(kept)
		return
	var k := 0.5 / acc
	var out: PackedStringArray = PackedStringArray()
	for i in keys.size():
		var scaled := 1.0 + (float(muls[i]) - 1.0) * k
		out.append("%s=%.4f" % [keys[i], scaled])
	row["bonus"] = "|".join(out)
	#（读入时按比例缩小超限加成）26.10.22 01:52 e


static func reject_reason(row: Dictionary) -> String:
	var mid := str(row.get("id", "")).strip_edges()
	#（自定义编号必须逐位是数字）26.10.22 01:52 s
	if not _six_digits(mid):
		return "自定义编号必须是六位数字"
	#（自定义编号必须逐位是数字）26.10.22 01:52 e
	for part in str(row.get("bonus", "")).split("|", false):
		var piece := str(part).strip_edges()
		var cut := piece.find("=")
		if cut <= 0:
			continue
		var key := piece.substr(0, cut).strip_edges()
		#（血量字段不再拒绝整行）26.10.22 11:25 s
		if key == "hp_mul":
			continue
		#（血量字段不再拒绝整行）26.10.22 11:25 e
		if not CrewRankScr.EFFECT_KEYS.has(key):
			return CAP_MSG
		var raw := piece.substr(cut + 1).strip_edges()
		if not raw.is_valid_float() or not is_finite(float(raw)):
			return CAP_MSG
	return ""


static func confirm_row(row: Dictionary) -> String:
	var why := reject_reason(row)
	if why == "":
		fit_bonus(row)
	if why != "":
		last_error = why
		return why
	for spec in [
		["portrait_b64", "portrait_mime", "portrait", "portrait"],
		["name_media_b64", "name_media_mime", "name_media", "name"],
		["bio_media_b64", "bio_media_mime", "bio_media", "bio"],
	]:
		why = _materialize_one(row, str(spec[0]), str(spec[1]), str(spec[2]), str(spec[3]))
		if why != "":
			last_error = why
			return why
	var mid := str(row.get("id", ""))
	var rows: Array = MemberTableScr.load_merged()
	var replaced := false
	for i in rows.size():
		if str(rows[i].get("id", "")) == mid:
			rows[i] = row.duplicate(true)
			replaced = true
			break
	if not replaced:
		rows.append(row.duplicate(true))
	MemberTableScr.write_rows(MemberTableScr._headers_of(rows), rows)
	delete_draft(mid)
	last_error = ""
	return ""


static func portable_row(row: Dictionary) -> Dictionary:
	var out := row.duplicate(true)
	_attach_file(out, "portrait", "portrait_b64", "portrait_mime")
	_attach_file(out, "name_media", "name_media_b64", "name_media_mime")
	_attach_file(out, "bio_media", "bio_media_b64", "bio_media_mime")
	return out


static func export_zip(row: Dictionary, zip_path: String) -> bool:
	var packed := portable_row(row)
	var header := PackedStringArray([
		"id", "name", "portrait", "bio", "rank", "bonus", "ships", "default_ship", "pref_eq",
		"portrait_b64", "portrait_mime", "name_media_b64", "name_media_mime", "bio_media_b64", "bio_media_mime",
	])
	var cells := PackedStringArray()
	for key in header:
		cells.append(_csv_escape(str(packed.get(key, ""))))
	var csv := ",".join(header) + "\n" + ",".join(cells) + "\n"
	var writer := ZIPPacker.new()
	if writer.open(zip_path) != OK:
		return false
	writer.start_file("member.csv")
	writer.write_file(csv.to_utf8_buffer())
	writer.close_file()
	writer.close()
	return true


static func import_zip(zip_path: String) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return {}
	var csv := ""
	for name in reader.get_files():
		if str(name).ends_with(".csv"):
			csv = reader.read_file(name).get_string_from_utf8()
			break
	reader.close()
	if csv == "":
		return {}
	var rows: Array = MemberTableScr.rows_from_text(csv)
	if rows.is_empty():
		return {}
	var row: Dictionary = rows[0]
	var seq := _read_seq()
	var n := int(seq.get("imports", 0)) + 1
	if n > 99:
		last_error = "导入次数已到 99"
		return {}
	var prefix := "%02d" % n
	var tail := str(row.get("id", "0000"))
	if tail.length() >= 4:
		tail = tail.substr(tail.length() - 4)
	else:
		tail = tail.pad_zeros(4)
	if not tail.is_valid_int():
		last_error = "自定义编号必须是六位数字"
		return {}
	var used := _used_ids()
	var mid := ""
	var base := int(tail)
	for bump in 10000:
		var candidate := prefix + ("%04d" % ((base + bump) % 10000))
		if not used.has(candidate):
			mid = candidate
			break
	if mid == "":
		last_error = "这一批编号已满"
		return {}
	row["id"] = mid
	row["rank"] = "SR"
	if confirm_row(row) != "":
		return {}
	seq["imports"] = n
	_write_seq(seq)
	return row


static func scale_image_bytes(bytes: PackedByteArray, mime: String) -> Dictionary:
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if mime.find("png") >= 0:
		err = img.load_png_from_buffer(bytes)
	elif mime.find("jpeg") >= 0 or mime.find("jpg") >= 0:
		err = img.load_jpg_from_buffer(bytes)
	elif mime.find("webp") >= 0:
		err = img.load_webp_from_buffer(bytes)
	elif mime.find("gif") >= 0:
		return _gif_bytes(bytes)
	if err != OK:
		err = img.load_png_from_buffer(bytes)
	if err != OK:
		return {"bytes": PackedByteArray(), "mime": mime, "error": "动图无法完整还原"}
	var longest := maxi(img.get_width(), img.get_height())
	if longest > 340:
		var scale := 340.0 / float(longest)
		img.resize(maxi(1, int(img.get_width() * scale)), maxi(1, int(img.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	return {"bytes": img.save_png_to_buffer(), "mime": "image/png"}


static func _gif_bytes(bytes: PackedByteArray) -> Dictionary:
	var frames := _decode_gif(bytes)
	if _gif_bad != "" or frames.is_empty():
		return {"bytes": PackedByteArray(), "mime": "", "error": "动图无法完整还原"}
	var first: Image = frames[0]
	var longest := maxi(first.get_width(), first.get_height())
	var scale := 1.0
	if longest > 340:
		scale = 340.0 / float(longest)
	for i in frames.size():
		var fr: Image = frames[i]
		if scale < 1.0:
			fr.resize(maxi(1, int(fr.get_width() * scale)), maxi(1, int(fr.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	if frames.size() == 1:
		return {"bytes": (frames[0] as Image).save_png_to_buffer(), "mime": "image/png"}
	var stamp := Time.get_ticks_msec()
	var dir := "%s/gif_%d" % [MEDIA_DIR, stamp]
	DirAccess.make_dir_recursive_absolute(dir)
	var paths: Array = []
	var delays: Array = []
	for i in frames.size():
		var fp := "%s/f%d.png" % [dir, i]
		(frames[i] as Image).save_png(fp)
		paths.append(fp)
		var delay := 0.1
		if i < _gif_delay.size():
			delay = float(_gif_delay[i])
		if delay <= 0.0:
			delay = 0.1
		delays.append(delay)
	var meta := "%s/portrait.json" % dir
	var f := FileAccess.open(meta, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"frames": paths, "delays": delays}))
	return {"bytes": PackedByteArray(), "mime": "application/x-evertbs-anim", "anim_path": meta}


static func _decode_gif(bytes: PackedByteArray) -> Array:
	## Non-interlaced GIF89a frames. Empty when the file is not that subset.
	_gif_bad = ""
	_gif_delay = []
	if bytes.size() < 13 or bytes.slice(0, 6).get_string_from_ascii() != "GIF89a" and bytes.slice(0, 6).get_string_from_ascii() != "GIF87a":
		_gif_bad = "动图无法完整还原"
		return []
	var pos := 13
	var packed := bytes[10]
	var gct := bool(packed & 0x80)
	var gct_n := 0
	var global: PackedColorArray = PackedColorArray()
	if gct:
		gct_n = 1 << ((packed & 0x07) + 1)
		global = _read_palette(bytes, pos, gct_n)
		pos += gct_n * 3
	var frames: Array = []
	var transparent := -1
	var pending := 0.1
	var disposal := 0
	while pos < bytes.size():
		var b := bytes[pos]
		pos += 1
		if b == 0x3B:
			break
		if b == 0x21:
			if pos >= bytes.size():
				break
			var label := bytes[pos]
			pos += 1
			if label == 0xF9 and pos + 6 <= bytes.size():
				var block := bytes[pos]
				if block >= 4:
					var flags := bytes[pos + 1]
					var cs := bytes[pos + 2] | (bytes[pos + 3] << 8)
					if cs > 0:
						pending = float(cs) / 100.0
					disposal = (flags >> 2) & 0x07
					if flags & 0x01:
						transparent = bytes[pos + 4]
				pos = _skip_subblocks(bytes, pos)
			else:
				pos = _skip_subblocks(bytes, pos)
			continue
		if b != 0x2C or pos + 9 > bytes.size():
			break
		#（画布偏移或局部覆盖的 GIF 拒绝还原）26.10.22 01:52 s
		var left := bytes[pos] | (bytes[pos + 1] << 8)
		var top := bytes[pos + 2] | (bytes[pos + 3] << 8)
		var w := bytes[pos + 4] | (bytes[pos + 5] << 8)
		var h := bytes[pos + 6] | (bytes[pos + 7] << 8)
		var canvas_w := bytes[6] | (bytes[7] << 8)
		var canvas_h := bytes[8] | (bytes[9] << 8)
		if left != 0 or top != 0 or w != canvas_w or h != canvas_h or disposal == 2 or disposal == 3:
			_gif_bad = "动图无法完整还原"
			return []
		#（画布偏移或局部覆盖的 GIF 拒绝还原）26.10.22 01:52 e
		var ip := bytes[pos + 8]
		pos += 9
		if ip & 0x40:
			_gif_bad = "动图无法完整还原"
			return []
		var pal := global
		if ip & 0x80:
			var n := 1 << ((ip & 0x07) + 1)
			pal = _read_palette(bytes, pos, n)
			pos += n * 3
		if pos >= bytes.size():
			break
		var min_code := bytes[pos]
		pos += 1
		var lzw := PackedByteArray()
		while pos < bytes.size():
			var sz := bytes[pos]
			pos += 1
			if sz == 0:
				break
			if pos + sz > bytes.size():
				return frames
			lzw.append_array(bytes.slice(pos, pos + sz))
			pos += sz
		var indices := _lzw(lzw, min_code, w * h)
		if indices.size() < w * h:
			continue
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var idx := indices[y * w + x]
				var col := Color(0, 0, 0, 0)
				if idx != transparent and idx >= 0 and idx < pal.size():
					col = pal[idx]
				img.set_pixel(x, y, col)
		frames.append(img)
		_gif_delay.append(pending)
		pending = 0.1
		if frames.size() >= 32:
			var rest := pos
			while rest < bytes.size():
				if bytes[rest] == 0x3B:
					break
				if bytes[rest] == 0x2C:
					_gif_bad = "动图无法完整还原"
					return []
				rest += 1
			break
	if frames.is_empty():
		_gif_bad = "动图无法完整还原"
	return frames


static func _read_palette(bytes: PackedByteArray, pos: int, n: int) -> PackedColorArray:
	var pal := PackedColorArray()
	for i in n:
		var o := pos + i * 3
		if o + 2 >= bytes.size():
			pal.append(Color.BLACK)
		else:
			pal.append(Color(bytes[o] / 255.0, bytes[o + 1] / 255.0, bytes[o + 2] / 255.0))
	return pal


static func _skip_subblocks(bytes: PackedByteArray, pos: int) -> int:
	while pos < bytes.size():
		var sz := bytes[pos]
		pos += 1 + sz
		if sz == 0:
			break
	return pos


static func _lzw(data: PackedByteArray, min_code: int, expected: int) -> PackedByteArray:
	var clear := 1 << min_code
	var end := clear + 1
	var code_size := min_code + 1
	var dict: Array = []
	for i in clear:
		dict.append(PackedByteArray([i]))
	dict.append(PackedByteArray())
	dict.append(PackedByteArray())
	var out := PackedByteArray()
	var bit := 0
	var prev := -1
	while out.size() < expected and bit / 8 < data.size():
		var code := _read_bits(data, bit, code_size)
		bit += code_size
		if code == clear:
			dict = []
			for i in clear:
				dict.append(PackedByteArray([i]))
			dict.append(PackedByteArray())
			dict.append(PackedByteArray())
			code_size = min_code + 1
			prev = -1
			continue
		if code == end:
			break
		var entry := PackedByteArray()
		if code < dict.size() and not (dict[code] as PackedByteArray).is_empty():
			entry = dict[code]
		elif prev >= 0 and prev < dict.size():
			entry = (dict[prev] as PackedByteArray).duplicate()
			if not entry.is_empty():
				entry.append(entry[0])
		else:
			break
		out.append_array(entry)
		if prev >= 0 and prev < dict.size():
			var neu: PackedByteArray = (dict[prev] as PackedByteArray).duplicate()
			if not entry.is_empty():
				neu.append(entry[0])
			dict.append(neu)
			if dict.size() == (1 << code_size) and code_size < 12:
				code_size += 1
		prev = code
	return out


static func _read_bits(data: PackedByteArray, bit: int, n: int) -> int:
	var v := 0
	for i in n:
		var p := bit + i
		var b := p >> 3
		if b >= data.size():
			break
		if data[b] & (1 << (p & 7)):
			v |= 1 << i
	return v


static func apply_remote_media(row: Dictionary) -> String:
	var why := ""
	for spec in [
		["portrait_b64", "portrait_mime", "portrait", "portrait"],
		["name_media_b64", "name_media_mime", "name_media", "name"],
		["bio_media_b64", "bio_media_mime", "bio_media", "bio"],
	]:
		why = _materialize_one(row, str(spec[0]), str(spec[1]), str(spec[2]), str(spec[3]))
		if why != "":
			return why
	return ""


static func _materialize_one(row: Dictionary, b64_key: String, mime_key: String, path_key: String, leaf: String) -> String:
	var b64 := str(row.get(b64_key, ""))
	if b64 == "":
		return ""
	var mime := str(row.get(mime_key, "image/png"))
	var mid := str(row.get("id", "x"))
	var dir := "%s/%s" % [MEDIA_DIR, mid]
	DirAccess.make_dir_recursive_absolute(dir)
	if mime.find("evertbs-anim") >= 0:
		var raw := Marshalls.base64_to_raw(b64)
		var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			return "动图无法完整还原"
		var frames_in: Array = (parsed as Dictionary).get("frames", [])
		var delays: Array = (parsed as Dictionary).get("delays", [])
		var paths: Array = []
		for i in frames_in.size():
			var bytes := Marshalls.base64_to_raw(str(frames_in[i]))
			var img := Image.new()
			if img.load_png_from_buffer(bytes) != OK:
				return "动图无法完整还原"
			#（动画导入长边收到 340）26.10.22 01:52 s
			var longest := maxi(img.get_width(), img.get_height())
			if longest > 340:
				var sc := 340.0 / float(longest)
				img.resize(maxi(1, int(img.get_width() * sc)), maxi(1, int(img.get_height() * sc)), Image.INTERPOLATE_LANCZOS)
			#（动画导入长边收到 340）26.10.22 01:52 e
			var fp := "%s/%s_%d.png" % [dir, leaf, i]
			img.save_png(fp)
			paths.append(fp)
		var meta_path := "%s/%s.json" % [dir, leaf]
		var mf := FileAccess.open(meta_path, FileAccess.WRITE)
		if mf:
			mf.store_string(JSON.stringify({"frames": paths, "delays": delays}))
		row[path_key] = meta_path
		row[mime_key] = mime
		row.erase(b64_key)
		return ""
	var scaled: Dictionary = scale_image_bytes(Marshalls.base64_to_raw(b64), mime)
	if str(scaled.get("error", "")) != "":
		return str(scaled.get("error", ""))
	if str(scaled.get("anim_path", "")) != "":
		row[path_key] = str(scaled.get("anim_path", ""))
		row[mime_key] = str(scaled.get("mime", mime))
		row.erase(b64_key)
		return ""
	var path := "%s/%s.png" % [dir, leaf]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(scaled.get("bytes", PackedByteArray()))
	row[path_key] = path
	row[mime_key] = "image/png"
	row.erase(b64_key)
	return ""


static func _attach_file(row: Dictionary, path_key: String, b64_key: String, mime_key: String) -> void:
	var path := str(row.get(path_key, ""))
	if path == "" or not FileAccess.file_exists(path):
		return
	if path.ends_with(".json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_DICTIONARY:
			return
		var frames_b64: Array = []
		for fp_v in (parsed as Dictionary).get("frames", []):
			if not FileAccess.file_exists(str(fp_v)):
				return
			frames_b64.append(Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(str(fp_v))))
		var payload := JSON.stringify({"frames": frames_b64, "delays": (parsed as Dictionary).get("delays", [])})
		row[b64_key] = Marshalls.raw_to_base64(payload.to_utf8_buffer())
		row[mime_key] = "application/x-evertbs-anim"
		return
	row[b64_key] = Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(path))
	if str(row.get(mime_key, "")) == "":
		row[mime_key] = "image/png"


static func _used_ids() -> Dictionary:
	var used := {}
	for row in MemberTableScr.load_merged():
		used[str(row.get("id", ""))] = true
	return used


static func _read_seq() -> Dictionary:
	if not FileAccess.file_exists(SEQ_PATH):
		return {"local": 1, "imports": 0}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SEQ_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {"local": 1, "imports": 0}


static func _write_seq(seq: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(SEQ_PATH.get_base_dir())
	var f := FileAccess.open(SEQ_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(seq))


static func _csv_escape(value: String) -> String:
	if value.find(",") >= 0 or value.find("\"") >= 0 or value.find("\n") >= 0:
		return "\"%s\"" % value.replace("\"", "\"\"")
	return value
