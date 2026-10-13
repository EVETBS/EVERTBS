param(
  [string]$Godot = "H:\game\game_dev\EVERTBS\tools\godot\Godot_v4.7.1-stable_win64.exe"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Shell = Join-Path $Root "shell"
$OutDir = Join-Path $Root "builds\windows"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

if (-not (Test-Path $Godot)) { throw "Godot not found: $Godot" }

Write-Host "Import shell..."
& $Godot --headless --path $Shell --import 2>&1 | Out-Host

$exe = Join-Path $OutDir "EveAutochess.exe"
Write-Host "Export Windows -> $exe"
& $Godot --headless --path $Shell --export-release "Windows Desktop" $exe 2>&1 | Out-Host

if (-not (Test-Path $exe)) { throw "Export failed: $exe" }
Write-Host "OK $exe"
