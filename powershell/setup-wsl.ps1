<#
.SYNOPSIS
    Fresh-machine bootstrap: enables WSL and installs an Ubuntu distro.
    Windows-only by nature -- no shell/ counterpart exists.

.NOTES
    Safe to re-run. Defaults to the distro name 'Ubuntu', which is
    Canonical's rolling "current LTS" alias -- pinning a specific version
    (e.g. Ubuntu-24.04) would go stale; pass -Distro to override.

    Deliberately NOT part of install-all.ps1: enabling the WSL feature on
    a machine that's never had it requires elevation and typically a
    REBOOT before a distro can run -- a reboot has no business appearing
    mid-way through an unattended install chain.

    First-run account creation (unix username/password) is interactive by
    design; this script installs with --no-launch and tells you to launch
    the distro once yourself.
#>

[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu'
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

function Get-InstalledDistros {
    # wsl.exe emits UTF-16; captured text arrives with interleaved nulls.
    $raw = wsl --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    @($raw) | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ }
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Step 'Checking WSL state'
wsl --status 2>&1 | Out-Null
$wslWorking = ($LASTEXITCODE -eq 0)

if ($wslWorking) {
    $installed = Get-InstalledDistros
    Write-Info "WSL is enabled. Installed distros: $(if ($installed) { $installed -join ', ' } else { '(none)' })"

    if ($installed -match [regex]::Escape($Distro)) {
        Write-Step "'$Distro' already installed"
        exit 0
    }

    Write-Step "Installing distro '$Distro'"
    # WSL feature already enabled: adding a distro needs no elevation and
    # no reboot.
    wsl --install --distribution $Distro --no-launch
    if ($LASTEXITCODE -ne 0) { throw "wsl --install exited with code $LASTEXITCODE" }
}
else {
    Write-Info 'WSL is not enabled on this machine.'
    if (-not (Test-IsAdmin)) {
        Write-Info 'Enabling the WSL feature requires an elevated (Administrator) session. Re-run this script as Administrator.'
        exit 1
    }

    Write-Step "Enabling WSL and installing '$Distro'"
    wsl --install --distribution $Distro --no-launch
    if ($LASTEXITCODE -ne 0) { throw "wsl --install exited with code $LASTEXITCODE" }
    Write-Info 'A REBOOT is typically required before the distro can start.'
}

Write-Step 'Done'
Write-Info "Launch it once to create your unix account: wsl -d $Distro"
Write-Info 'Then run the shell/ bootstrap scripts (or shell/install-all.sh) inside it.'
exit 0
