<#
.SYNOPSIS
    Fresh-machine bootstrap: installs the Zed editor via winget.

.NOTES
    Safe to re-run. Zed manages its own updates in-app; winget upgrade
    (or update-all.ps1) also works.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = @($machine, $user) -join ';'
}

Update-SessionPath

Write-Step 'Checking for Zed'
if (Get-Command zed -ErrorAction SilentlyContinue) {
    Write-Info "Found $((Get-Command zed).Source)"
    Write-Info 'To update: winget upgrade ZedIndustries.Zed (or Zed updates itself in-app).'
    exit 0
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Info 'No winget available; install manually from https://zed.dev, then re-run.'
    exit 1
}

Write-Info 'Installing via winget.'
winget install -e --id ZedIndustries.Zed --accept-package-agreements --accept-source-agreements
if ($LASTEXITCODE -ne 0) { throw "winget install exited with code $LASTEXITCODE" }

Write-Step 'Verifying'
Update-SessionPath
if (Get-Command zed -ErrorAction SilentlyContinue) {
    Write-Info 'Zed installed.'
}
else {
    winget list --id ZedIndustries.Zed --accept-source-agreements | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Zed not found after install' }
    Write-Info 'Zed installed (registered with winget; may need a new shell for PATH).'
}

Write-Step 'Done'
exit 0
