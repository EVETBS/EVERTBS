# SHELL_LOCK — EVETBS 永恒壳冻结边界

## Engine

| Item | Value |
|------|--------|
| Godot | **4.7.1** stable |
| Binary | `H:\game\game_dev\EVETBS\tools\godot\Godot_v4.7.1-stable_win64.exe`（junction → eveautochess-dev tools） |
| Shell project | `godot_eternal_shell/shell` |
| Content project | `godot_project/`（玩法）· `godot_eternal_shell/content_src`（壳烟测） |
| App name | `烬海征服者` |
| Android package | `com.evetbs.game` |
| `shellCompatibilityId` | `evetbs-shell-v1` |
| Protocol | `1` |

## What the shell may do (frozen)

- HTTPS GET `version.json` / `manifest.json` / files（用户点「核实版本是否最新」后）
- SHA256 verify、增量下载到 `user://content_runtime/`
- `ProjectSettings.load_resource_pack`
- 跳到 `version.entry`（默认 `res://game/main.tscn`）

## What never goes in the shell

烬海地图小队战玩法场景、美术、数值表 — 留在热更 PCK / `godot_project`。

**Must stay in shell**: Boot / UpdateClient，以及 Autoload（`AdminBus` / `DataStore` / `GameSession`）。

## When to rebuild the shell

- Boot / 热更协议变更
- Godot / 导出模板升级
- Android 包名 / 权限 / 签名变更
- `SHELL_COMPATIBILITY_ID` bump
