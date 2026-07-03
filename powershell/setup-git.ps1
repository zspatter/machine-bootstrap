<#
.SYNOPSIS
    Fresh-machine bootstrap: installs git via winget. Extracted from the
    retired setup-python-env.ps1 -- uv needs no git, but cloning
    sym-lattice or anything else still does.

.NOTES
    Safe to re-run.
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

Write-Step 'Checking for git'
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Info "Found $(git --version) at $((Get-Command git).Source)"
    exit 0
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    # Installing git is this script's entire job, so unlike the retired
    # best-effort Ensure-Git, a missing winget is a hard failure here.
    Write-Info 'No winget available; install git manually from https://git-scm.com, then re-run.'
    exit 1
}

Write-Info 'Installing via winget.'
winget install -e --id Git.Git --accept-package-agreements --accept-source-agreements
if ($LASTEXITCODE -ne 0) { throw "winget install exited with code $LASTEXITCODE" }
Update-SessionPath

Write-Step 'Verifying'
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Info "$(git --version)"
}
else {
    Write-Info 'git installed but not yet on PATH in this session. Open a new shell.'
}

exit 0
