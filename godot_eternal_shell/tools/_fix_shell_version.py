# -*- coding: utf-8 -*-
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent / "shell"

p = ROOT / "project.godot"
text = p.read_text(encoding="utf-8", errors="replace")
text = re.sub(r'config/name="[^"]*"', 'config/name="EVE自走棋"', text, count=1)
text = re.sub(r'config/description="[^"]*"', 'config/description="EVE自走棋"', text, count=1)
text = re.sub(r'config/version="[^"]*"', 'config/version="202608.2.4"', text, count=1)
p.write_text(text, encoding="utf-8", newline="\n")
print("project.godot ok")

ep = ROOT / "export_presets.cfg"
et = ep.read_text(encoding="utf-8", errors="replace")
et = re.sub(r"version/code=\d+", "version/code=32", et, count=1)
et = re.sub(r'version/name="[^"]*"', 'version/name="202608.2.4"', et, count=1)
et = re.sub(r'package/name="[^"]*"', 'package/name="EVE自走棋"', et, count=1)
et = re.sub(
    r'command_line/extra_args="[^"]*"',
    'command_line/extra_args="--rendering-driver opengl3 --rendering-method gl_compatibility"',
    et,
    count=1,
)
ep.write_text(et, encoding="utf-8", newline="\n")
print("export_presets.cfg ok")
for i, line in enumerate(et.splitlines(), 1):
    if 50 <= i <= 70 or "version/" in line or "package/name" in line:
        if i <= 70 or "version/" in line or "package/name" in line:
            if 50 <= i <= 70:
                print(f"{i}:{line}")
