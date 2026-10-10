# EVETBS · 烬海征服者（开发仓）

**烬海征服者**（EVETBS）是一款**不以盈利为目的**的玩家二创实时策略军棋游戏。故事背景取自 EVE 手游「烬海」；玩家扮演**军团意志**，在烬海地图上指挥**小队战**。

本仓只承载 **Godot 游戏本体代码**（脚本、场景、内容 JSON、永恒壳）。玩法 / 数值 / 仓门禁权威在设计仓：  
[EVETBS-design](https://github.com/EVETBS/EVETBS-design)

远程：https://github.com/EVETBS/EVETBS

## 打开

```powershell
$Godot = "H:\game\game_dev\EVETBS\tools\godot\Godot_v4.7.1-stable_win64.exe"
& $Godot --path "H:\game\game_dev\EVETBS\godot_project"
& $Godot --path "H:\game\game_dev\EVETBS\godot_eternal_shell\shell"
```

## 结构

| 路径 | 职责 |
|------|------|
| `godot_project/` | 玩法工程（星图试验 / 小队战） |
| `godot_eternal_shell/` | 永恒壳（Boot / 热更 / 双端导出） |
| `tools/godot/` | Godot 4.7.1（本机，不进 Git） |

美术资源与本地获取脚本不进本仓；范围见设计仓 [`docs/REPO_GATES.md`](https://github.com/EVETBS/EVETBS-design/blob/main/docs/REPO_GATES.md)。

## 双仓门禁

权威：设计仓 [`docs/REPO_GATES.md`](https://github.com/EVETBS/EVETBS-design/blob/main/docs/REPO_GATES.md)。

- 改玩法 / UI / 协议 → **先**更新 `EVETBS-design/docs/`，再改本仓
- 禁止擅自推 HF / GitHub Releases（须用户明确批准）

## License

原创源代码拟采用 BSD 3-Clause（待补 `LICENSE`）。  
相关美术与设定权利归属各自权利人；本项目为非商业玩家二创。
