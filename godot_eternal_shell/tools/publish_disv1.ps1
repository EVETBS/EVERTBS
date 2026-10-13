param(
  [string]$Godot = "H:\game\game_dev\EVERTBS\tools\godot\Godot_v4.7.1-stable_win64.exe",
  [string]$Disv1 = "H:\disv1",
  [string]$Iscc = "",
  # Default: ship full multi-pack content in Setup + APK. Opt out with -ThinShell.
  [switch]$BundleContent,
  [switch]$ThinShell,
  # Optional: directory containing packs/*.pck (defaults to HF staging packs/).
  [string]$ContentPacksDir = "",
  # Legacy single-file override (still accepted; prefer multi-pack dir).
  [string]$ContentPck = "",
  [string]$ContentVersion = "",
  [string]$ContentEntry = "res://scenes/main_menu.tscn"
)

$ErrorActionPreference = "Stop"
## Unspecified → full content pack (user rule 2026-08-08). Only -ThinShell skips seed.
if ($ThinShell) {
  $BundleContent = $false
} elseif (-not $PSBoundParameters.ContainsKey("BundleContent")) {
  $BundleContent = $true
}
$Root = Split-Path -Parent $PSScriptRoot
$Shell = Join-Path $Root "shell"
$WinOut = Join-Path $Root "builds\windows\EVETBS.exe"
$ApkOut = Join-Path $Root "builds\android\EVETBS.apk"
$SetupOut = Join-Path $Root "builds\windows\EVETBS_Setup.exe"
$Iss = Join-Path $Root "installer\EVETBS.iss"
$SeedDir = Join-Path $Root "builds\seed"
$BundledDir = Join-Path $Shell "bundled_content"

$env:JAVA_HOME = if (Test-Path "C:\Program Files\Java\jdk-20") { "C:\Program Files\Java\jdk-20" } else { $env:JAVA_HOME }
if ($env:JAVA_HOME) { $env:Path = "$env:JAVA_HOME\bin;" + $env:Path }
$env:ANDROID_HOME = if (-not $env:ANDROID_HOME) { "C:\Users\WXH\AppData\Local\Android\Sdk" } else { $env:ANDROID_HOME }

if (-not $Iscc) {
  $cands = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
  )
  $Iscc = $cands | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Iscc -or -not (Test-Path $Iscc)) {
  throw "Inno Setup ISCC.exe not found. Install JRSoftware.InnoSetup (winget)."
}

function Invoke-GodotExport {
  param(
    [string]$Label,
    [string]$PresetName,
    [string]$ExportFlag,
    [string]$OutFile
  )
  $before = if (Test-Path $OutFile) { (Get-Item $OutFile).LastWriteTimeUtc } else { [datetime]::MinValue }
  Write-Host "Export $Label (preset '$PresetName')..."
  $argLine = "--headless --path `"$Shell`" $ExportFlag `"$PresetName`" `"$OutFile`""
  $p = Start-Process -FilePath $Godot -ArgumentList $argLine -WorkingDirectory $Shell -Wait -PassThru -NoNewWindow
  if ($p.ExitCode -ne 0) {
    throw "Godot export failed ($Label) exit=$($p.ExitCode)"
  }
  if (-not (Test-Path $OutFile)) {
    throw "$Label export missing output: $OutFile"
  }
  $after = (Get-Item $OutFile).LastWriteTimeUtc
  if ($after -le $before) {
    throw "$Label export did not refresh $OutFile (stamp still $after)"
  }
  Write-Host "  OK $OutFile ($((Get-Item $OutFile).Length) bytes, local $($after.ToLocalTime()))"
}

