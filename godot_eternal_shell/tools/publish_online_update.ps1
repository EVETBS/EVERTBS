param(
  [string]$Version = "",
  [switch]$Push,
  [switch]$PushGitHub,
  [string]$Godot = "H:\game\game_dev\EVERTBS\tools\godot\Godot_v4.7.1-stable_win64.exe"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$HfStage = "H:\game_dev\eveautochess-hf"
$Pointer = "H:\game_dev\eveautochess-online-update"
$Dist = Join-Path $Root "content_dist"
$BaseUrl = "https://huggingface.co/buckets/liketocode789/eveautochess/resolve/"

function Get-Sha256Hex([string]$Path) {
  $hash = Get-FileHash -Path $Path -Algorithm SHA256
  return $hash.Hash.ToLowerInvariant()
}

function Get-NextVersion([string]$Current) {
  $now = Get-Date
  $prefix = "{0:D4}{1:D2}.{2}" -f $now.Year, $now.Month, $now.Day
  $n = 1
  if ($Current -match '^(\d{6})\.(\d{1,2})\.(\d{1,3})$') {
    $curPrefix = "{0}.{1}" -f $Matches[1], [int]$Matches[2]
    # Normalize: YYYYMM.D from today
    $todayPrefix = "{0:D6}.{1}" -f ($now.Year * 100 + $now.Month), $now.Day
    # Matches[1] is YYYYMM
    $ym = $Matches[1]
    $d = [int]$Matches[2]
    $nCur = [int]$Matches[3]
    $todayYm = "{0:D4}{1:D2}" -f $now.Year, $now.Month
    if ($ym -eq $todayYm -and $d -eq $now.Day) {
      $n = $nCur + 1
    }
  }
  return "{0}.{1}" -f $prefix, $n
}

# Resolve version
$existingVer = ""
$verPath = Join-Path $HfStage "version.json"
if (Test-Path $verPath) {
  try {
    $existingVer = (Get-Content $verPath -Raw | ConvertFrom-Json).version
  } catch {}
}
if (-not $Version) {
  $Version = Get-NextVersion $existingVer
}

Write-Host "Version: $Version"

# Export pack into content_dist then copy into hf staging
& (Join-Path $PSScriptRoot "export_content_pack.ps1") -Godot $Godot -OutPck (Join-Path $Dist "packs\game.pck")

$pck = Join-Path $Dist "packs\game.pck"
$sha = Get-Sha256Hex $pck
$size = (Get-Item $pck).Length

$manifest = [ordered]@{
  version = $Version
  files   = @(
    [ordered]@{
      path       = "packs/game.pck"
      sha256     = $sha
      size       = $size
      kind       = "pack"
      mountOrder = 10
    }
  )
}

$publishedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
$versionObj = [ordered]@{
  protocol              = 1
  version               = $Version
  publishedAt           = $publishedAt
  baseUrl               = $BaseUrl
  entry                 = "res://game/main.tscn"
  shellCompatibilityId  = "eveac-shell-v1"
  notes                 = "Snake demo content pack from godot_eternal_shell"
}

# Write content_dist
New-Item -ItemType Directory -Path (Join-Path $Dist "packs") -Force | Out-Null
$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $Dist "manifest.json") -Encoding utf8
$versionObj | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $Dist "version.json") -Encoding utf8

# Stage into eveautochess-hf
New-Item -ItemType Directory -Path (Join-Path $HfStage "packs") -Force | Out-Null
Copy-Item $pck (Join-Path $HfStage "packs\game.pck") -Force
Copy-Item (Join-Path $Dist "manifest.json") (Join-Path $HfStage "manifest.json") -Force
Copy-Item (Join-Path $Dist "version.json") (Join-Path $HfStage "version.json") -Force

# Also mirror into _hf_publish_root for sync
$pub = Join-Path $HfStage "_hf_publish_root"
New-Item -ItemType Directory -Path (Join-Path $pub "packs") -Force | Out-Null
Copy-Item $pck (Join-Path $pub "packs\game.pck") -Force
Copy-Item (Join-Path $Dist "manifest.json") (Join-Path $pub "manifest.json") -Force
Copy-Item (Join-Path $Dist "version.json") (Join-Path $pub "version.json") -Force

# Sync pointer repo files locally (no push unless asked)
if (Test-Path $Pointer) {
  Copy-Item (Join-Path $Dist "version.json") (Join-Path $Pointer "version.json") -Force
  Copy-Item (Join-Path $Dist "manifest.json") (Join-Path $Pointer "manifest.json") -Force
}

Write-Host "Staged locally:"
Write-Host "  $HfStage"
Write-Host "  $Dist"

if ($Push) {
  Write-Host "Pushing HF bucket liketocode789/eveautochess ..."
  hf buckets sync $pub "hf://buckets/liketocode789/eveautochess" -v
  Write-Host "HF sync done."
} else {
  Write-Host "HF NOT pushed (pass -Push only after user confirms)."
}

if ($PushGitHub) {
  if (-not (Test-Path (Join-Path $Pointer ".git"))) {
    throw "Pointer repo missing git: $Pointer"
  }
  Push-Location $Pointer
  git add version.json manifest.json
  git status -sb
  git commit -m "sync hotupdate pointer $Version" 
  git push origin main
  Pop-Location
} else {
  Write-Host "GitHub pointer NOT pushed (pass -PushGitHub if needed)."
}

Write-Host "Done. Version $Version sha256=$sha"
