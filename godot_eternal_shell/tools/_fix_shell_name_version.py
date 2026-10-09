# -*- coding: utf-8 -*-
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJ = ROOT / "shell" / "project.godot"
PRESETS = ROOT / "shell" / "export_presets.cfg"
VERSION = "202608.8.24"
CODE = 89
NAME = "EVE自走棋"


def main() -> None:
	text = PROJ.read_text(encoding="utf-8-sig")
	text2, n = re.subn(r"^config/name=.*$", f'config/name="{NAME}"', text, count=1, flags=re.M)
	if n != 1:
		raise SystemExit(f"config/name replace failed n={n}")
	text2, n = re.subn(r'^config/version=".*"$', f'config/version="{VERSION}"', text2, count=1, flags=re.M)
	if n != 1:
		raise SystemExit(f"config/version replace failed n={n}")
	PROJ.write_text(text2, encoding="utf-8", newline="\n")  # no BOM — Godot rejects BOM on presets
	print("project.godot:")
	for ln in text2.splitlines():
		if ln.startswith("config/name") or ln.startswith("config/version"):
			print(" ", ln)

	pt = PRESETS.read_text(encoding="utf-8-sig")
	pt2, n = re.subn(r'package/name=".*"', f'package/name="{NAME}"', pt, count=1)
	if n != 1:
		raise SystemExit(f"package/name replace failed n={n}")
	pt2, n = re.subn(r'version/name=".*"', f'version/name="{VERSION}"', pt2, count=1)
	if n != 1:
		raise SystemExit(f"version/name replace failed n={n}")
	pt2, n = re.subn(r"version/code=\d+", f"version/code={CODE}", pt2, count=1)
	if n != 1:
		raise SystemExit(f"version/code replace failed n={n}")
	PRESETS.write_text(pt2, encoding="utf-8", newline="\n")
	print("export_presets.cfg:")
	for ln in pt2.splitlines():
		if "package/name" in ln or "version/name" in ln or "version/code" in ln:
			print(" ", ln)
		if ln.startswith("name=") or ln.startswith("platform="):
			print(" ", ln)


if __name__ == "__main__":
	main()