function Clear-BundledContentStaging {
  if (Test-Path $BundledDir) {
    Remove-Item (Join-Path $BundledDir "packs") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $BundledDir "seed_meta.json") -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path $SeedDir) {
    Remove-Item $SeedDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Stage-BundledContent {
  $hfPacks = "H:\game_dev\EVETBS-hf\_hf_publish_root\packs"
  $hfManifest = "H:\game_dev\EVETBS-hf\_hf_publish_root\manifest.json"
  $useExplicitPacks = [bool]$ContentPacksDir

  if (-not $ContentPacksDir) {
    if ($ContentPck -and (Test-Path $ContentPck)) {
      $script:ContentPacksDir = Split-Path -Parent $ContentPck
    } elseif (Test-Path $hfPacks) {
      $script:ContentPacksDir = $hfPacks
    }
  }

  $needPack = $true
  if (-not $ContentPacksDir -or -not (Test-Path $ContentPacksDir)) {
    $needPack = $true
  }
  if (-not $useExplicitPacks) {
    ## Refresh default packs from EVETBS-dev; an explicit directory is
    ## already a pinned, caller-verified release payload.
    Write-Host "BundleContent: exporting content packs from EVETBS-dev..."
    $packScript = "H:\game_dev\EVETBS-dev\tools\pack_hf_content.ps1"
    if (-not (Test-Path $packScript)) { throw "Missing $packScript and no multi-pack staging" }
    & $packScript
    $script:ContentPacksDir = $hfPacks
  } else {
    Write-Host "BundleContent: using explicit content packs from $ContentPacksDir"
  }

  ## Prefer manifest file list (tonnage models_* + data/logic/ui/audio).
  $requiredRels = @()
  $manPath = $hfManifest
  if ($ContentPacksDir -and (Test-Path (Join-Path (Split-Path $ContentPacksDir -Parent) "manifest.json"))) {
    $manPath = Join-Path (Split-Path $ContentPacksDir -Parent) "manifest.json"
  }
  if (Test-Path $manPath) {
    $man = Get-Content $manPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($f in $man.files) {
      $p = [string]$f.path
      if ($p -and $p.StartsWith("packs/")) { $requiredRels += $p }
    }
  }
  if ($requiredRels.Count -lt 5) {
    $requiredRels = @(
      "packs/data.pck", "packs/logic.pck", "packs/ui.pck",
      "packs/models_env.pck", "packs/models_frigate.pck", "packs/models_cruiser.pck",
      "packs/models_battleship.pck", "packs/models_capital.pck", "packs/audio.pck"
    )
  }

  foreach ($rel in $requiredRels) {
    $name = Split-Path $rel -Leaf
    $p = Join-Path $ContentPacksDir $name
    if (-not (Test-Path $p)) { throw "Content pack missing: $p" }
  }

  if (-not $ContentVersion) {
    $verFile = "H:\game_dev\EVETBS-hf\_hf_publish_root\version.json"
    if (-not (Test-Path $verFile)) { $verFile = "H:\game_dev\EVETBS-hf\version.json" }
    if (Test-Path $verFile) {
      $vj = Get-Content $verFile -Raw -Encoding UTF8 | ConvertFrom-Json
      $script:ContentVersion = [string]$vj.version
      if ($vj.entry) { $script:ContentEntry = [string]$vj.entry }
    }
  }
  if (-not $ContentVersion) { $script:ContentVersion = "202607.29.04" }

  $packMeta = @()
  $totalSize = 0L
  New-Item -ItemType Directory -Path (Join-Path $SeedDir "packs") -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $BundledDir "packs") -Force | Out-Null
  foreach ($rel in $requiredRels) {
    $name = Split-Path $rel -Leaf
    $src = Join-Path $ContentPacksDir $name
    $sha = (Get-FileHash -Path $src -Algorithm SHA256).Hash.ToLowerInvariant()
    $size = (Get-Item $src).Length
    $totalSize += $size
    Write-Host "BundleContent pack: $rel size=$size sha=$sha"
    Copy-Item $src (Join-Path $SeedDir "packs\$name") -Force
    Copy-Item $src (Join-Path $BundledDir "packs\$name") -Force
    $packMeta += [ordered]@{
      path   = $rel
      sha256 = $sha
      size   = $size
    }
  }
  Write-Host "BundleContent: version=$ContentVersion packs=$($packMeta.Count) totalSize=$totalSize"

  $applied = [ordered]@{
    version   = $ContentVersion
    entry     = $ContentEntry
    appliedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    platform  = "windows"
    source    = "inno_bundle"
    packs     = @($requiredRels)
  }
  ($applied | ConvertTo-Json -Depth 5) | Set-Content (Join-Path $SeedDir "applied_version.json") -Encoding utf8

  $meta = [ordered]@{
    version = $ContentVersion
    entry   = $ContentEntry
    packs   = $packMeta
  }
  ($meta | ConvertTo-Json -Depth 6) | Set-Content (Join-Path $BundledDir "seed_meta.json") -Encoding utf8
  Write-Host "  staged Inno seed + Android bundled_content (multi-pack)"
}

# Always clear previous fat seed so thin builds stay thin.
Clear-BundledContentStaging
if ($BundleContent) {
  Stage-BundledContent
}

New-Item -ItemType Directory -Path (Split-Path $WinOut) -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $ApkOut) -Force | Out-Null

