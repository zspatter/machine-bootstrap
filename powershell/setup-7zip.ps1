<#
.SYNOPSIS
    Fresh-machine bootstrap: installs NanaZip (the maintained 7-Zip fork)
    via winget.

.NOTES
    Safe to re-run.

    Why NanaZip over classic 7-Zip (2026-07 decision): the same 7-Zip
    engine underneath -- M2-Team rebases on upstream releases -- plus
    the Windows 11 TOP-LEVEL context menu that upstream has never
    implemented (verified against the 7-Zip changelog through 26.02;
    classic 7-Zip only ever appears under "Show more options"), a
    modernized UI, extra codecs (Zstandard/Brotli/LZ4), and Store-based
    auto-updates. Trade-offs, accepted: it can lag upstream briefly
    after each 7-Zip release, and the CLI is NanaZipC (an app-execution
    alias) rather than 7z.exe at a fixed path -- nothing in these repos
    shells out to either. If the fork ever stagnates, classic 7-Zip is
    the fallback: swap the id back to 7zip.7zip.

    The MSIX registers the Win11 context menu itself; Explorer may need
    a restart (or a fresh session) before the entry shows up.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

Write-Step 'Checking for NanaZip'
$found = $false
if (Get-Command NanaZipC -ErrorAction SilentlyContinue) {
    $found = $true
}
else {
    winget list --id M2Team.NanaZip --accept-source-agreements 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $found = $true }
}

if ($found) {
    Write-Info 'NanaZip already installed (updates arrive via the Store / winget upgrade).'
}
else {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Info 'No winget available; install NanaZip from the Microsoft Store, then re-run.'
        exit 1
    }
    Write-Info 'Installing via winget.'
    winget install -e --id M2Team.NanaZip --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget install exited with code $LASTEXITCODE" }
    Write-Info 'Installed. Explorer may need a restart before the context menu appears.'
}

# Doubled context menus are the one migration hazard: classic 7-Zip's
# shell extension stays registered until it's uninstalled.
if (Test-Path (Join-Path $env:ProgramFiles '7-Zip\7z.exe')) {
    Write-Info 'Classic 7-Zip is also installed -- remove it to avoid duplicate menu entries:'
    Write-Info '  winget uninstall 7zip.7zip'
}

Write-Step 'Done'
exit 0
