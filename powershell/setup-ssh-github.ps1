<#
.SYNOPSIS
    Fresh-machine bootstrap: generates an ed25519 SSH key (if absent),
    wires the Windows OpenSSH agent, and registers the public key with
    GitHub via the gh CLI when it's authenticated.

.NOTES
    Safe to re-run: existing keys are never touched, and the GitHub
    upload is skipped when the key is already registered.

    The key is generated WITHOUT a passphrase -- the deliberate trade for
    unattended bootstrap. Regenerate with one (ssh-keygen -p -f <key>)
    if this machine's threat model wants it; the agent wiring below makes
    a passphrase cheap to live with.

    Prerequisite: the Windows OpenSSH Client capability (ssh, ssh-add,
    ssh-keygen -- NOT installed by default) and the ssh-agent service,
    both of which setup-windows-elevated.ps1 handles in the single
    elevated pass. This script itself never needs elevation.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
    # 32-bit pwsh on 64-bit Windows: WOW64 redirects System32 to SysWOW64,
    # which has no OpenSSH -- the capability can be fully installed yet
    # invisible to this process (hit live: the machine's only pwsh was the
    # x86 build). Sysnative is the redirection escape hatch for detection.
    if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem -and
        (Test-Path "$env:windir\Sysnative\OpenSSH\ssh-keygen.exe")) {
        Write-Info 'OpenSSH IS installed, but this is 32-bit PowerShell on 64-bit Windows --'
        Write-Info 'System32 redirection hides it. Fix the shell, not ssh: from a CMD window,'
        Write-Info '  winget uninstall "PowerShell 7-x86"'
        Write-Info '  winget install -e --id Microsoft.PowerShell --architecture x64'
        Write-Info '(x86/x64 share an MSI upgrade identity, so uninstall must come first.)'
        exit 1
    }
    Write-Info 'Windows OpenSSH Client is not installed (ssh/ssh-keygen/ssh-add missing).'
    Write-Info 'Run the elevated pass once, then re-run this:'
    Write-Info "  sudo pwsh -NoProfile -File $PSScriptRoot\setup-windows-elevated.ps1"
    exit 1
}

$KeyPath = Join-Path $HOME '.ssh\id_ed25519'
$PubPath = "$KeyPath.pub"

Write-Step 'SSH key'
if (Test-Path $KeyPath) {
    Write-Info "Key already exists at $KeyPath -- leaving it alone."
}
else {
    New-Item -ItemType Directory -Force -Path (Split-Path $KeyPath) | Out-Null
    # -N "" (a genuinely empty arg -- pwsh 7 passes it correctly). The
    # often-cited -N '""' workaround is for Windows PowerShell 5.1 and
    # produces a key whose passphrase is literally two quote characters
    # here -- which made ssh-add prompt forever and hung a CI runner.
    ssh-keygen -t ed25519 -f $KeyPath -N "" -C "$env:USERNAME@$env:COMPUTERNAME" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "ssh-keygen exited with code $LASTEXITCODE" }
    Write-Info "Generated $KeyPath (no passphrase -- see script notes)."
}

Write-Step 'ssh-agent'
$svc = Get-Service ssh-agent -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    ssh-add $KeyPath 2>$null | Out-Null
    Write-Info 'Key loaded into the running agent.'
}
else {
    Write-Info 'ssh-agent service is not running -- ssh still works, it just'
    Write-Info 'reads the key per-connection. Wire the service permanently with:'
    Write-Info "  sudo pwsh -NoProfile -File $PSScriptRoot\setup-windows-elevated.ps1"
}

Write-Step 'GitHub registration'
$pubKey = (Get-Content $PubPath -Raw).Trim()
$keyBody = ($pubKey -split ' ')[1]
$ghReady = $false
if (Get-Command gh -ErrorAction SilentlyContinue) {
    gh auth status 2>&1 | Out-Null
    $ghReady = ($LASTEXITCODE -eq 0)
}
if ($ghReady) {
    $existing = gh ssh-key list 2>$null | Out-String
    if ($existing -match [regex]::Escape($keyBody)) {
        Write-Info 'Key already registered with GitHub.'
    }
    else {
        gh ssh-key add $PubPath --title $env:COMPUTERNAME
        if ($LASTEXITCODE -ne 0) { throw "gh ssh-key add exited with code $LASTEXITCODE" }
        Write-Info "Registered with GitHub as '$env:COMPUTERNAME'."
    }
}
else {
    Write-Info 'gh CLI missing or unauthenticated; add the key manually:'
    Write-Info "  $pubKey"
    Write-Info 'https://github.com/settings/ssh/new (or run setup-gh-cli.ps1 + gh auth login, then re-run).'
}

Write-Step 'Done'
Write-Info 'Test with: ssh -T git@github.com'
exit 0
