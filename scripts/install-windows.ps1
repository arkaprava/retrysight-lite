# SPDX-License-Identifier: Apache-2.0

$ErrorActionPreference = "Stop"

$Prefix = if ($env:RETRYSIGHT_PREFIX) { $env:RETRYSIGHT_PREFIX } else {
  Join-Path $env:LOCALAPPDATA "RetrySightLite"
}
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinSrc = Join-Path $ScriptDir "retrysight-lite.exe"
if (-not (Test-Path $BinSrc)) {
  $Alt = Join-Path $ScriptDir "..\release\win-x64\retrysight-lite.exe"
  if (Test-Path $Alt) { $BinSrc = $Alt } else {
    Write-Error "retrysight-lite.exe not found. Run npm run dist:win first."
  }
}

$BinDir = Join-Path $Prefix "bin"
$DataDir = Join-Path $Prefix "data"
New-Item -ItemType Directory -Force -Path $BinDir, $DataDir | Out-Null
# Data dir contains DB + tokens — restrict to the current user only
icacls $DataDir /inheritance:r /grant:r "$env:USERNAME:(OI)(CI)F" | Out-Null
Copy-Item -Force $BinSrc (Join-Path $BinDir "retrysight-lite.exe")

$Exe = Join-Path $BinDir "retrysight-lite.exe"
$TaskName = "RetrySightLite"

$Action = New-ScheduledTaskAction -Execute $Exe -Argument "--headless" -WorkingDirectory $Prefix
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

$EnvArgs = @(
  "RETRYSIGHT_HEADLESS=1",
  "RETRYSIGHT_HOST=127.0.0.1",
  "RETRYSIGHT_DATA_DIR=$DataDir",
  "RETRYSIGHT_DB_PATH=$(Join-Path $DataDir 'retrysight-lite.db')"
)

# Scheduled tasks don't inherit custom env easily; use a wrapper cmd
$Wrapper = Join-Path $BinDir "run-headless.cmd"
@"
@echo off
set RETRYSIGHT_HEADLESS=1
set RETRYSIGHT_HOST=127.0.0.1
set RETRYSIGHT_DATA_DIR=$DataDir
set RETRYSIGHT_DB_PATH=$DataDir\retrysight-lite.db
set NODE_OPTIONS=--experimental-sqlite
"$Exe" --headless
"@ | Set-Content -Encoding ASCII $Wrapper

$Action = New-ScheduledTaskAction -Execute $Wrapper -WorkingDirectory $Prefix
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Description "RetrySightLite standalone (loopback API + collectors)" | Out-Null
Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

Write-Host "Installed RetrySightLite → $Prefix"
Write-Host "  binary:  $Exe"
Write-Host "  task:    $TaskName (at logon, headless on 127.0.0.1:18081)"
Write-Host "  data:    $DataDir"
Write-Host "  tokens:  $DataDir\admin-token  and  $DataDir\agent-api-key"
Write-Host "TUI:       & '$Exe'"
Write-Host "Uninstall: Unregister-ScheduledTask -TaskName $TaskName -Confirm:`$false; Remove-Item -Recurse -Force '$Prefix'"
