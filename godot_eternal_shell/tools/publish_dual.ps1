# EVERTBS dual-end publish (inverted Y, modeled on EVE autochess publish_disv1.ps1):
#   one shared packs/game.pck  ->  Windows EVERTBS_Setup.exe (Inno seed) + Android EVERTBS.apk (bundled_content)
# Output: builds/release/ with exactly two files. Never writes H:\disv1 (EVE autochess release dir).
param(
  [string]$Godot = "H:\game\game_dev\EVERTBS\tools\godot\Godot_v4.7.1-stable_win64.exe",
  [string]$OutDir = "",
  [string]$Iscc = "",
  # Default: full content in Setup + APK. -ThinShell ships the boot shell only.
  [switch]$ThinShell,
  # Pinned pack instead of re-exporting from godot_project.
  [string]$ContentPck = "",
  [string]$ContentVersion = "",
  [string]$ContentEntry = "res://game/main_menu.tscn"
)

$ErrorActionPreference = "Stop"
$BundleContent = -not $ThinShell
$Root = Split-Path -Parent $PSScriptRoot
$Shell = Join-Path $Root "shell"
if (-not $OutDir) { $OutDir = Join-Path $Root "builds\release" }
$OutFull = [IO.Path]::GetFullPath($OutDir).TrimEnd('\')
if ($OutFull -like "H:\disv1*") { throw "Refusing to write $OutFull (H:\disv1 belongs to EVE autochess)" }

$WinOut = Join-Path $Root "builds\windows\EVERTBS.exe"
$ApkOut = Join-Path $Root "builds\android\EVERTBS.apk"
$SetupOut = Join-Path $Root "builds\windows\EVERTBS_Setup.exe"
$Iss = Join-Path $Root "installer\EVERTBS.iss"
$SeedDir = Join-Path $Root "builds\seed"
$BundledDir = Join-Path $Shell "bundled_content"
$PackRel = "packs/game.pck"

$env:JAVA_HOME = if (Test-Path "C:\Program Files\Java\jdk-20") { "C:\Program Files\Java\jdk-20" } else { $env:JAVA_HOME }
if ($env:JAVA_HOME) { $env:Path = "$env:JAVA_HOME\bin;" + $env:Path }
if (-not $env:ANDROID_HOME) { $env:ANDROID_HOME = "C:\Users\WXH\AppData\Local\Android\Sdk" }

if (-not (Test-Path $Godot)) { throw "Godot not found: $Godot" }
if (-not $Iscc) {
  $Iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Iscc -or -not (Test-Path $Iscc)) { throw "Inno Setup ISCC.exe not found" }

$shellVer = (Select-String -Path (Join-Path $Shell "project.godot") -Pattern '^config/version="([^"]+)"' | Select-Object -First 1).Matches[0].Groups[1].Value
if (-not $shellVer) { throw "config/version missing in shell project.godot" }
if (-not $ContentVersion) { $ContentVersion = $shellVer }

function Invoke-GodotExport([string]$Label, [string]$PresetName, [string]$ExportFlag, [string]$OutFile) {
  $before = if (Test-Path $OutFile) { (Get-Item $OutFile).LastWriteTimeUtc } else { [datetime]::MinValue }
  Write-Host "Export $Label (preset '$PresetName')..."
  $log = Join-Path $Root "builds\logs\shell_$Label.log"
  New-Item -ItemType Directory -Path (Split-Path $log) -Force | Out-Null
  $argLine = "--headless --path `"$Shell`" $ExportFlag `"$PresetName`" `"$OutFile`""
  $p = Start-Process -FilePath $Godot -ArgumentList $argLine -WorkingDirectory $Shell -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput $log -RedirectStandardError "$log.err"
  if ($p.ExitCode -ne 0) { throw "Godot export failed ($Label) exit=$($p.ExitCode) (see $log)" }
  if (-not (Test-Path $OutFile)) { throw "$Label export missing output: $OutFile" }
  $after = (Get-Item $OutFile).LastWriteTimeUtc
  if ($after -le $before) { throw "$Label export did not refresh $OutFile" }
  Write-Host "  OK $OutFile ($((Get-Item $OutFile).Length) bytes)"
}

# Always clear the previous seed so thin builds stay thin.
Remove-Item (Join-Path $BundledDir "packs\*.pck") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $BundledDir "seed_meta.json") -Force -ErrorAction SilentlyContinue
Remove-Item $SeedDir -Recurse -Force -ErrorAction SilentlyContinue

