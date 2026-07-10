<#
.SYNOPSIS
    Fresh-machine bootstrap: installs Visual Studio Code via winget and
    syncs extensions from the dotfiles manifest.

.NOTES
    Safe to re-run.

    Extension sync is a fixed-path contract (like PES in
    setup-nvim-tooling): sym-lattice's symlink-manager links
    dotfiles/vscode/extensions.txt to ~/.vscode/extensions.txt, and
    anything listed there installs if missing. Never uninstalls --
    prune by hand. No file = no-op, so this script stays usable
    standalone.
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

Write-Step 'Checking for VS Code'
if (Get-Command code -ErrorAction SilentlyContinue) {
    Write-Info "Found $((code --version 2>$null | Select-Object -First 1)) at $((Get-Command code).Source)"
}
else {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Info 'No winget available; install manually from https://code.visualstudio.com, then re-run.'
        exit 1
    }
    Write-Info 'Installing via winget.'
    winget install -e --id Microsoft.VisualStudioCode --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget install exited with code $LASTEXITCODE" }
    Update-SessionPath

    Write-Step 'Verifying'
    if (Get-Command code -ErrorAction SilentlyContinue) {
        Write-Info "$((code --version 2>$null | Select-Object -First 1))"
    }
    else {
        Write-Info 'VS Code installed but not yet on PATH in this session. Open a new shell, then re-run for extension sync.'
    }
}

# --- Extension sync (see .NOTES) ---
$ExtFile = Join-Path $HOME '.vscode\extensions.txt'
if ((Get-Command code -ErrorAction SilentlyContinue) -and (Test-Path $ExtFile)) {
    Write-Step 'Syncing VS Code extensions'
    $installed = @(code --list-extensions 2>$null)
    $wanted = Get-Content $ExtFile | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' } |
        ForEach-Object { $_.Trim() }
    foreach ($ext in $wanted) {
        if ($installed -contains $ext) {
            Write-Info "$ext already installed"
        }
        else {
            Write-Info "Installing $ext"
            code --install-extension $ext | Out-Null
            if ($LASTEXITCODE -ne 0) { Write-Warning "code --install-extension $ext failed" }
        }
    }
}
elseif (-not (Test-Path $ExtFile)) {
    Write-Info "No $ExtFile -- extension sync skipped (symlink-manager deploys it from sym-lattice)."
}

Write-Step 'Done'
exit 0
