# SPDX-License-Identifier: Apache-2.0
#
# RetrySight Lite Windows installer
#   irm https://app.retrysight.com/install.ps1 | iex

$ErrorActionPreference = "Stop"

$InstallBase = if ($env:RETRYSIGHT_INSTALL_BASE) { $env:RETRYSIGHT_INSTALL_BASE } else { "https://app.retrysight.com/lite" }
$Version = if ($env:RETRYSIGHT_VERSION) { $env:RETRYSIGHT_VERSION } else { "latest" }
$ManifestUrl = if ($Version -eq "latest") { "$InstallBase/latest/manifest.json" } else { "$InstallBase/$Version/manifest.json" }

Write-Host "==> RetrySight Lite installer (Windows x64)"
Write-Host "==> Fetching manifest from $ManifestUrl"

$manifest = Invoke-RestMethod -Uri $ManifestUrl
$download = $manifest.downloads | Where-Object { $_.id -eq "win-x64" } | Select-Object -First 1
if (-not $download) { throw "No Windows x64 artifact in manifest" }

$tmp = Join-Path $env:TEMP ("retrysight-lite-" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$zipPath = Join-Path $tmp $download.filename

Write-Host "==> Downloading $($download.filename)"
Invoke-WebRequest -Uri $download.url -OutFile $zipPath

$hash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLower()
if ($hash -ne $download.sha256) { throw "Checksum mismatch for $($download.filename)" }
Write-Host "==> Checksum verified"

$dest = if ($env:RETRYSIGHT_INSTALL_DIR) { $env:RETRYSIGHT_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA "RetrySightLite" }
Expand-Archive -Path $zipPath -DestinationPath $tmp -Force
$src = Get-ChildItem -Path $tmp -Recurse -Filter "retrysightlite.exe" | Select-Object -First 1
if (-not $src) { throw "retrysightlite.exe not found in archive" }

New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -Force $src.FullName (Join-Path $dest "RetrySight Lite.exe")
$startMenu = [Environment]::GetFolderPath("Programs")
$shortcut = Join-Path $startMenu "RetrySight Lite.lnk"
# Optional: create shortcut via WScript if desired

Write-Host "==> Installed RetrySight Lite → $dest\RetrySight Lite.exe"
Write-Host "==> Done. No Node.js required — backend is bundled in the app."
Remove-Item -Recurse -Force $tmp
