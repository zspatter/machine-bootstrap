<#
.SYNOPSIS
    Fresh-machine bootstrap: installs Claude Code (the CLI) via the
    official native installer -- the documented recommended path, and
    unlike winget it auto-updates in the background.

.NOTES
    Safe to re-run. Auth is interactive (`claude` then browser login) --
    same boundary as setup-gh-cli: install-only, no credential automation.
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

Write-Step 'Installing / locating Claude Code'
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Info "claude already installed: $((claude --version 2>&1 | Select-Object -First 1)) at $((Get-Command claude).Source)"
    Write-Info 'If winget-installed: winget upgrade Anthropic.ClaudeCode. Native installs auto-update.'
    exit 0
}

# Official installer, saved to a file first rather than piped straight
# into iex -- same hygiene as the uv installer. Run via powershell
# -ExecutionPolicy Bypass so a restrictive policy can't block it.
$tmp = Join-Path $env:TEMP 'claude-install.ps1'
Invoke-WebRequest -UseBasicParsing -MaximumRetryCount 3 -RetryIntervalSec 2 -Uri 'https://claude.ai/install.ps1' -OutFile $tmp
powershell -NoProfile -ExecutionPolicy Bypass -File $tmp
$installerExit = $LASTEXITCODE
Remove-Item $tmp -ErrorAction SilentlyContinue
if ($installerExit -ne 0) { throw "Claude Code installer exited with code $installerExit" }

Update-SessionPath
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    $env:Path = "$HOME\.local\bin;$env:Path"
}

Write-Step 'Verifying'
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Info "$((claude --version 2>&1 | Select-Object -First 1))"
}
else {
    Write-Info 'claude installed but not yet on PATH in this session. Open a new shell.'
}

Write-Step 'Done'
Write-Info 'Run `claude` in a project to authenticate (interactive browser login).'
exit 0
