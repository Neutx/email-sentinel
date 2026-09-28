<#
.SYNOPSIS
  Deploys origin/main of Email Sentinel to the dedicated live checkout that
  production (API task + Hermes cron jobs) runs from, then restarts the API.

  Production must never run from the development working tree: agents switch
  that tree between feature branches.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File hermes\deploy.ps1
#>
[CmdletBinding()]
param(
  [string]$LivePath = 'D:\Murphy Labs\email-sentinel-live',
  [string]$Ref = 'origin/main'
)

$ErrorActionPreference = 'Stop'
$devRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

git -C $devRepo fetch --quiet origin
if (-not (Test-Path (Join-Path $LivePath '.git'))) {
  git -C $devRepo worktree add --detach $LivePath $Ref
  Write-Host "Created live checkout at $LivePath"
} else {
  git -C $LivePath checkout --quiet --detach $Ref
}
$sha = git -C $LivePath rev-parse --short HEAD
Write-Host "Live checkout at $Ref ($sha)"

# Secrets are not in git: seed the live .env from the dev checkout once.
$liveEnv = Join-Path $LivePath '.env'
if (-not (Test-Path $liveEnv)) {
  Copy-Item (Join-Path $devRepo '.env') $liveEnv
  Write-Host 'Copied .env into the live checkout (edit it there from now on).'
}

Push-Location $LivePath
try { uv sync --quiet --frozen } finally { Pop-Location }

# Re-point the API task, Hermes scripts and skills at the live checkout.
& (Join-Path $LivePath 'hermes\install.ps1') -SkipCron

schtasks /End /TN 'EmailSentinel API' 2>$null | Out-Null
Start-Sleep -Seconds 2
Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue |
  ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
schtasks /Run /TN 'EmailSentinel API' | Out-Null
Write-Host "Deployed $sha and restarted the API."