Invoke-GodotExport -Label "Windows" -PresetName "Windows Desktop" -ExportFlag "--export-release" -OutFile $WinOut
## Android: use debug export (no release keystore on this machine). Shell GDScript
## warnings are warn-level so Boot/Autoload still load on device.
Invoke-GodotExport -Label "Android" -PresetName "Android" -ExportFlag "--export-debug" -OutFile $ApkOut

# Sync AppVersion in .iss from project.godot when possible
$projGodot = Join-Path $Shell "project.godot"
$verLine = Select-String -Path $projGodot -Pattern '^config/version="([^"]+)"' | Select-Object -First 1
if ($verLine) {
  $ver = $verLine.Matches[0].Groups[1].Value
  $issText = Get-Content $Iss -Raw -Encoding UTF8
  $issText = [regex]::Replace($issText, '#define MyAppVersion "[^"]+"', "#define MyAppVersion `"$ver`"")
  if ($ver -match '^(\d{4})(\d{2})\.(\d+)\.(\d+)$') {
    $vi = "{0}.{1}.{2}.{3}" -f $Matches[1], [int]$Matches[2], $Matches[3], $Matches[4]
    $issText = [regex]::Replace($issText, 'VersionInfoVersion=[^\r\n]+', "VersionInfoVersion=$vi")
  }
  Set-Content -Path $Iss -Value $issText -Encoding UTF8 -NoNewline
  Write-Host "Inno AppVersion -> $ver"
}

Write-Host "Build Inno Setup installer..."
if (Test-Path $SetupOut) { Remove-Item $SetupOut -Force }
$pSetup = Start-Process -FilePath $Iscc -ArgumentList "`"$Iss`"" -WorkingDirectory (Split-Path $WinOut) -Wait -PassThru -NoNewWindow
if ($pSetup.ExitCode -ne 0) {
  throw "ISCC failed exit=$($pSetup.ExitCode)"
}
if (-not (Test-Path $SetupOut)) {
  throw "Setup missing: $SetupOut"
}
Write-Host "  OK $SetupOut ($((Get-Item $SetupOut).Length) bytes)"

New-Item -ItemType Directory -Path $Disv1 -Force | Out-Null
Get-ChildItem $Disv1 -Force | Remove-Item -Force -Recurse
Copy-Item $SetupOut (Join-Path $Disv1 "EVETBS_Setup.exe") -Force
Copy-Item $ApkOut (Join-Path $Disv1 "EVETBS.apk") -Force

## Sidecar sample mod zip (not bundled into Setup/APK/PCK).
$BeitouSample = "H:\game_dev\EVETBS-dev\godot_project\mod_samples\beitou-float-turret"
$BeitouZip = Join-Path $Disv1 "beitou-float-turret.zip"
if (-not (Test-Path (Join-Path $BeitouSample "mod.json"))) {
  throw "Missing beitou sample mod: $BeitouSample"
}
if (Test-Path $BeitouZip) { Remove-Item $BeitouZip -Force }
## Top-level folder name = package_name (import-friendly).
Compress-Archive -Path $BeitouSample -DestinationPath $BeitouZip -CompressionLevel Optimal
if (-not (Test-Path $BeitouZip)) { throw "Failed to write $BeitouZip" }
Write-Host "  OK $BeitouZip ($((Get-Item $BeitouZip).Length) bytes)"

$files = @(Get-ChildItem $Disv1 -File)
if ($files.Count -ne 3) { throw "disv1 must contain exactly 3 files" }
$names = @($files.Name | Sort-Object)
$expect = @("EVETBS.apk", "EVETBS_Setup.exe", "beitou-float-turret.zip") | Sort-Object
if (($names -join ",") -ne ($expect -join ",")) {
  throw "disv1 unexpected files: $($names -join ', ')"
}

if ($BundleContent) {
  $apkSize = (Get-Item (Join-Path $Disv1 "EVETBS.apk")).Length
  $setupSize = (Get-Item (Join-Path $Disv1 "EVETBS_Setup.exe")).Length
  if ($apkSize -lt 200MB) {
    throw "BundleContent APK too small ($apkSize) — bundled_content may not have been exported"
  }
  if ($setupSize -lt 80MB) {
    throw "BundleContent Setup too small ($setupSize) — Inno seed may be missing"
  }
  Write-Host "BundleContent size gate OK (APK=$apkSize Setup=$setupSize)"
}

Write-Host "Published to $Disv1 :"
$files | Format-Table Name, Length, LastWriteTime
if ($BundleContent) {
  Write-Host "Content bundled: version=$ContentVersion entry=$ContentEntry"
}