$packSize = 0L
if ($BundleContent) {
  if (-not $ContentPck) {
    & (Join-Path $PSScriptRoot "pack_content.ps1") -Godot $Godot
    $ContentPck = Join-Path $Root "content_dist\packs\game.pck"
  }
  if (-not (Test-Path $ContentPck)) { throw "Content pack missing: $ContentPck" }
  $sha = (Get-FileHash -Path $ContentPck -Algorithm SHA256).Hash.ToLowerInvariant()
  $packSize = (Get-Item $ContentPck).Length
  Write-Host "Content pack: $PackRel size=$packSize sha=$sha version=$ContentVersion entry=$ContentEntry"

  New-Item -ItemType Directory -Path (Join-Path $SeedDir "packs"), (Join-Path $BundledDir "packs") -Force | Out-Null
  Copy-Item $ContentPck (Join-Path $SeedDir "packs\game.pck") -Force
  Copy-Item $ContentPck (Join-Path $BundledDir "packs\game.pck") -Force

  $applied = [ordered]@{
    version   = $ContentVersion
    entry     = $ContentEntry
    appliedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    platform  = "windows"
    source    = "inno_bundle"
    packs     = @($PackRel)
  }
  ($applied | ConvertTo-Json -Depth 5) | Set-Content (Join-Path $SeedDir "applied_version.json") -Encoding utf8
  $meta = [ordered]@{
    version = $ContentVersion
    entry   = $ContentEntry
    packs   = @([ordered]@{ path = $PackRel; sha256 = $sha; size = $packSize })
  }
  (ConvertTo-Json -InputObject $meta -Depth 6) | Set-Content (Join-Path $BundledDir "seed_meta.json") -Encoding utf8
  Write-Host "  staged Inno seed + Android bundled_content"
}

New-Item -ItemType Directory -Path (Split-Path $WinOut), (Split-Path $ApkOut) -Force | Out-Null
Invoke-GodotExport -Label "windows" -PresetName "Windows Desktop" -ExportFlag "--export-release" -OutFile $WinOut
# Android: debug export (no release keystore on this machine).
Invoke-GodotExport -Label "android" -PresetName "Android" -ExportFlag "--export-debug" -OutFile $ApkOut

# Sync installer version from shell project.godot (UTF-8 BOM keeps Chinese text intact for ISCC).
$issText = [IO.File]::ReadAllText($Iss, [Text.Encoding]::UTF8)
$issText = [regex]::Replace($issText, '#define MyAppVersion "[^"]+"', "#define MyAppVersion `"$shellVer`"")
if ($shellVer -match '^(\d{4})(\d{2})\.(\d+)\.(\d+)$') {
  $vi = "{0}.{1}.{2}.{3}" -f $Matches[1], [int]$Matches[2], $Matches[3], $Matches[4]
  $issText = [regex]::Replace($issText, 'VersionInfoVersion=[^\r\n]+', "VersionInfoVersion=$vi")
}
[IO.File]::WriteAllText($Iss, $issText, (New-Object Text.UTF8Encoding $true))
Write-Host "Inno AppVersion -> $shellVer"

Write-Host "Build Inno Setup installer..."
if (Test-Path $SetupOut) { Remove-Item $SetupOut -Force }
$isccLog = Join-Path $Root "builds\logs\iscc.log"
$pSetup = Start-Process -FilePath $Iscc -ArgumentList "`"$Iss`"" -WorkingDirectory (Split-Path $Iss) -Wait -PassThru -NoNewWindow `
  -RedirectStandardOutput $isccLog -RedirectStandardError "$isccLog.err"
if ($pSetup.ExitCode -ne 0) { throw "ISCC failed exit=$($pSetup.ExitCode) (see $isccLog)" }
if (-not (Test-Path $SetupOut)) { throw "Setup missing: $SetupOut" }
Write-Host "  OK $SetupOut ($((Get-Item $SetupOut).Length) bytes)"

New-Item -ItemType Directory -Path $OutFull -Force | Out-Null
Get-ChildItem $OutFull -Force | Remove-Item -Force -Recurse
Copy-Item $SetupOut (Join-Path $OutFull "EVERTBS_Setup.exe") -Force
Copy-Item $ApkOut (Join-Path $OutFull "EVERTBS.apk") -Force

$files = @(Get-ChildItem $OutFull -File)
$names = (@($files.Name) | Sort-Object) -join ","
if ($names -ne "EVERTBS.apk,EVERTBS_Setup.exe") { throw "release dir unexpected files: $names" }

if ($BundleContent) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $OutFull "EVERTBS.apk"))
  try {
    $entry = $zip.Entries | Where-Object { $_.FullName -like "*bundled_content/packs/game.pck" } | Select-Object -First 1
    if (-not $entry -or $entry.Length -ne $packSize) { throw "APK lacks bundled_content/packs/game.pck of $packSize bytes" }
  } finally { $zip.Dispose() }
  $setupSize = (Get-Item (Join-Path $OutFull "EVERTBS_Setup.exe")).Length
  if ($setupSize -lt [long]($packSize * 0.3)) { throw "Setup too small ($setupSize) - Inno seed may be missing" }
  Write-Host "Bundle gate OK (APK carries game.pck; Setup=$setupSize)"
}

Write-Host "Published to $OutFull :"
$files | Format-Table Name, Length, LastWriteTime
Write-Host "Shell $shellVer; content $(if ($BundleContent) { "$ContentVersion entry=$ContentEntry" } else { 'thin (none bundled)' })"
exit 0
