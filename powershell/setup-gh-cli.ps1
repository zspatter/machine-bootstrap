<#
.SYNOPSIS
    Fresh-machine bootstrap: installs the GitHub CLI (gh) via winget. Not
    project-specific.

.NOTES
    Safe to re-run. Deliberately install-only, not auth-only: `gh auth
    login` is an interactive OAuth device-code / browser flow (or needs a
    pre-existing token via $env:GH_TOKEN) -- there's no way to complete it
    unattended without either hanging a non-interactive run or taking on
    secret-handling this script has no business doing. This installs the
    binary and tells you to run `gh auth login` yourself, once.
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

function Install-GhCli {
    Write-Step 'Checking for gh'
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        Write-Info "Found $(gh --version | Select-Object -First 1)"
        return
    }

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Info 'No gh on PATH; installing via winget.'
        winget install -e --id GitHub.cli --accept-package-agreements --accept-source-agreements
        Update-SessionPath
    }
    else {
        Write-Info 'No gh on PATH and no winget available; install it manually from https://cli.github.com, then re-run.'
        return
    }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Info 'gh installed but not yet on PATH in this session. Open a new shell if you need it immediately.'
    }
}

function Show-AuthStatus {
    Write-Step 'Checking auth status'
    gh auth status 2>&1 | Out-Null
    # A non-zero exit here (not logged in) is an expected, non-fatal
    # outcome for this script. A prior attempt tried to capture then reset
    # $LASTEXITCODE here, but that reset didn't actually reach the real
    # automatic variable -- plain assignment inside a function scope
    # shadows it locally instead. Left as an explicit `exit 0` at the very
    # end of the script instead (see main), which sidesteps the ambiguity
    # entirely regardless of what $LASTEXITCODE ends up holding.
    if ($LASTEXITCODE -eq 0) {
        Write-Info 'Already authenticated.'
    }
    else {
        Write-Info "Not authenticated. Run 'gh auth login' to authenticate -- this needs your interactive input (browser or token), not something a bootstrap script can do for you."
    }
}

# --- main ---

Install-GhCli
if (Get-Command gh -ErrorAction SilentlyContinue) {
    Write-Info "gh version: $(gh --version | Select-Object -First 1)"
    Show-AuthStatus
}

Write-Step 'Done'

# Explicit, unconditional: this script only ever throws for a real
# failure (see Install-GhCli); reaching this point always means success,
# regardless of what $LASTEXITCODE holds from the last native command
# (e.g. `gh auth status` legitimately returning non-zero when not logged
# in). Without this, PowerShell inherits that stale exit code as the
# script's own process exit code even though nothing actually failed.
exit 0
