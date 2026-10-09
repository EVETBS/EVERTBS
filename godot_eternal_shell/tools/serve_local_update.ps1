param(
  [int]$Port = 8765,
  [string]$Root = ""
)

$ErrorActionPreference = "Stop"
if (-not $Root) {
  $Root = "H:\game_dev\eveautochess-hf\_hf_publish_root"
  if (-not (Test-Path (Join-Path $Root "version.json"))) {
    $Root = Join-Path (Split-Path -Parent $PSScriptRoot) "content_dist"
  }
}

if (-not (Test-Path $Root)) { throw "Serve root missing: $Root" }

# Patch a serve-local version.json so baseUrl stays on this server (shell also supports lockBaseUrl).
$verPath = Join-Path $Root "version.json"
if (Test-Path $verPath) {
  $ver = Get-Content $verPath -Raw | ConvertFrom-Json
  $ver.baseUrl = "http://127.0.0.1:$Port/"
  $ver | ConvertTo-Json -Depth 6 | Set-Content -Path $verPath -Encoding utf8
}

Write-Host "Serving $Root on http://127.0.0.1:$Port/"
Write-Host "Write user://bootstrap_override.json with:"
Write-Host ('  {{ "baseUrl": "http://127.0.0.1:{0}/", "lockBaseUrl": true }}' -f $Port)
Write-Host "Android: use http://<LAN-IP>:$Port/ and adb push override."

Set-Location $Root
python -m http.server $Port
