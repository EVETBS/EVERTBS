param(
  [string]$Godot = "H:\game\game_dev\EVERTBS\tools\godot\Godot_v4.7.1-stable_win64.exe"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Shell = Join-Path $Root "shell"
$OutDir = Join-Path $Root "builds\android"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

if (-not (Test-Path $Godot)) { throw "Godot not found: $Godot" }

Write-Host "Import shell..."
& $Godot --headless --path $Shell --import 2>&1 | Out-Host

$apk = Join-Path $OutDir "EveAutochess.apk"
Write-Host "Export Android -> $apk"
Write-Host "Requires Android export templates + JDK/SDK configured in Godot Editor."
& $Godot --headless --path $Shell --export-debug "Android" $apk 2>&1 | Out-Host

if (-not (Test-Path $apk)) {
  Write-Warning "APK not created. Open shell/ in Godot, install Android templates, configure export, then re-run."
  exit 1
}
Write-Host "OK $apk"
