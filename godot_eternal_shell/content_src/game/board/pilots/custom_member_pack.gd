extends RefCounted
class_name CustomMemberPack
## Drafts, confirmed SR rows, and one-csv zip packs.

const MemberTableScr := preload("res://game/board/pilots/member_table.gd")
const SEQ_PATH := "user://content_runtime/data/board/custom_seq.json"
const MEDIA_DIR := "user://content_runtime/data/board/custom_members"

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
	var mid := "00%04d" % n
	var used := _used_ids()
	while used.has(mid):
		n += 1
		mid = "00%04d" % n
	seq["local"] = n + 1
	_write_seq(seq)
	return mid


static func confirm_row(row: Dictionary) -> void:
	if str(row.get("portrait_b64", "")) != "":
		_materialize_media(row)
		row.erase("portrait_b64")
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


static func export_zip(row: Dictionary, zip_path: String) -> bool:
	var header := PackedStringArray([
		"id", "name", "portrait", "bio", "rank", "bonus", "ships", "default_ship", "pref_eq",
		"portrait_b64", "portrait_mime", "name_media_b64", "bio_media_b64",
	])
	var cells := PackedStringArray()
	for key in header:
		cells.append(_csv_escape(str(row.get(key, ""))))
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
		n = 99
	seq["imports"] = n
	_write_seq(seq)
	var prefix := "%02d" % n
	var tail := str(row.get("id", "0000"))
	if tail.length() >= 4:
		tail = tail.substr(tail.length() - 4)
	else:
		tail = tail.pad_zeros(4)
	var mid := prefix + tail
	var used := _used_ids()
	var bump := 0
	while used.has(mid):
		bump += 1
		mid = prefix + ("%04d" % ((int(tail) + bump) % 10000))
	row["id"] = mid
	row["rank"] = "SR"
	confirm_row(row)
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
		return {"bytes": bytes, "mime": mime}
	var longest := maxi(img.get_width(), img.get_height())
	if longest > 340:
		var scale := 340.0 / float(longest)
		img.resize(maxi(1, int(img.get_width() * scale)), maxi(1, int(img.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	return {"bytes": img.save_png_to_buffer(), "mime": "image/png"}


static func _gif_bytes(bytes: PackedByteArray) -> Dictionary:
	var frames := _decode_gif(bytes)
	if frames.is_empty():
		return {"bytes": bytes, "mime": "image/gif"}
	var first: Image = frames[0]
	var longest := maxi(first.get_width(), first.get_height())
	if longest > 340:
		var scale := 340.0 / float(longest)
		for i in frames.size():
			var fr: Image = frames[i]
			fr.resize(maxi(1, int(fr.get_width() * scale)), maxi(1, int(fr.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	if frames.size() == 1:
		return {"bytes": (frames[0] as Image).save_png_to_buffer(), "mime": "image/png"}
	var anim := AnimatedTexture.new()
	anim.frames = mini(frames.size(), 256)
	anim.speed_scale = 1.0
	for i in anim.frames:
		var tex := ImageTexture.create_from_image(frames[i])
		anim.set_frame_texture(i, tex)
		anim.set_frame_duration(i, 0.1)
	var path := "%s/gif_%d.tres" % [MEDIA_DIR, Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(MEDIA_DIR)
	ResourceSaver.save(anim, path)
	return {"bytes": bytes, "mime": "image/gif", "anim_path": path, "texture": anim}


static func _decode_gif(bytes: PackedByteArray) -> Array:
	## Non-interlaced GIF89a frames. Empty when the file is not that subset.
	if bytes.size() < 13 or bytes.slice(0, 6).get_string_from_ascii() != "GIF89a" and bytes.slice(0, 6).get_string_from_ascii() != "GIF87a":
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
					if flags & 0x01:
						transparent = bytes[pos + 4]
				pos = _skip_subblocks(bytes, pos)
			else:
				pos = _skip_subblocks(bytes, pos)
			continue
		if b != 0x2C or pos + 9 > bytes.size():
			break
		var w := bytes[pos + 4] | (bytes[pos + 5] << 8)
		var h := bytes[pos + 6] | (bytes[pos + 7] << 8)
		var ip := bytes[pos + 8]
		pos += 9
		if ip & 0x40:
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
		if frames.size() >= 32:
			break
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


static func _materialize_media(row: Dictionary) -> void:
	var mid := str(row.get("id", "x"))
	var b64 := str(row.get("portrait_b64", ""))
	if b64 == "":
		return
	var bytes := Marshalls.base64_to_raw(b64)
	var scaled: Dictionary = scale_image_bytes(bytes, str(row.get("portrait_mime", "image/png")))
	DirAccess.make_dir_recursive_absolute("%s/%s" % [MEDIA_DIR, mid])
	var path := "%s/%s/portrait.png" % [MEDIA_DIR, mid]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(scaled.get("bytes", bytes))
	row["portrait"] = path


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
