<#
.SYNOPSIS
    Fresh-machine bootstrap: installs the Zed editor via winget and wires
    the "Open with Zed" explorer context menu the installer forgets.

.NOTES
    Safe to re-run. Zed manages its own updates in-app; winget upgrade
    (or update-all.ps1) also works.

    PATH: the installer adds %LOCALAPPDATA%\Programs\Zed\bin (zed CLI)
    to the user PATH itself -- nothing to do here.

    Context menu: the installer registers a ZedContextMenu class (title
    only) but wires no shell verbs to it, so fresh installs get no
    right-click entry (zed-industries/zed#46223). The classic HKCU shell
    verbs are registered below instead -- files, folders, and folder
    backgrounds. On Win11 they appear under "Show more options" (the
    modern top-level menu needs an MSIX-packaged IExplorerCommand;
    not worth the machinery). Settings/keymap live in the sym-lattice
    dotfiles and symlink to ~/AppData/Roaming/Zed via symlink-manager.
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
}
else {
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
}

# --- "Open with Zed" context menu (see .NOTES) ---
Write-Step 'Registering "Open with Zed" context menu'
$ZedExe = Join-Path $env:LOCALAPPDATA 'Programs\Zed\Zed.exe'
if (-not (Test-Path $ZedExe)) {
    Write-Info "Zed.exe not at $ZedExe (non-default install?); skipping context menu."
}
else {
    # Key creation + simple values via reg.exe (the file-class key is
    # literally named '*', which PowerShell provider *paths* treat as a
    # wildcard; reg.exe takes it literally, and /f makes every line an
    # idempotent overwrite). The command values go through the provider
    # with -LiteralPath instead: they need embedded quotes, and quotes
    # passed to reg.exe get eaten under Windows PowerShell's legacy
    # native-argument quoting (hit live -- the value landed unquoted,
    # a latent break for any install path with a space in it).
    # %1 = clicked file/folder; %V = the folder for background clicks.
    $entries = @(
        @{ Key = 'HKCU\Software\Classes\*\shell\Zed';                    Arg = '%1' }
        @{ Key = 'HKCU\Software\Classes\Directory\shell\Zed';            Arg = '%V' }
        @{ Key = 'HKCU\Software\Classes\Directory\Background\shell\Zed'; Arg = '%V' }
    )
    foreach ($e in $entries) {
        reg add $e.Key /ve /d 'Open with Zed' /f | Out-Null
        reg add $e.Key /v Icon /d "$ZedExe" /f | Out-Null
        reg add "$($e.Key)\command" /f | Out-Null
        Set-ItemProperty -LiteralPath "HKCU:\$($e.Key.Substring(5))\command" -Name '(Default)' `
            -Value "`"$ZedExe`" `"$($e.Arg)`""
    }
    Write-Info 'Registered for files, folders, and folder backgrounds (classic menu / "Show more options").'
    Write-Info 'Remove with: reg delete "HKCU\Software\Classes\*\shell\Zed" /f (and the two Directory variants).'
}

Write-Step 'Done'
exit 0
