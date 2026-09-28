<#
.SYNOPSIS
  Installs/updates the Email Sentinel integration into the local Hermes Agent:
  cron scripts, Sentinel skills, and the three cron jobs. Safe to re-run.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File hermes\install.ps1
#>
[CmdletBinding()]
param(
  [string]$HermesRoot = (Join-Path $env:LOCALAPPDATA 'hermes'),
  [string]$HermesProfile = '',
  [string]$DesignSkillsSource = '',
  [string]$Model = 'gemini-3.7-flash',
  [string]$Provider = 'gemini',
  [switch]$SkipCron
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$hermes = Join-Path $HermesRoot 'bin\hermes.exe'
if (-not (Test-Path $hermes)) { throw "Hermes not found at $hermes" }

# Hermes keeps skills/scripts/cron per profile; target the active one by default.
if (-not $HermesProfile) {
  $activeFile = Join-Path $HermesRoot 'active_profile'
  if (Test-Path $activeFile) { $HermesProfile = (Get-Content $activeFile -Raw).Trim() }
}
$HermesHome = $HermesRoot
if ($HermesProfile -and (Test-Path (Join-Path $HermesRoot "profiles\$HermesProfile"))) {
  $HermesHome = Join-Path $HermesRoot "profiles\$HermesProfile"
}
Write-Host "Target Hermes home: $HermesHome (profile: $(if ($HermesProfile) { $HermesProfile } else { 'default' }))"

# 0. Windows scheduled task that owns the API server process
if ($IsWindows -or $env:OS -eq 'Windows_NT') {
  & (Join-Path $PSScriptRoot 'windows\register-api-task.ps1') -Repo $repo
}

# 1. Scripts -> ~/.hermes/scripts (repo path baked into sentinel_common.py)
$scriptsDir = Join-Path $HermesHome 'scripts'
New-Item -ItemType Directory -Force $scriptsDir | Out-Null
Get-ChildItem (Join-Path $PSScriptRoot 'scripts') -Filter *.py | ForEach-Object {
  $content = Get-Content $_.FullName -Raw
  if ($_.Name -eq 'sentinel_common.py') {
    $content = $content -replace 'r"D:\\Murphy Labs\\email-sentinel"', ('r"' + $repo + '"')
  }
  [System.IO.File]::WriteAllText((Join-Path $scriptsDir $_.Name), $content, (New-Object System.Text.UTF8Encoding $false))
}
Write-Host "Installed scripts to $scriptsDir"

# 2. Skills -> ~/.hermes/skills/sentinel/<name>
$skillsDir = Join-Path $HermesHome 'skills\sentinel'
New-Item -ItemType Directory -Force $skillsDir | Out-Null
Get-ChildItem (Join-Path $PSScriptRoot 'skills') -Directory | ForEach-Object {
  $dest = Join-Path $skillsDir $_.Name
  New-Item -ItemType Directory -Force $dest | Out-Null
  Copy-Item (Join-Path $_.FullName '*') $dest -Recurse -Force
}
Write-Host "Installed skills to $skillsDir"

# 2b. Design skills (ui-ux-pro-max, liquid-glass) used by the app builder.
#     Pass -DesignSkillsSource <dir containing both skill folders> to (re)install them.
if ($DesignSkillsSource) {
  $designDir = Join-Path $HermesHome 'skills\design'
  New-Item -ItemType Directory -Force $designDir | Out-Null
  foreach ($name in 'ui-ux-pro-max', 'liquid-glass') {
    $src = Join-Path $DesignSkillsSource $name
    if (Test-Path $src) {
      Copy-Item $src $designDir -Recurse -Force
      Write-Host "Installed design skill $name"
    }
  }
}

if ($SkipCron) { return }

# 3. Cron jobs (created once; re-runs leave existing jobs untouched)
$existing = (& $hermes cron list --all 2>$null | Out-String)
function Add-Job([string]$Name, [string[]]$CronArgs) {
  if ($existing -match [regex]::Escape($Name)) {
    Write-Host "Cron job '$Name' already exists - skipped"
    return
  }
  & $hermes cron create @CronArgs --name $Name
  if ($LASTEXITCODE -ne 0) { throw "Failed to create cron job $Name" }
  Write-Host "Created cron job '$Name'"
}

Add-Job 'sentinel-watchdog' @('every 5m', '--script', 'sentinel_watchdog.py', '--no-agent', '--deliver', 'local')
Add-Job 'sentinel-scan' @('every 5m', '--script', 'sentinel_scan.py', '--no-agent', '--deliver', 'local')
Add-Job 'sentinel-briefing' @(
  '0 8,18 * * *',
  'Write and save the Sentinel inbox briefing for the owner, following the sentinel-briefing skill exactly. The period and CONTEXT_JSON are provided below.',
  '--script', 'sentinel_briefing_context.py',
  '--skill', 'sentinel-briefing',
  '--model', $Model, '--provider', $Provider,
  '--deliver', 'local'
)

& $hermes cron list
