<#
.SYNOPSIS
    Fresh-machine bootstrap: installs pyenv-win and sets a global
    latest-release Python. Not project-specific — no per-repo
    .python-version handling here.

.NOTES
    Safe to re-run. No manual Python install required — falls back to a
    direct python.org download if winget isn't available.

    Supports -Scope System (shared, C:\ProgramData\pyenv, needs an
    elevated/Administrator session) and -Scope User (default, $HOME\.pyenv).
    Auto-detected from the current session's elevation when omitted.

    No direnv here by design: direnv's automatic per-directory venv
    activation (`layout pyenv`) hardcodes a POSIX `bin/` venv layout and
    evaluates .envrc via bash — it doesn't work with Windows venvs, which
    use `Scripts\`. pyenv-win already reads .python-version per-directory
    on its own (no direnv needed for that part); venv activation on Windows
    stays manual via `.venv\Scripts\Activate.ps1` regardless. direnv adds
    no value in this scope on native Windows. See setup-python-env.sh for
    the WSL/Linux/macOS side, where direnv's layout_pyenv works correctly.
#>

[CmdletBinding()]
param(
    # Allow pinning instead of "latest" if ever needed.
    [string]$PythonVersion,
    [switch]$IncludeFreeThreaded,
    [ValidateSet('Auto', 'System', 'User')]
    [string]$Scope = 'Auto'
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$script:IsAdmin = Test-IsAdmin
$script:ResolvedScope = if ($Scope -eq 'Auto') { if ($script:IsAdmin) { 'System' } else { 'User' } } else { $Scope }

if ($script:ResolvedScope -eq 'System' -and -not $script:IsAdmin) {
    throw '-Scope System requires an elevated (Administrator) PowerShell session. Re-run as Administrator, or omit -Scope to auto-detect.'
}

# Shared root for -Scope System, analogous to /opt/pyenv on the Unix side.
$script:SystemShareRoot = 'C:\ProgramData\pyenv'

function Update-SessionPath {
    # Pull the freshly-written User/Machine PATH into this process without
    # needing a new shell.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = @($machine, $user) -join ';'
}

function Add-EnvPathEntry {
    param(
        [Parameter(Mandatory)][string]$Entry,
        [Parameter(Mandatory)][ValidateSet('Machine', 'User')][string]$Scope
    )

    $current = [Environment]::GetEnvironmentVariable('Path', $Scope)
    $parts = @()
    if ($current) { $parts = $current -split ';' | Where-Object { $_ -ne '' } }

    if ($parts -contains $Entry) { return }

    # Prepend so pyenv shims win over any bootstrap Python already on PATH.
    # SetEnvironmentVariable(..., $Scope) is used deliberately instead of
    # `setx`, which silently truncates PATH past 1024 chars and can nuke
    # existing entries.
    $newPath = (@($Entry) + $parts) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newPath, $Scope)
}

function Read-XmlFileWithRetry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$MaxAttempts = 5,
        [int]$DelayMs = 500
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return [xml](Get-Content $Path -Raw -ErrorAction Stop)
        }
        catch {
            if ($attempt -eq $MaxAttempts) {
                # A file just written/ACL'd under -Scope System can be
                # transiently locked (e.g. AV real-time scanning) right
                # after being touched. Surface the actual ACL state here so
                # a genuine permission bug is distinguishable from that.
                Write-Info "Get-Content failed after $MaxAttempts attempts on $Path. Diagnostics:"
                icacls $Path 2>&1 | ForEach-Object { Write-Info "  $_" }
                throw
            }
            Start-Sleep -Milliseconds $DelayMs
        }
    }
}

function Set-SharedReadExecuteAcl {
    param([Parameter(Mandatory)][string]$Path)

    # Mirrors `chmod -R a+rX,go-w` in setup-python-env.sh: the shared root
    # stays Administrators/SYSTEM-writable only, so an unelevated session
    # can't `pyenv install` / `pyenv global`. Everyday accounts get Read &
    # Execute so they can use whatever's already installed.
    #
    # /inheritance:r + /grant:r (not plain /grant) is deliberate: a plain
    # /grant is purely additive and would leave any pre-existing, more
    # permissive inherited ACE (e.g. from C:\ProgramData's own defaults)
    # in place, silently defeating the lockdown. This was caught for real
    # on the Unix side in CI with the chmod equivalent -- `a+rX` alone let
    # a non-admin account still write, because it never strips anything.
    # Applying the same authoritative-replace fix here on principle, since
    # there's no equivalent multi-account CI check to prove it empirically
    # on Windows yet. Uses well-known SIDs so this is locale-independent.
    #
    # Two separate icacls calls, not one combined /inheritance:r + multiple
    # /grant:r + /T: combining them in one invocation was tried first and
    # produced files with a genuinely empty DACL (confirmed via `icacls`
    # diagnostics in CI -- zero ACEs, not a transient lock) on at least one
    # recursively-touched child, meaning /T didn't reliably propagate the
    # grants for that combination. Splitting into "strip inheritance
    # recursively" then "grant recursively" as two well-established simple
    # operations avoids relying on that combination working.
    icacls $Path /inheritance:r /T /Q
    if ($LASTEXITCODE -ne 0) { throw "icacls /inheritance:r failed on $Path (exit $LASTEXITCODE)" }

    icacls $Path /grant:r '*S-1-5-18:(OI)(CI)F' `
        /grant:r '*S-1-5-32-544:(OI)(CI)F' `
        /grant:r '*S-1-5-32-545:(OI)(CI)RX' `
        /T /Q
    if ($LASTEXITCODE -ne 0) { throw "icacls /grant:r failed on $Path (exit $LASTEXITCODE)" }
}

