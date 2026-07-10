<#
.SYNOPSIS
    Fresh-machine bootstrap: installs Neovide (GUI frontend for Neovim)
    via winget. The nvim config it renders lives in sym-lattice; Neovide
    embeds whatever nvim is on PATH, so setup-nvim.ps1 is the real
    prerequisite.

.NOTES
    Safe to re-run. GUI-specific settings (font, animations, scale) live
    in the nvim config gated on vim.g.neovide -- nothing to configure here.

    Context menu: Neovide's installer registers "Open with Neovide" for
    files (*\shell, %1) and folder BACKGROUNDS (Directory\Background,
    %V) but not for folders themselves -- right-clicking a directory
    got nothing (found 2026-07 while auditing the Zed menu work). The
    missing Directory\shell verb is registered below; opening a folder
    lands in nvim-tree via its directory hijack. Classic menu only
    ("Show more options" on Win11), same ceiling as every unpackaged
    Win32 app.
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
}
else {
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
}

# --- complete the installer's context-menu set (see .NOTES) ---
Write-Step 'Registering folder "Open with Neovide"'
$NeovideExe = (Get-Command neovide -ErrorAction SilentlyContinue).Source
if (-not $NeovideExe) { $NeovideExe = Join-Path $env:ProgramFiles 'Neovide\neovide.exe' }
if (-not (Test-Path $NeovideExe)) {
    Write-Info "neovide.exe not found; skipping context menu."
}
else {
    # Same split as setup-zed.ps1: reg.exe for keys/plain values,
    # provider for the command value (its embedded quotes get eaten by
    # Windows PowerShell's legacy native-arg quoting). Quoted properly,
    # unlike the installer's own unquoted space-containing commands.
    $Key = 'HKCU\Software\Classes\Directory\shell\Neovide'
    reg add $Key /ve /d 'Open with Neovide' /f | Out-Null
    reg add $Key /v Icon /d "$NeovideExe" /f | Out-Null
    reg add "$Key\command" /f | Out-Null
    Set-ItemProperty -LiteralPath "HKCU:\$($Key.Substring(5))\command" -Name '(Default)' `
        -Value "`"$NeovideExe`" `"%V`""
    Write-Info 'Folders now open in Neovide (files and folder backgrounds were already covered by the installer).'
}

Write-Step 'Done'
exit 0
