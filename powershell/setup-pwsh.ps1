<#
.SYNOPSIS
    Bootstrap rung zero for Windows: installs PowerShell 7 (x64, MSI,
    machine-wide) and Windows Terminal. Written for WINDOWS POWERSHELL
    5.1 -- the only shell a clean machine ships -- so no pwsh-7 syntax
    here (no &&, no ternary). Every other script in this directory
    assumes pwsh 7; this is the one that gets you there.

.NOTES
    Safe to re-run.

    --source winget is load-bearing: the msstore source carries the same
    package id and can win resolution, installing the per-user MSIX
    build into WindowsApps -- fine for Store users, wrong for a
    machine-wide dev bootstrap (hit live: an --architecture x64 request
    landed in WindowsApps). The winget source serves the MSI.

    --architecture x64 is also load-bearing: an x86 pwsh on a 64-bit OS
    reads System32 through WOW64 redirection and silently loses sight of
    OpenSSH among other things (also hit live).

    Machine-scope MSI needs elevation: run from an admin 5.1 shell, or
    once sudo is available, `sudo powershell -File ...`.
#>

[CmdletBinding()]
param(
    # CI runners can't reliably install MSIX packages in session 0;
    # everything else about this script still validates there.
    [switch]$SkipWindowsTerminal
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

Write-Step 'Checking for PowerShell 7 (x64, machine-wide)'
if (Test-Path 'C:\Program Files\PowerShell\7\pwsh.exe') {
    Write-Info 'Already installed.'
}
else {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Info 'No winget. On Windows 10, install "App Installer" from the Microsoft Store, then re-run.'
        exit 1
    }
    Write-Info 'Installing via winget (MSI, machine scope -- needs elevation).'
    winget install -e --id Microsoft.PowerShell --architecture x64 --source winget --scope machine --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget install PowerShell exited with code $LASTEXITCODE" }
}

Write-Step 'Checking for Windows Terminal'
if ($SkipWindowsTerminal) {
    Write-Info 'Skipped by switch.'
}
elseif (Get-Command wt -ErrorAction SilentlyContinue) {
    Write-Info 'Already installed.'
}
else {
    winget install -e --id Microsoft.WindowsTerminal --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget install Windows Terminal exited with code $LASTEXITCODE" }
}

Write-Step 'Done'
Write-Info 'Open an ELEVATED PowerShell 7 and run the admin pass -- it enables'
Write-Info 'sudo, so this is the last elevated shell the bootstrap ever needs:'
Write-Info '  pwsh -NoProfile -File powershell\setup-windows-elevated.ps1'
Write-Info 'Then from a normal pwsh: powershell\install-all.ps1'
exit 0
