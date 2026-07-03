<#
.SYNOPSIS
    Fresh-machine bootstrap: installs Zen Browser via winget.

.NOTES
    Safe to re-run. GUI app, no CLI executable expected on PATH --
    presence is checked via winget's registry and the default install
    location.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

function Test-ZenInstalled {
    if (Test-Path "$env:ProgramFiles\Zen Browser\zen.exe") { return $true }
    if (Test-Path "$env:LOCALAPPDATA\Programs\Zen Browser\zen.exe") { return $true }
    winget list --id Zen-Team.Zen-Browser -e --accept-source-agreements 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

Write-Step 'Checking for Zen Browser'
if (Test-ZenInstalled) {
    Write-Info 'Already installed.'
    Write-Info 'To update: winget upgrade Zen-Team.Zen-Browser (or Zen updates itself in-app).'
    exit 0
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Info 'No winget available; install manually from https://zen-browser.app, then re-run.'
    exit 1
}

Write-Info 'Installing via winget.'
winget install -e --id Zen-Team.Zen-Browser --accept-package-agreements --accept-source-agreements
if ($LASTEXITCODE -ne 0) { throw "winget install exited with code $LASTEXITCODE" }

Write-Step 'Verifying'
if (Test-ZenInstalled) {
    Write-Info 'Zen Browser installed.'
}
else {
    throw 'Zen Browser not found after install'
}

Write-Step 'Done'
exit 0
