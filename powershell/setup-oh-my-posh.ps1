<#
.SYNOPSIS
    Fresh-machine bootstrap: installs oh-my-posh via winget. The prompt
    config lives in dotfiles (sym-lattice) and depends on this binary
    existing.

.NOTES
    Safe to re-run. Nerd Fonts (which themes generally want) are handled
    by setup-fonts.ps1.
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

Write-Step 'Checking for oh-my-posh'
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    Write-Info "Found oh-my-posh $(oh-my-posh version) at $((Get-Command oh-my-posh).Source)"
    Write-Info 'To update: oh-my-posh upgrade (or winget upgrade JanDeDobbeleer.OhMyPosh)'
    exit 0
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Info 'No winget available; install manually from https://ohmyposh.dev, then re-run.'
    exit 1
}

Write-Info 'Installing via winget.'
winget install -e --id JanDeDobbeleer.OhMyPosh --accept-package-agreements --accept-source-agreements
if ($LASTEXITCODE -ne 0) { throw "winget install exited with code $LASTEXITCODE" }
Update-SessionPath

Write-Step 'Verifying'
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    Write-Info "oh-my-posh $(oh-my-posh version)"
}
else {
    Write-Info 'oh-my-posh installed but not yet on PATH in this session. Open a new shell.'
}

Write-Step 'Done'
Write-Info 'Prompt config comes from your dotfiles; themes generally want a Nerd Font (out of scope here).'
exit 0
