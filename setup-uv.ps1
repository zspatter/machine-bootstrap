<#
.SYNOPSIS
    Fresh-machine bootstrap: installs uv (Astral's Python toolchain
    manager) and a current default Python. Not project-specific.

.NOTES
    Safe to re-run. Per-user by design -- no -Scope concept, unlike the
    retired pyenv scripts: uv is a single static binary in ~\.local\bin
    with managed Pythons under its own data dir, and Python installs are
    prebuilt downloads that take seconds. "Run this once per account"
    replaces the old shared-root + ACL-lockdown machinery outright.

    Per-project pins (.python-version / pyproject.toml) are handled
    per-repo; uv auto-downloads whatever a project pins on first `uv run`.
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

function Ensure-Uv {
    Write-Step 'Installing / locating uv'
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        Write-Info "uv already installed: $(uv --version) at $((Get-Command uv).Source)"
        Write-Info 'To update it later: uv self update (standalone installs only).'
        return
    }

    # Official standalone installer, saved to a file first rather than
    # piped straight into iex -- same trust either way, but this is
    # inspection-friendly and immune to executing a truncated stream. Run
    # via powershell.exe -ExecutionPolicy Bypass so a restrictive local
    # policy can't block the downloaded file.
    $tmp = Join-Path $env:TEMP 'uv-install.ps1'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://astral.sh/uv/install.ps1' -OutFile $tmp
    powershell -NoProfile -ExecutionPolicy Bypass -File $tmp
    $installerExit = $LASTEXITCODE
    Remove-Item $tmp -ErrorAction SilentlyContinue
    if ($installerExit -ne 0) { throw "uv installer exited with code $installerExit" }

    # The installer writes ~\.local\bin onto the User PATH for future
    # shells; this process needs it now.
    Update-SessionPath
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        $env:Path = "$HOME\.local\bin;$env:Path"
    }
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        throw 'uv install did not land on PATH. Open a new shell and re-run.'
    }
}

function Install-DefaultPython {
    Write-Step 'Installing latest Python (uv-managed, prebuilt)'
    # Runs from $HOME with --no-project, deliberately: uv respects
    # .python-version pins in the current directory, so running this from
    # inside a project would install the project's pin as the machine-wide
    # default instead of latest. Caught on the first real machine run, not
    # by CI, whose checkouts have no pin to trip on.
    Push-Location $HOME
    try {
        # --default also exposes bare python/python3 executables, filling
        # the old `pyenv global` niche. The flag is still marked
        # experimental upstream, so fall back to a plain managed install
        # rather than failing the whole bootstrap if it disappears or
        # changes; uv-managed flows (uv run, uv venv, uvx) are identical
        # either way.
        uv python install --default
        if ($LASTEXITCODE -ne 0) {
            Write-Info 'Experimental --default flag failed; retrying without bare python/python3 shims.'
            uv python install
        }
        if ($LASTEXITCODE -ne 0) {
            # Known uv-on-Windows quirk: the minor-version-link step can
            # report "Missing expected target directory" and exit 2 while
            # the interpreter itself lands fine and is fully usable --
            # astral-sh/uv#19622 tracks the non-self-healing link logic.
            # Observed live on a hardened Windows 11 machine even into a
            # brand-new install dir. Trust a functional check over the
            # exit code before failing the whole bootstrap.
            uv run --no-project python --version
            if ($LASTEXITCODE -ne 0) { throw 'uv python install failed and no functional managed Python found' }
            Write-Info 'uv python install reported an error, but a managed Python is installed and functional -- continuing (see astral-sh/uv#19622).'
        }

        Write-Info "uv: $(uv --version)"
        Write-Info "default python: $(uv run --no-project python --version 2>&1)"
    }
    finally { Pop-Location }
}

# --- main ---

Ensure-Uv
Install-DefaultPython

Write-Step 'Done'
Write-Info 'Open a new shell to pick up PATH.'
Write-Info 'Per-project: `uv run <cmd>` with a .python-version/pyproject pin -- uv auto-downloads pinned versions on demand.'
Write-Info 'To update later: `uv self update` and `uv python upgrade`.'

# Explicit and unconditional: reaching this point means success, regardless
# of what $LASTEXITCODE holds from the last native command (lesson learned
# in setup-gh-cli.ps1 -- pwsh otherwise inherits a stale native exit code
# as the script's own).
exit 0
