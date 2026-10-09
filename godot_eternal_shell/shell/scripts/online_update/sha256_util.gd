class_name Sha256Util
extends RefCounted


static func file_sha256(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	const CHUNK := 1024 * 256
	while not f.eof_reached():
		var buf := f.get_buffer(CHUNK)
		if buf.size() == 0:
			break
		ctx.update(buf)
	f.close()
	var dig := ctx.finish()
	return dig.hex_encode()


static func bytes_sha256(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()
