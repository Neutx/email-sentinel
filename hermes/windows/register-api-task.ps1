<#
.SYNOPSIS
  Registers the "EmailSentinel API" scheduled task: runs `email-sentinel serve`
  hidden, at logon, restarts on failure, no time limit. Hermes' watchdog starts
  it on demand with `schtasks /Run`. Task Scheduler (not Hermes) owns the process,
  so it survives Hermes restarts and job-object cleanup. Safe to re-run.
#>
[CmdletBinding()]
param(
  [string]$Repo = '',
  [string]$TaskName = 'EmailSentinel API'
)

$ErrorActionPreference = 'Stop'
if (-not $Repo) { $Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
$runtime = Join-Path $env:LOCALAPPDATA 'email-sentinel'
$logs = Join-Path $runtime 'logs'
New-Item -ItemType Directory -Force $logs | Out-Null

$uv = (Get-Command uv -ErrorAction SilentlyContinue).Source
if (-not $uv) { $uv = Join-Path $env:LOCALAPPDATA 'hermes\bin\uv.exe' }
if (-not (Test-Path $uv)) { throw 'uv not found' }

$cmdFile = Join-Path $runtime 'run-api.cmd'
$cmd = @"
@echo off
cd /d "$Repo"
echo === starting API %DATE% %TIME% ===>> "$logs\api.log"
"$uv" run --project "$Repo" email-sentinel serve >> "$logs\api.log" 2>&1
"@
[System.IO.File]::WriteAllText($cmdFile, $cmd, [System.Text.Encoding]::ASCII)

# wscript runs the .cmd with a hidden window and waits, so the task stays
# "Running" for the server's lifetime (prevents duplicate instances).
$vbsFile = Join-Path $runtime 'run-api-hidden.vbs'
$vbs = "WScript.Quit CreateObject(""WScript.Shell"").Run(""""""$cmdFile"""""", 0, True)"
[System.IO.File]::WriteAllText($vbsFile, $vbs, [System.Text.Encoding]::ASCII)

$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$vbsFile`"" -WorkingDirectory $Repo
$settings = New-ScheduledTaskSettingsSet `
  -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
  -MultipleInstances IgnoreNew `
  -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

try {
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Principal $principal -Description 'Email Sentinel REST API (managed by Hermes watchdog)' -Force | Out-Null
  Write-Host "Registered '$TaskName' (starts at logon; Hermes watchdog starts it on demand)."
} catch {
  # Logon triggers can require elevation; an on-demand task still works with the watchdog.
  Register-ScheduledTask -TaskName $TaskName -Action $action -Settings $settings `
    -Principal $principal -Description 'Email Sentinel REST API (managed by Hermes watchdog)' -Force | Out-Null
  Write-Host "Registered '$TaskName' without a logon trigger (needs elevation); the Hermes watchdog starts it within 5 minutes."
}
