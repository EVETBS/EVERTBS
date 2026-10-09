# -*- coding: utf-8 -*-
from pathlib import Path
import re

p = Path(r"H:\game_dev\godot_eternal_shell\shell\project.godot")
t = p.read_text(encoding="utf-8")
t = t.replace('config/name="EVE???"', 'config/name="EVE自走棋"')
t = re.sub(r'config/version="[^"]+"', 'config/version="202608.8.27"', t, count=1)
if "use_custom_user_dir" not in t:
    t = t.replace(
        'config/version="202608.8.27"',
        'config/version="202608.8.27"\n'
        "config/use_custom_user_dir=true\n"
        'config/custom_user_dir_name="userdata"',
    )
p.write_text(t, encoding="utf-8", newline="\n")
for line in p.read_text(encoding="utf-8").splitlines():
    if "config/name" in line or "custom_user" in line or "config/version" in line:
        print(repr(line))

# Self-contained markers (Godot: ._sc_ next to exe → user data beside install)
for sc in (
    Path(r"H:\game_dev\godot_eternal_shell\installer\._sc_"),
    Path(r"H:\game_dev\godot_eternal_shell\shell\._sc_"),
):
    sc.write_text("", encoding="utf-8")
    print("wrote", sc)
