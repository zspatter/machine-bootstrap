<#
.SYNOPSIS
    Fresh-machine bootstrap: installs the Claude Desktop app via winget.

.NOTES
    Safe to re-run. GUI app -- presence is checked via the default install
    location and winget's registry.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

function Test-ClaudeDesktopInstalled {
    if (Test-Path "$env:LOCALAPPDATA\AnthropicClaude\claude.exe") { return $true }
    if (Test-Path "$env:LOCALAPPDATA\Programs\Claude\Claude.exe") { return $true }
    winget list --id Anthropic.Claude -e --accept-source-agreements 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

Write-Step 'Checking for Claude Desktop'
if (Test-ClaudeDesktopInstalled) {
    Write-Info 'Already installed.'
    Write-Info 'To update: winget upgrade Anthropic.Claude (or the app updates itself).'
    exit 0
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Info 'No winget available; install manually from https://claude.com/download, then re-run.'
    exit 1
}

Write-Info 'Installing via winget.'
winget install -e --id Anthropic.Claude --accept-package-agreements --accept-source-agreements
if ($LASTEXITCODE -ne 0) { throw "winget install exited with code $LASTEXITCODE" }

Write-Step 'Verifying'
if (Test-ClaudeDesktopInstalled) {
    Write-Info 'Claude Desktop installed.'
}
else {
    throw 'Claude Desktop not found after install'
}

Write-Step 'Done'
exit 0
