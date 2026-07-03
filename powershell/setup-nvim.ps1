<#
.SYNOPSIS
    Fresh-machine bootstrap: installs Neovim via winget. Config is NOT
    this script's job -- dotfiles handle that.

.NOTES
    Safe to re-run. winget keeps Neovim current on Windows (unlike Debian
    stable's apt, which is why the Linux script uses the official tarball
    instead of a package manager).
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

# A fresh shell (or a fresh CI step) may predate PATH changes from installs
# earlier in the same session -- refresh from the registry before the
# presence checks, or already-installed tools look missing and get
# reinstalled (winget then exits 0x8A15002B "no applicable upgrade",
# failing the run). Caught by the install-all re-run smoke test in CI.
Update-SessionPath

Write-Step 'Checking for nvim'
if (Get-Command nvim -ErrorAction SilentlyContinue) {
    Write-Info "Found $((nvim --version | Select-Object -First 1)) at $((Get-Command nvim).Source)"
    Write-Info 'To update: winget upgrade Neovim.Neovim'
    exit 0
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Info 'No winget available; install Neovim manually from https://neovim.io, then re-run.'
    exit 1
}

Write-Info 'Installing via winget.'
winget install -e --id Neovim.Neovim --accept-package-agreements --accept-source-agreements
if ($LASTEXITCODE -ne 0) { throw "winget install exited with code $LASTEXITCODE" }
Update-SessionPath

Write-Step 'Verifying'
if (Get-Command nvim -ErrorAction SilentlyContinue) {
    Write-Info "$((nvim --version | Select-Object -First 1))"
}
else {
    Write-Info 'nvim installed but not yet on PATH in this session. Open a new shell.'
}

Write-Step 'Done'
Write-Info 'Config is handled by your dotfiles (sym-lattice), not here.'
exit 0
