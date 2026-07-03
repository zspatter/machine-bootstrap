<#
.SYNOPSIS
    Fresh-machine bootstrap: installs Obsidian (the app only) via winget.
    Vault setup is deliberately not here -- a notes vault is personal
    data, and this repo is public; sym-lattice's onboarding handles the
    private vault clone.

.NOTES
    Safe to re-run. Obsidian installs per-user and is a GUI app -- it
    does not put a CLI executable on PATH, so verification checks the
    install location rather than Get-Command.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

function Test-ObsidianInstalled {
    Test-Path "$env:LOCALAPPDATA\Programs\Obsidian\Obsidian.exe"
}

Write-Step 'Checking for Obsidian'
if (Test-ObsidianInstalled) {
    Write-Info "Found $env:LOCALAPPDATA\Programs\Obsidian\Obsidian.exe"
    Write-Info 'To update: winget upgrade Obsidian.Obsidian (or Obsidian updates itself in-app).'
    exit 0
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Info 'No winget available; install manually from https://obsidian.md, then re-run.'
    exit 1
}

Write-Info 'Installing via winget.'
winget install -e --id Obsidian.Obsidian --accept-package-agreements --accept-source-agreements
if ($LASTEXITCODE -ne 0) { throw "winget install exited with code $LASTEXITCODE" }

Write-Step 'Verifying'
if (Test-ObsidianInstalled) {
    Write-Info 'Obsidian installed.'
}
else {
    # winget can report success while the installer registers elsewhere;
    # fall back to asking winget itself before declaring failure.
    winget list --id Obsidian.Obsidian --accept-source-agreements | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Obsidian not found after install' }
    Write-Info 'Obsidian installed (registered with winget; non-default location).'
}

Write-Step 'Done'
Write-Info 'Vault setup is personal data and lives in sym-lattice onboarding, not here.'
exit 0
