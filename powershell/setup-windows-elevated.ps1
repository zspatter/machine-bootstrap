<#
.SYNOPSIS
    The once-per-machine ELEVATED pass: everything the bootstrap needs
    admin for, consolidated here so every other script stays user-scope.
    Run once from an elevated shell; safe to re-run.

.NOTES
    What it does and why:
      - Windows sudo (inline): the deliberate alternative to Developer
                              Mode -- elevation stays explicit and
                              per-command (`sudo symlink-deploy dotfiles`)
                              instead of making symlinks globally
                              unprivileged. apt/brew muscle memory.
      - OpenSSH Client      : ssh / ssh-add / ssh-keygen (a Windows
                              optional capability, NOT installed by
                              default) -- setup-ssh-github depends on it.
      - ssh-agent service   : automatic startup, so keys load once.
      - NTFS long paths     : deep node_modules/nvim-data trees stop
                              hitting MAX_PATH.

    Deliberately NOT here: setup-wsl.ps1 stays separate because enabling
    the WSL feature can require a reboot, which this script must never
    trigger. Everything in the normal install-all chain stays user-scope
    by design -- this script is the single elevation touchpoint.

    Invocation note: `sudo <script>.ps1` fails with "not a valid Win32
    application" -- sudo execs binaries, not PowerShell scripts. Use:
        sudo pwsh -NoProfile -File <path-to-this-script>
    (or run it from an already-elevated shell).
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) {
    Write-Info 'This script needs an elevated shell (it exists so nothing else does).'
    exit 1
}

Write-Step 'Windows sudo (inline mode)'
# Deliberately NOT Developer Mode: that makes symlink creation globally
# unprivileged, a broader grant than wanted. sudo keeps elevation explicit
# and per-command -- `sudo symlink-deploy dotfiles` -- and inline mode runs
# it in the current window, apt-style.
if (-not (Get-Command sudo -ErrorAction SilentlyContinue)) {
    Write-Info 'No built-in sudo (needs Windows 11 24H2+); elevated tasks keep needing an admin shell.'
}
elseif ((sudo config 2>&1) -match 'Inline') {
    Write-Info 'Already in inline mode.'
}
else {
    sudo config --enable normal 2>&1 | Out-Null
    if ((sudo config 2>&1) -match 'Inline') {
        Write-Info 'Enabled inline mode.'
    }
    else {
        # CLI syntax has varied across builds; the registry value is stable.
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo' `
            -Name Enabled -Value 3 -Type DWord
        Write-Info 'Enabled inline mode (via registry).'
    }
}

Write-Step 'OpenSSH Client capability'
$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Client*' | Select-Object -First 1
if ($cap.State -eq 'Installed') {
    Write-Info "$($cap.Name) already installed."
}
else {
    Add-WindowsCapability -Online -Name $cap.Name | Out-Null
    Write-Info "Installed $($cap.Name)."
}

Write-Step 'ssh-agent service'
$svc = Get-Service ssh-agent -ErrorAction SilentlyContinue
if (-not $svc) {
    throw 'ssh-agent service not found even after the OpenSSH capability install.'
}
if ($svc.StartType -ne 'Automatic') { Set-Service ssh-agent -StartupType Automatic }
if ($svc.Status -ne 'Running') { Start-Service ssh-agent }
Write-Info 'ssh-agent running with automatic startup.'

Write-Step 'NTFS long paths'
$fsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
if ((Get-ItemProperty -Path $fsKey -Name LongPathsEnabled -ErrorAction SilentlyContinue).LongPathsEnabled -eq 1) {
    Write-Info 'Already enabled.'
}
else {
    Set-ItemProperty -Path $fsKey -Name LongPathsEnabled -Value 1 -Type DWord
    Write-Info 'Enabled.'
}

Write-Step 'Done'
Write-Info 'Re-run setup-ssh-github.ps1 (normal shell) to load your key into the agent.'
exit 0
