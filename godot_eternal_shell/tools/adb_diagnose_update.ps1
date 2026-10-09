param(
  [string]$Serial = "",
  [string]$Package = "com.eveautochess.game",
  [switch]$ClearData,
  [switch]$Launch,
  [int]$Seconds = 90
)

$ErrorActionPreference = "Stop"
$adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
  $adb = (Get-Command adb -ErrorAction Stop).Source
}

function Adb([string[]]$Args) {
  if ($Serial) {
    & $adb -s $Serial @Args
  } else {
    & $adb @Args
  }
}

Write-Host "=== devices ==="
& $adb devices -l
if (-not $Serial) {
  $lines = & $adb devices | Where-Object { $_ -match "\tdevice$" }
  if ($lines.Count -ge 1) {
    $Serial = ($lines[0] -split "\s+")[0]
    Write-Host "Using serial=$Serial"
  }
}

Write-Host "=== package ==="
Adb @("shell", "pm", "path", $Package)

if ($ClearData) {
  Write-Host "=== pm clear ==="
  Adb @("shell", "pm", "clear", $Package)
}

Adb @("logcat", "-c") | Out-Null

if ($Launch) {
  Write-Host "=== launch ==="
  Adb @("shell", "am", "start", "-n", "$Package/com.godot.game.GodotAppLauncher")
}

Write-Host "=== logcat ${Seconds}s (godot / UpdateClient / ERROR) ==="
$deadline = (Get-Date).AddSeconds($Seconds)
$proc = if ($Serial) {
  Start-Process -FilePath $adb -ArgumentList @("-s", $Serial, "logcat", "-v", "time") -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\eve_adb_logcat.txt"
} else {
  Start-Process -FilePath $adb -ArgumentList @("logcat", "-v", "time") -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\eve_adb_logcat.txt"
}

while ((Get-Date) -lt $deadline -and -not $proc.HasExited) {
  Start-Sleep -Seconds 2
  if (Test-Path "$env:TEMP\eve_adb_logcat.txt") {
    Get-Content "$env:TEMP\eve_adb_logcat.txt" -Tail 40 -ErrorAction SilentlyContinue |
      Where-Object { $_ -match "godot|Godot|UpdateClient|Boot|SCRIPT ERROR|main\.tscn|resource_pack|STALL|http_get" } |
      ForEach-Object { Write-Host $_ }
  }
}

if (-not $proc.HasExited) {
  Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}

$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) "tools"
$png = Join-Path $outDir "_adb_boot_capture.png"
Adb @("shell", "screencap", "-p", "/sdcard/eve_boot.png") | Out-Null
Adb @("pull", "/sdcard/eve_boot.png", $png) | Out-Null
Write-Host "Screenshot: $png"

Write-Host "=== hint ==="
Write-Host "If UI shows 下载 … XX/XX KB stuck at equal sizes, look for:"
Write-Host "  [UpdateClient] bytes full … waiting request_completed"
Write-Host "  [UpdateClient] STALL: full body"
Write-Host "After fix expect: http_get_bytes done → wrote → load_resource_pack OK → [Boot] change_scene"
