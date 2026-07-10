<#
.SYNOPSIS
    Fresh-machine bootstrap: installs the Zed editor via winget and
    verifies its "Open with Zed" context-menu package registered.

.NOTES
    Safe to re-run. Zed manages its own updates in-app; winget upgrade
    (or update-all.ps1) also works.

    PATH: the installer adds %LOCALAPPDATA%\Programs\Zed\bin (zed CLI)
    to the user PATH itself -- nothing to do here.

    Context menu -- correction for the record (2026-07): an earlier
    revision registered classic HKCU shell verbs here, diagnosing the
    menu as "forgotten by the installer" because no *\shell keys
    existed and the ZedContextMenu class had no verbs wired to it.
    Wrong place to look: Zed registers a SPARSE MSIX PACKAGE
    (ZedIndustries.Zed, IExplorerCommand) whose manifest covers files
    (*), Directory, and Directory\Background -- top-level in the Win11
    modern menu AND rendered in the classic one; the ZedContextMenu
    class is just its title payload. The hand-registered verbs doubled
    every classic-menu entry once the packaged one showed up (hit
    live), so this script now removes them where a previous run left
    them and merely verifies the package instead (its registration can
    genuinely flake -- zed-industries/zed#46223). Settings/keymap live
    in the sym-lattice dotfiles and symlink to ~/AppData/Roaming/Zed
    via symlink-manager.
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

# --- context menu: Zed's own sparse package owns it (see .NOTES) ---
Write-Step 'Checking the "Open with Zed" context menu'

# Self-heal: drop the classic verbs a previous revision of this script
# registered -- they double the packaged entry in the classic menu.
# reg delete is a no-op grumble when the key is already gone.
foreach ($key in @(
        'HKCU\Software\Classes\*\shell\Zed',
        'HKCU\Software\Classes\Directory\shell\Zed',
        'HKCU\Software\Classes\Directory\Background\shell\Zed'
    )) {
    reg delete $key /f 2>$null | Out-Null
}

if (Get-AppxPackage -Name ZedIndustries.Zed -ErrorAction SilentlyContinue) {
    Write-Info 'Sparse package registered: files, folders, and backgrounds -- top-level on Win11.'
}
else {
    Write-Info 'Sparse package NOT registered -- the context menu will be missing (zed#46223).'
    Write-Info 'Reinstall (winget install -e --id ZedIndustries.Zed) or restart Explorer, then re-check.'
}

Write-Step 'Done'
exit 0
