# ONLINE_UPDATE — Eternal shell protocol

Aligns with TopDog [`VERSION.md`](../../top_dog_unity/docs/VERSION.md) / [`ONLINE_UPDATE.md`](../../top_dog_unity/docs/ONLINE_UPDATE.md) and pointer [`PROTOCOL.md`](../../../EVERTBS-online-update/PROTOCOL.md).

## Boot（壳 `202608.8.26+`）

1. **冷启动默认**跑核实流：`BundledContentSeed`（受不降级约束）→ 指针仓 discovery → HF `version.json` → 增量下载 → `mount_packs` → `write_applied_version` → `change_scene(entry)`
2. 「**直接进入游戏**」= 离线/打断兜底：不 GET 远端；seed（若不降级）→ 挂载本地 → 进游戏
3. **Seed 永不降级**：`applied_version` 存在且 `local_ver > seed_ver` 且 packs 齐全 → **禁止**因 sha_mismatch 重灌内置包（修复「杀进程后内容跌回 seed 版」）
4. 进主菜单前：`DataStore.content_version` = `applied_version`（缺省才 `local`）
5. 诊断：`print` / 会话侧可见 `boot.seed reason=`、`boot.apply content=`

## 主动验版（冷启默认 · 选项可再触发）

入口：冷启动自动；或主菜单 **选项 →「核实版本是否最新」**（`GameSession.request_verify_content_version()` → 回到 `boot.tscn`）。

1. GET 候选 `version.json`；GitHub 指针仅 discovery（只取 `baseUrl`），再拉 HF 权威 `version.json`
2. Check `protocol` + `shellCompatibilityId` (`eveac-shell-v1`)
3. Apply `baseUrl` if present（`lockBaseUrl` 除外）
4. Compare remote vs `user://online_update/applied_version.json`：`(年,月,日,N)`
5. **remote > local**（或首次 / 本地 pack 缺失需修复）→  
   - **仅版号前进且 pack sha 均已齐**（待下载 0 文件）→ **无需弹窗**，盖写 `applied_version` 后挂载进入  
   - 否则 **弹窗等待用户确认**：  
     - **更新**：再拉 manifest、增量下载、写 applied、挂载  
     - **暂不更新** / **直接进入游戏**：有本地则挂载进入；无本地则停在 Boot  
6. **remote == local** 且 pack 齐全 → 不下载，直接挂载进入  
7. **remote < local** → 不下载、不降级，挂载本地  
8. Mount packs → 读 `applied_version` 写入 `DataStore.content_version` → `change_scene(entry)`

**规范：有包要下时不自动下载，须点「更新」。纯版号对齐（0 文件）可自动盖戳。**

**UI 版本**：玩家可见处只显示 **内容热更版**（`DataStore.content_version`）。壳号不进 UI。联机 `rules_hash` = 同内容版字符串（`MatchRng.compute_rules_hash`）。
验版/下载中途可随时「直接进入游戏」取消 HTTP。

Network failure: 重试；有本地包可「直接进入游戏」（仍不降级 seed）。

## Version format

`YYYYMM.D.N` — no letters. Example: `202607.26.1`.

## Manifest file entry

```json
{
  "path": "packs/game.pck",
  "sha256": "...",
  "size": 0,
  "kind": "pack",
  "mountOrder": 10
}
```

倒 Y: shared `packs/**`; `platform/windows/**` Win only; `platform/android/**` Android only.

## Publish

```powershell
cd H:\game_dev\godot_eternal_shell
.\tools\publish_online_update.ps1              # stage only
.\tools\publish_online_update.ps1 -Push        # after user confirms
.\tools\publish_online_update.ps1 -PushGitHub  # pointer repo
.\tools\serve_local_update.ps1                 # local CDN for debug
```

## Local override

`user://bootstrap_override.json`:

```json
{ "baseUrl": "http://127.0.0.1:8765/", "lockBaseUrl": true }
```

`lockBaseUrl: true` 防止远端 `version.json.baseUrl`（HF）覆盖本地联调基址。
