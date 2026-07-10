<#
.SYNOPSIS
    Fresh-machine bootstrap: installs 7-Zip via winget.

.NOTES
    Safe to re-run.

    Context menu: the 7-Zip installer registers its classic shell
    extension itself -- nothing to wire here. On Windows 11 that menu
    lives under "Show more options" (Shift+F10 / Shift+RightClick): NO
    7-Zip release implements the modern top-level menu (verified against
    the full changelog through 26.02). If top-level entries ever matter
    enough, NanaZip (winget id M2Team.NanaZip) is the actively
    maintained 7-Zip fork packaged as MSIX with native Windows 11
    context-menu integration -- a drop-in swap for this script.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

Write-Step 'Checking for 7-Zip'
$SevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
if (Test-Path $SevenZip) {
    Write-Info "Found $SevenZip"
    Write-Info 'To update: winget upgrade 7zip.7zip (or update-all.ps1).'
    Write-Step 'Done'
    exit 0
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Info 'No winget available; install manually from https://www.7-zip.org, then re-run.'
    exit 1
}

Write-Info 'Installing via winget.'
winget install -e --id 7zip.7zip --accept-package-agreements --accept-source-agreements
if ($LASTEXITCODE -ne 0) { throw "winget install exited with code $LASTEXITCODE" }

Write-Step 'Verifying'
if (Test-Path $SevenZip) {
    Write-Info "$SevenZip installed (context menu under Win11's 'Show more options')."
}
else {
    throw '7z.exe not found after install'
}

Write-Step 'Done'
exit 0