function Get-LatestPythonOrgInstaller {
    # winget-less fallback only: find the newest release with an amd64
    # installer directly on python.org, same directory listing technique as
    # Repair-PyenvVersionCache.
    $listing = Invoke-WebRequest -UseBasicParsing -Uri 'https://www.python.org/ftp/python/'
    $versions = $listing.Links.href |
        Where-Object { $_ -match '^(\d+\.\d+\.\d+)/$' } |
        ForEach-Object { $Matches[1] } |
        Sort-Object { [version]$_ } -Descending

    foreach ($version in $versions) {
        $page = "https://www.python.org/ftp/python/$version/"
        $exeName = "python-$version-amd64.exe"
        try {
            $pageContent = Invoke-WebRequest -UseBasicParsing -Uri $page
        }
        catch { continue }

        if ($pageContent.Links.href -contains $exeName) {
            return [pscustomobject]@{ Version = $version; Url = "$page$exeName" }
        }
    }

    throw 'Could not find a python.org amd64 installer to bootstrap with.'
}

function Ensure-BootstrapPython {
    # Always per-user/throwaway regardless of -Scope: this copy only
    # exists to provide a pip for the one-off `pip install pyenv-win`
    # below, and is never used again after that.
    Write-Step 'Checking for a bootstrap Python'
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Info "Found $(python --version 2>&1) at $($cmd.Source)"
        return
    }

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Info 'No Python on PATH; installing a bootstrap copy via winget.'
        winget install -e --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements
    }
    else {
        Write-Info 'No Python on PATH and no winget available; downloading the official installer from python.org instead.'
        $installer = Get-LatestPythonOrgInstaller
        $installerPath = Join-Path $env:TEMP "python-$($installer.Version)-amd64.exe"
        Write-Info "Downloading Python $($installer.Version)"
        Invoke-WebRequest -UseBasicParsing -Uri $installer.Url -OutFile $installerPath

        Write-Info 'Running installer silently (per-user, no admin required).'
        # InstallAllUsers=0 avoids needing elevation; PrependPath=1 puts it
        # on User PATH so Update-SessionPath below can pick it up.
        $proc = Start-Process -FilePath $installerPath `
            -ArgumentList '/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_test=0' `
            -Wait -PassThru
        Remove-Item $installerPath -ErrorAction SilentlyContinue

        if ($proc.ExitCode -ne 0) {
            throw "python.org installer exited with code $($proc.ExitCode)"
        }
    }

    Update-SessionPath
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        throw 'Bootstrap Python install did not land on PATH. Open a new shell and re-run.'
    }
}

function Get-PyenvRoot {
    if ($script:ResolvedScope -eq 'System') { return Join-Path $script:SystemShareRoot 'pyenv-win' }
    return Join-Path $HOME '.pyenv\pyenv-win'
}

function Get-PipTargetRoot {
    # Parent dir passed to `pip install --target`; pip creates the
    # `pyenv-win` subfolder itself from the package contents.
    if ($script:ResolvedScope -eq 'System') { return $script:SystemShareRoot }
    return "$HOME\.pyenv"
}

function Ensure-PyenvWin {
    $pyenvRoot = Get-PyenvRoot
    $envScope = if ($script:ResolvedScope -eq 'System') { 'Machine' } else { 'User' }
    Write-Step "Installing / locating pyenv-win ($script:ResolvedScope scope: $pyenvRoot)"

    if (-not (Test-Path (Join-Path $pyenvRoot 'bin\pyenv.bat'))) {
        Write-Info 'Installing pyenv-win via pip --target'
        # --no-user is required: pip's default --user mode conflicts with
        # --target and errors out.
        python -m pip install pyenv-win --target (Get-PipTargetRoot) --no-user
    }
    else {
        Write-Info "pyenv-win already present at $pyenvRoot"
    }

    [Environment]::SetEnvironmentVariable('PYENV', $pyenvRoot, $envScope)
    [Environment]::SetEnvironmentVariable('PYENV_ROOT', $pyenvRoot, $envScope)
    [Environment]::SetEnvironmentVariable('PYENV_HOME', $pyenvRoot, $envScope)
    Add-EnvPathEntry -Entry (Join-Path $pyenvRoot 'bin') -Scope $envScope
    Add-EnvPathEntry -Entry (Join-Path $pyenvRoot 'shims') -Scope $envScope

    $env:PYENV = $pyenvRoot
    $env:PYENV_ROOT = $pyenvRoot
    $env:PYENV_HOME = $pyenvRoot
    Update-SessionPath

    if ($script:ResolvedScope -eq 'System') {
        Set-SharedReadExecuteAcl -Path $script:SystemShareRoot
    }
}

