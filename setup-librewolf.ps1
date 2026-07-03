<#
.SYNOPSIS
    Fresh-machine bootstrap: installs LibreWolf via winget.

.NOTES
    Safe to re-run. GUI app -- presence is checked via the default install
    locations and winget's registry.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

function Test-LibreWolfInstalled {
    if (Test-Path "$env:ProgramFiles\LibreWolf\librewolf.exe") { return $true }
    if (Test-Path "$env:LOCALAPPDATA\Programs\LibreWolf\librewolf.exe") { return $true }
    winget list --id LibreWolf.LibreWolf -e --accept-source-agreements 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

Write-Step 'Checking for LibreWolf'
if (Test-LibreWolfInstalled) {
    Write-Info 'Already installed.'
    Write-Info 'To update: winget upgrade LibreWolf.LibreWolf'
    exit 0
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Info 'No winget available; install manually from https://librewolf.net, then re-run.'
    exit 1
}

Write-Info 'Installing via winget.'
winget install -e --id LibreWolf.LibreWolf --accept-package-agreements --accept-source-agreements
if ($LASTEXITCODE -ne 0) { throw "winget install exited with code $LASTEXITCODE" }

Write-Step 'Verifying'
if (Test-LibreWolfInstalled) {
    Write-Info 'LibreWolf installed.'
}
else {
    throw 'LibreWolf not found after install'
}

Write-Step 'Done'
exit 0
