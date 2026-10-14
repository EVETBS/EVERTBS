# EVERTBS · 永恒壳（Godot Eternal Shell）

薄壳（Windows + Android）+ 热更内容挂载。从上游 [EVE自走棋](https://github.com/EveAutochess-develop/EveAutoChess) `godot_eternal_shell` 复制并换皮为 **eve战棋（EVERTBS）**。

- 壳：[`shell/`](shell/) — Boot、版本门、下载、`load_resource_pack`
- 内容烟测：[`content_src/`](content_src/) — 占位 demo（`res://game/main.tscn`）
- 玩法工程：仓内 [`../godot_project/`](../godot_project/)（小队战内容落点）
- 文档：[`docs/SHELL_LOCK.md`](docs/SHELL_LOCK.md) · [`docs/ONLINE_UPDATE.md`](docs/ONLINE_UPDATE.md)

设计权威：[EVERTBS-design](https://github.com/EVETBS/EVERTBS-design)

## 打开

```powershell
$Godot = "H:\game\game_dev\EVERTBS\tools\godot\Godot_v4.7.1-stable_win64.exe"
# 内容工程
& $Godot --path "H:\game\game_dev\EVERTBS\godot_project"
# 壳 Boot
& $Godot --path "H:\game\game_dev\EVERTBS\godot_eternal_shell\shell"
```

## 身份

| 项 | 值 |
|----|-----|
| 中文名 | eve战棋 |
| 英文 / 仓名 | EVERTBS |
| Android package | `com.evertbs.game` |
| `shellCompatibilityId` | `evertbs-shell-v1` |
| Godot | 4.7.1 stable |

> 兼容说明：旧壳 `evetbs-shell-v1` / `com.evetbs.game` 与新标识不互通，须换壳。

热更 HF / 指针仓尚未建好；默认 URL 为占位，本地用「直接进入游戏」即可。

## 双端打包（倒 Y）

```powershell
& "H:\game\game_dev\EVERTBS\godot_eternal_shell\tools\publish_dual.ps1"
# → builds\release\EVERTBS_Setup.exe + EVERTBS.apk（共用 packs/game.pck，从 ../godot_project 导出）
# -ThinShell：只打壳不带内容；-ContentPck <path>：用指定内容包
```

- 内容包单独导：`tools\pack_content.ps1`（暂存到 `builds\content_stage`，去 MCP 插件与 `tools/`）
- 安装器 `installer\EVERTBS.iss`：显示名 EVE战棋，无向导图；Windows `user://` = `%APPDATA%\EVERTBS`
- 不写 `H:\disv1`；规则见设计仓 `UI_AND_SHELL.md` §8
