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

    Enabling the ssh-agent service needs elevation once; without it the
    key still works (ssh prompts per-use), so this script degrades
    rather than failing.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

$KeyPath = Join-Path $HOME '.ssh\id_ed25519'
$PubPath = "$KeyPath.pub"

Write-Step 'SSH key'
if (Test-Path $KeyPath) {
    Write-Info "Key already exists at $KeyPath -- leaving it alone."
}
else {
    New-Item -ItemType Directory -Force -Path (Split-Path $KeyPath) | Out-Null
    ssh-keygen -t ed25519 -f $KeyPath -N '""' -C "$env:USERNAME@$env:COMPUTERNAME" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "ssh-keygen exited with code $LASTEXITCODE" }
    Write-Info "Generated $KeyPath (no passphrase -- see script notes)."
}

Write-Step 'ssh-agent service'
$svc = Get-Service ssh-agent -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Info 'No ssh-agent service (OpenSSH client feature missing?); skipping agent wiring.'
}
elseif ($svc.Status -eq 'Running') {
    Write-Info 'ssh-agent already running.'
    ssh-add $KeyPath 2>$null | Out-Null
}
else {
    $elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($elevated) {
        Set-Service ssh-agent -StartupType Automatic
        Start-Service ssh-agent
        ssh-add $KeyPath 2>$null | Out-Null
        Write-Info 'ssh-agent enabled (automatic startup) and key added.'
    }
    else {
        Write-Info 'ssh-agent service is disabled and this shell is not elevated.'
        Write-Info 'Run once elevated: Set-Service ssh-agent -StartupType Automatic; Start-Service ssh-agent'
    }
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
