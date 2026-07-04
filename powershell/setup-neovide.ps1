<#
.SYNOPSIS
    Fresh-machine bootstrap: installs Neovide (GUI frontend for Neovim)
    via winget. The nvim config it renders lives in sym-lattice; Neovide
    embeds whatever nvim is on PATH, so setup-nvim.ps1 is the real
    prerequisite.

.NOTES
    Safe to re-run. GUI-specific settings (font, animations, scale) live
    in the nvim config gated on vim.g.neovide -- nothing to configure here.
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

Write-Step 'Checking for Neovide'
if (Get-Command neovide -ErrorAction SilentlyContinue) {
    Write-Info "Found $((Get-Command neovide).Source)"
    Write-Info 'To update: winget upgrade Neovide.Neovide (or update-all.ps1).'
    exit 0
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Info 'No winget available; install manually from https://neovide.dev, then re-run.'
    exit 1
}

Write-Info 'Installing via winget.'
winget install -e --id Neovide.Neovide --accept-package-agreements --accept-source-agreements
if ($LASTEXITCODE -ne 0) { throw "winget install exited with code $LASTEXITCODE" }

Write-Step 'Verifying'
Update-SessionPath
if (Get-Command neovide -ErrorAction SilentlyContinue) {
    Write-Info 'Neovide installed.'
}
else {
    winget list --id Neovide.Neovide --accept-source-agreements | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Neovide not found after install' }
    Write-Info 'Neovide installed (registered with winget; may need a new shell for PATH).'
}

Write-Step 'Done'
exit 0
