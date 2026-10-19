# EVERTBS → EchoesDump only. Uninstall com.evertbs.game, then install. Never adb install -r.
param(
  [string]$Apk = "H:\game\game_dev\EVERTBS\godot_eternal_shell\builds\android\EVERTBS.apk"
)

$ErrorActionPreference = "Stop"
$adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) { throw "adb not found: $adb" }
if (-not (Test-Path $Apk)) { throw "APK not found: $Apk" }

$info = Get-Item $Apk
Write-Host ("APK {0}" -f $info.FullName)
Write-Host ("size {0}  mtime {1:yyyy-MM-dd HH:mm:ss}" -f $info.Length, $info.LastWriteTime)

$lines = & $adb devices
$serials = @()
foreach ($line in $lines) {
  if ($line -match "^(\S+)\s+device$") {
    $serial = $Matches[1]
    $name = (& $adb -s $serial shell getprop ro.boot.qemu.avd_name).Trim()
    if ($name.StartsWith("EchoesDump")) { $serials += $serial }
  }
}
if ($serials.Count -eq 0) { throw "No online EchoesDump emulator" }

foreach ($serial in $serials) {
  Write-Host "uninstall $serial"
  & $adb -s $serial uninstall com.evertbs.game
  Write-Host "install $serial"
  & $adb -s $serial install $Apk
  if ($LASTEXITCODE -ne 0) { throw "install failed on $serial" }
}
Write-Host ("installed {0}" -f $info.FullName)
