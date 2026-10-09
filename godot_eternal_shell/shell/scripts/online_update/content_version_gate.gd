class_name ContentVersionGate
extends RefCounted

## Aligns with TopDog ContentVersionGate / docs/VERSION.md — YYYYMM.D.N


static func try_parse(version: String) -> Dictionary:
	## Returns { ok, year, month, day, n } or { ok: false }
	var v := version.strip_edges()
	var re := RegEx.new()
	re.compile("^(\\d{6})\\.(\\d{1,2})\\.(\\d{1,3})$")
	var m := re.search(v)
	if m == null:
		return {"ok": false}
	var ym := m.get_string(1)
	var year := int(ym.substr(0, 4))
	var month := int(ym.substr(4, 2))
	var day := int(m.get_string(2))
	var n := int(m.get_string(3))
	if month < 1 or month > 12:
		return {"ok": false}
	if day < 1 or day > 31:
		return {"ok": false}
	if n < 1 or n > 999:
		return {"ok": false}
	return {"ok": true, "year": year, "month": month, "day": day, "n": n}


static func compare(a: String, b: String) -> int:
	## <0 if a<b, 0 if equal string-wise when both parse equal, >0 if a>b
	var pa := try_parse(a)
	var pb := try_parse(b)
	if pa.get("ok", false) and pb.get("ok", false):
		for key in ["year", "month", "day", "n"]:
			var da: int = int(pa[key])
			var db: int = int(pb[key])
			if da != db:
				return -1 if da < db else 1
		return 0
	var sa := a.strip_edges()
	var sb := b.strip_edges()
	if sa == sb:
		return 0
	return -1 if sa < sb else 1


static func matches(a: String, b: String) -> bool:
	return a.strip_edges() == b.strip_edges()
