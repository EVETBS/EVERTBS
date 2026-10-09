# EVETBS · 永恒壳（Godot Eternal Shell）

薄壳（Windows + Android）+ 热更内容挂载。从 EVE自走棋 `godot_eternal_shell` 复制并换皮为 **烬海征服者**。

- 壳：[`shell/`](shell/) — Boot、版本门、下载、`load_resource_pack`
- 内容烟测：[`content_src/`](content_src/) — 占位 demo（`res://game/main.tscn`）
- 玩法工程：仓内 [`../godot_project/`](../godot_project/)（小队战内容落点）
- 文档：[`docs/SHELL_LOCK.md`](docs/SHELL_LOCK.md) · [`docs/ONLINE_UPDATE.md`](docs/ONLINE_UPDATE.md)

设计权威：[EVETBS-design](https://github.com/EVETBS/EVETBS-design)

## 打开

```powershell
$Godot = "H:\game\game_dev\EVETBS\tools\godot\Godot_v4.7.1-stable_win64.exe"
# 内容工程
& $Godot --path "H:\game\game_dev\EVETBS\godot_project"
# 壳 Boot
& $Godot --path "H:\game\game_dev\EVETBS\godot_eternal_shell\shell"
```

## 身份

| 项 | 值 |
|----|-----|
| 中文名 | 烬海征服者 |
| 英文 / 仓名 | EVETBS |
| Android package | `com.evetbs.game` |
| `shellCompatibilityId` | `evetbs-shell-v1` |
| Godot | 4.7.1 stable |

热更 HF / 指针仓尚未建好；默认 URL 为占位，本地用「直接进入游戏」即可。
