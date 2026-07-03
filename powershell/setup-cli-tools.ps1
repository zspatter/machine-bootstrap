<#
.SYNOPSIS
    Fresh-machine bootstrap: installs a curated bundle of small,
    zero-config CLI tools via winget -- currently jq, ripgrep, fd, fzf,
    bat, zoxide. Adding a tool later = adding one entry to the table below.

.NOTES
    Safe to re-run.
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

# command name -> winget package id
$Tools = [ordered]@{
    'jq'     = 'jqlang.jq'
    'rg'     = 'BurntSushi.ripgrep.MSVC'
    'fd'     = 'sharkdp.fd'
    'fzf'    = 'junegunn.fzf'
    'bat'    = 'sharkdp.bat'
    'zoxide' = 'ajeetdsouza.zoxide'
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Info 'No winget available; install the tools manually, then re-run.'
    exit 1
}

Write-Step 'Installing CLI tools bundle'
foreach ($cmd in $Tools.Keys) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Write-Info "$cmd already installed"
        continue
    }
    Write-Info "Installing $($Tools[$cmd])"
    winget install -e --id $Tools[$cmd] --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget install $($Tools[$cmd]) exited with code $LASTEXITCODE" }
}
Update-SessionPath

Write-Step 'Verifying'
$missing = @()
foreach ($cmd in $Tools.Keys) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Write-Info "${cmd}: $((& $cmd --version 2>&1 | Select-Object -First 1))"
    }
    else {
        Write-Info "${cmd}: not on PATH yet (may need a new shell)"
        $missing += $cmd
    }
}
if ($missing.Count -gt 0) {
    Write-Info "Not resolvable in this session: $($missing -join ', '). Open a new shell and verify."
}

Write-Step 'Done'
exit 0
