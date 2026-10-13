# OBSOLETE — do not use for release. Monolithic game.pck / ContentPack path is retired.
# Use: H:\game_dev\eveautochess-dev\tools\pack_hf_content.ps1 (five packs: data/logic/ui/models/audio)
param(
  [string]$Godot = "H:\game\game_dev\EVERTBS\tools\godot\Godot_v4.7.1-stable_win64.exe",
  [string]$OutPck = ""
)

$ErrorActionPreference = "Stop"
Write-Warning "export_content_pack.ps1 is OBSOLETE (game.pck). Prefer pack_hf_content.ps1."
$Root = Split-Path -Parent $PSScriptRoot
$Content = Join-Path $Root "content_src"
if (-not $OutPck) {
  $OutPck = Join-Path $Root "content_dist\packs\game.pck"
}

if (-not (Test-Path $Godot)) {
  throw "Godot not found: $Godot"
}

$outDir = Split-Path -Parent $OutPck
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

Write-Host "Importing content project..."
& $Godot --headless --path $Content --import 2>&1 | Out-Host

Write-Host "Exporting pack -> $OutPck"
& $Godot --headless --path $Content --export-pack "ContentPack" $OutPck 2>&1 | Out-Host

if (-not (Test-Path $OutPck)) {
  throw "Pack not created: $OutPck"
}
$fi = Get-Item $OutPck
Write-Host ("OK {0} ({1:N0} bytes)" -f $fi.FullName, $fi.Length)
