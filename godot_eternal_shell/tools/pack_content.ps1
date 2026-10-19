# Export the shared content pack (inverted-Y stem): godot_project -> content_dist/packs/game.pck
# Both Windows Setup and Android APK carry this same pack (EVERTBS-design UI_AND_SHELL section 8).
param(
  [string]$Godot = "H:\game\game_dev\EVERTBS\tools\godot\Godot_v4.7.1-stable_win64.exe",
  [string]$Source = "",
  [string]$OutPck = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Source) { $Source = Join-Path (Split-Path -Parent $Root) "godot_project" }
if (-not $OutPck) { $OutPck = Join-Path $Root "content_dist\packs\game.pck" }
$Stage = Join-Path $Root "builds\content_stage"
$LogDir = Join-Path $Root "builds\logs"

if (-not (Test-Path $Godot)) { throw "Godot not found: $Godot" }
if (-not (Test-Path (Join-Path $Source "project.godot"))) { throw "Content source missing project.godot: $Source" }
New-Item -ItemType Directory -Path $Stage, $LogDir, (Split-Path -Parent $OutPck) -Force | Out-Null

## Stage lives under builds/ (gitignored): local art (assets/, art_modules/) never enters Git.
## Stage .godot is excluded from /MIR so re-imports stay incremental.
Write-Host "Stage content: $Source -> $Stage"
robocopy $Source $Stage /MIR /XD ".godot" (Join-Path $Source "addons\godot_mcp") (Join-Path $Source "tools") /XF "project.godot" "export_presets.cfg" /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed exit=$LASTEXITCODE" }

## Editor-only MCP autoload/plugin must not ship; both GPU texture families for the shared pack.
$proj = Get-Content (Join-Path $Source "project.godot") -Raw -Encoding UTF8
$proj = ($proj -split "`r?`n" | Where-Object { $_ -notmatch 'godot_mcp' }) -join "`n"
if ($proj -match '(?m)^\[rendering\]') {
  $proj = [regex]::Replace($proj, '(?m)^\[rendering\]', "[rendering]`n`ntextures/vram_compression/import_s3tc_bptc=true`ntextures/vram_compression/import_etc2_astc=true")
} else {
  $proj += "`n[rendering]`n`ntextures/vram_compression/import_s3tc_bptc=true`ntextures/vram_compression/import_etc2_astc=true`n"
}
[IO.File]::WriteAllText((Join-Path $Stage "project.godot"), $proj, (New-Object Text.UTF8Encoding $false))

$presets = @'
[preset.0]

name="ContentPack"
platform="Windows Desktop"
runnable=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="*.json,*.on,*.csv"
exclude_filter=""
export_path=""
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=false
texture_format/s3tc_bptc=true
texture_format/etc2_astc=true
ssh_remote_deploy/enabled=false
'@
[IO.File]::WriteAllText((Join-Path $Stage "export_presets.cfg"), $presets, (New-Object Text.UTF8Encoding $false))

function Invoke-Godot([string]$Label, [string]$ArgLine) {
  $log = Join-Path $LogDir "content_$Label.log"
  Write-Host "Godot $Label ..."
  $p = Start-Process -FilePath $Godot -ArgumentList $ArgLine -WorkingDirectory $Stage -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput $log -RedirectStandardError "$log.err"
  if ($p.ExitCode -ne 0) { throw "Godot $Label failed exit=$($p.ExitCode) (see $log)" }
}

Invoke-Godot "import" "--headless --path `"$Stage`" --import"
if (Test-Path $OutPck) { Remove-Item $OutPck -Force }
Invoke-Godot "export" "--headless --path `"$Stage`" --export-pack `"ContentPack`" `"$OutPck`""

if (-not (Test-Path $OutPck)) { throw "Pack not created: $OutPck" }
$fi = Get-Item $OutPck
Write-Host ("OK {0} ({1:N0} bytes)" -f $fi.FullName, $fi.Length)
exit 0
