from PIL import Image
from pathlib import Path

base_dir = Path(r"H:\game_dev\eveautochess-original\unity-source\DUST_243-main\Assets\Sprites\ChampionIcons")
jpgs = list(base_dir.glob("*.jpg")) + list(base_dir.glob("*.png"))
candidates = sorted(jpgs, key=lambda p: abs(p.stat().st_size - 260519))
base_file = candidates[0]
print("base", base_file, base_file.stat().st_size)

badge_path = Path(
    r"C:\Users\WXH\.cursor\projects\h\assets\c__Users_WXH_AppData_Roaming_Cursor_User_workspaceStorage_a6e066ac4a2afb80200e61f3e501804f_images_app-icon-source-5a982607-a2ce-426d-92d5-c25bbb5b96fb.png"
)
out_png = Path(r"H:\game_dev\godot_eternal_shell\shell\icon.png")

base = Image.open(base_file).convert("RGBA")
w, h = base.size
side = max(w, h)
square = Image.new("RGBA", (side, side), (20, 24, 36, 255))
square.paste(base, ((side - w) // 2, (side - h) // 2), base)
base = square.resize((512, 512), Image.Resampling.LANCZOS)

badge = Image.open(badge_path).convert("RGBA")
pixels = badge.load()
bw, bh = badge.size
for y in range(bh):
    for x in range(bw):
        r, g, b, a = pixels[x, y]
        if r < 28 and g < 28 and b < 28:
            pixels[x, y] = (r, g, b, 0)

bbox = badge.getbbox()
if bbox:
    badge = badge.crop(bbox)

badge_side = int(512 * 0.38)
badge = badge.resize((badge_side, badge_side), Image.Resampling.LANCZOS)
margin = 10
pos = (512 - badge_side - margin, 512 - badge_side - margin)
base.paste(badge, pos, badge)
base.save(out_png, "PNG")
print("wrote", out_png, out_png.stat().st_size)