function Repair-PyenvVersionCache {
    # pyenv-update.vbs (and the bundled version list) calls
    # CreateObject("htmlfile") to scrape python.org. On hardened Windows 11
    # builds, Windows Script Host blocks that COM object as an anti-malware
    # measure — confirmed this is a WSH policy block, not a missing
    # registration (an elevated `regsvr32 mshtml.dll` does not fix it).
    # Upstream fixes (pyenv-win/pyenv-win#724, #729) aren't merged yet.
    #
    # Workaround: fetch the live version list from python.org directly
    # (bypasses the broken COM dependency) and merge any missing entries
    # into .versions_cache.xml ourselves. Always run this rather than
    # trying to detect the broken state — it's idempotent and fixes both
    # the broken and working case the same way.
    Write-Step 'Refreshing pyenv-win version cache from python.org'

    $pyenvRoot = Get-PyenvRoot
    $cachePath = Join-Path $pyenvRoot '.versions_cache.xml'
    if (-not (Test-Path $cachePath)) {
        Write-Info "No .versions_cache.xml found at $cachePath; skipping cache repair."
        return
    }

    $cache = Read-XmlFileWithRetry -Path $cachePath
    $existing = @{}
    foreach ($v in $cache.versions.version) { $existing[$v.code] = $true }

    $listing = Invoke-WebRequest -UseBasicParsing -Uri 'https://www.python.org/ftp/python/'
    $dirVersions = $listing.Links.href |
        Where-Object { $_ -match '^(\d+\.\d+\.\d+)/$' } |
        ForEach-Object { $Matches[1] } |
        Sort-Object -Unique

    $added = 0
    foreach ($version in $dirVersions) {
        if ($existing.ContainsKey($version)) { continue }

        $installerPage = "https://www.python.org/ftp/python/$version/"
        try {
            $page = Invoke-WebRequest -UseBasicParsing -Uri $installerPage
        }
        catch { continue }

        $exeName = "python-$version-amd64.exe"
        if (-not ($page.Links.href -contains $exeName)) { continue }

        $node = $cache.CreateElement('version')
        $node.SetAttribute('x64', 'true')
        $node.SetAttribute('webInstall', 'false')
        $node.SetAttribute('msi', 'false')

        $codeNode = $cache.CreateElement('code')
        $codeNode.InnerText = $version
        $node.AppendChild($codeNode) | Out-Null

        $fileNode = $cache.CreateElement('file')
        $fileNode.InnerText = $exeName
        $node.AppendChild($fileNode) | Out-Null

        $urlNode = $cache.CreateElement('URL')
        $urlNode.InnerText = "$installerPage$exeName"
        $node.AppendChild($urlNode) | Out-Null

        $cache.versions.AppendChild($node) | Out-Null
        $added++
    }

    if ($added -gt 0) {
        $cache.Save($cachePath)
        Write-Info "Added $added missing version(s) to .versions_cache.xml"
    }
    else {
        Write-Info 'Cache already up to date.'
    }
}

function Get-LatestPythonVersion {
    param([switch]$IncludeFreeThreaded)

    $pyenvRoot = Get-PyenvRoot
    $cachePath = Join-Path $pyenvRoot '.versions_cache.xml'
    $cache = Read-XmlFileWithRetry -Path $cachePath

    $candidates = $cache.versions.version.code | Where-Object {
        if ($IncludeFreeThreaded) { $_ -match '^\d+\.\d+\.\d+t?$' }
        else { $_ -match '^\d+\.\d+\.\d+$' }
    }

    $candidates |
        Sort-Object { [version]($_ -replace 't$', '') } |
        Select-Object -Last 1
}

function Install-GlobalPython {
    param([string]$Version)

    if (-not $Version) {
        Write-Step 'Resolving latest Python release'
        $Version = Get-LatestPythonVersion -IncludeFreeThreaded:$IncludeFreeThreaded
        if (-not $Version) { throw 'Could not resolve a latest Python version from the pyenv-win cache.' }
    }
    Write-Info "Target version: $Version"

    Write-Step "Installing Python $Version via pyenv"
    & pyenv install $Version --skip-existing
    & pyenv global $Version
    Update-SessionPath

    if ($script:ResolvedScope -eq 'System') {
        Set-SharedReadExecuteAcl -Path $script:SystemShareRoot
    }

    Write-Info "pyenv version: $(& pyenv version)"
}

# --- main ---

Write-Step "Scope: $script:ResolvedScope"
if ($script:ResolvedScope -eq 'System') {
    Write-Info "Shared under $(Get-PyenvRoot); other user accounts pick this up on next login."
}

Ensure-BootstrapPython
Ensure-PyenvWin
Repair-PyenvVersionCache
Install-GlobalPython -Version $PythonVersion

Write-Step 'Done'
Write-Info 'Open a new shell (or re-import your profile) to pick up PATH.'
Write-Info 'Per-project: `pyenv local <version>`, then `python -m venv .venv` and `.venv\Scripts\Activate.ps1` each session.'
