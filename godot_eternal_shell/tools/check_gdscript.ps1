# Thin wrapper: same gate for eternal shell project (incremental; -Full available).
param(
  [string]$Godot = "H:\game\game_dev\EVETBS\tools\godot\Godot_v4.7.1-stable_win64.exe",
  [switch]$SkipSmoke,
  [switch]$Full
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $PSScriptRoot
$check = "H:\game_dev\eveautochess-dev\tools\check_gdscript.ps1"
$shellProj = Join-Path $here "shell"
$splat = @{
  Godot     = $Godot
  Project   = $shellProj
  SkipSmoke = $true
}
if ($Full) { $splat.Full = $true }
if ($SkipSmoke) { $splat.SkipSmoke = $true }
& $check @splat
exit $LASTEXITCODE
