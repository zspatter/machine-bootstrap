<#
.SYNOPSIS
    Fresh-machine bootstrap: installs the LSP servers, linters, and
    formatters the Neovim config (sym-lattice dotfiles/vim/nvim) expects.
    Companion to setup-nvim.ps1, which installs the editor itself.

.NOTES
    Safe to re-run. The config deliberately uses no mason.nvim -- servers
    are ordinary CLI tools, so this script is where their maintenance
    lives. Tool inventory (driven by that config's lsp.lua /
    linting.lua / formatting.lua):

      lua-language-server, shellcheck, shfmt, stylua  : winget
      pyright, bash-language-server                   : npm (Node LTS via winget)
      ruff                                            : uv tool
      PSScriptAnalyzer                                : Install-Module
      PowerShell Editor Services                      : GitHub release bundle,
        extracted to a FIXED path ($env:LOCALAPPDATA\powershell-editor-services)
        that the config's powershell_es setup relies on -- change one, change both.

    Updates: `npm i -g` reinstalls latest on every run; the rest are
    install-if-missing (use `winget upgrade`, `uv tool upgrade ruff`,
    `Update-Module PSScriptAnalyzer`, or delete the PES dir and re-run).
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

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Info 'No winget available; install the tools manually, then re-run.'
    exit 1
}

# --- winget-packaged tools (command name -> package id) ---
$WingetTools = [ordered]@{
    'lua-language-server' = 'LuaLS.lua-language-server'
    'shellcheck'          = 'koalaman.shellcheck'
    'shfmt'               = 'mvdan.shfmt'
    'stylua'              = 'JohnnyMorganz.StyLua'
}

Write-Step 'Installing winget-packaged tools'
foreach ($cmd in $WingetTools.Keys) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Write-Info "$cmd already installed"
        continue
    }
    Write-Info "Installing $($WingetTools[$cmd])"
    winget install -e --id $WingetTools[$cmd] --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget install $($WingetTools[$cmd]) exited with code $LASTEXITCODE" }
}
Update-SessionPath

# --- npm-only language servers (need Node LTS first) ---
Write-Step 'Installing npm-based language servers'
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Info 'No npm; installing Node LTS via winget.'
    winget install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget install Node LTS exited with code $LASTEXITCODE" }
    Update-SessionPath
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        throw 'npm still not on PATH after Node install. Open a new shell and re-run.'
    }
}
# npm i -g installs AND updates -- this doubles as the update path for both.
npm install -g pyright bash-language-server
if ($LASTEXITCODE -ne 0) { throw "npm install exited with code $LASTEXITCODE" }

# --- ruff (uv-managed, consistent with the Python toolchain) ---
Write-Step 'Installing ruff'
if (Get-Command ruff -ErrorAction SilentlyContinue) {
    Write-Info 'ruff already installed'
}
elseif (Get-Command uv -ErrorAction SilentlyContinue) {
    uv tool install ruff
    if ($LASTEXITCODE -ne 0) { throw 'uv tool install ruff failed' }
}
else {
    Write-Info 'Neither ruff nor uv found -- run setup-uv.ps1 first, then re-run.'
    exit 1
}

# --- PSScriptAnalyzer (PowerShell lint + the Invoke-Formatter conform uses) ---
Write-Step 'Installing PSScriptAnalyzer'
if (Get-Module -ListAvailable PSScriptAnalyzer) {
    Write-Info 'PSScriptAnalyzer already installed'
}
else {
    Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
    Write-Info "Installed PSScriptAnalyzer $((Get-Module -ListAvailable PSScriptAnalyzer).Version)"
}

# --- PowerShell Editor Services bundle, at the path lsp.lua relies on ---
Write-Step 'Installing PowerShell Editor Services'
$PsesBundle = Join-Path $env:LOCALAPPDATA 'powershell-editor-services'
$PsesLauncher = Join-Path $PsesBundle 'PowerShellEditorServices\Start-EditorServices.ps1'
if (Test-Path $PsesLauncher) {
    Write-Info "Bundle already present at $PsesBundle (delete the dir and re-run to update)."
}
else {
    $zip = Join-Path $env:TEMP 'PowerShellEditorServices.zip'
    Invoke-WebRequest -UseBasicParsing -OutFile $zip -Uri `
        'https://github.com/PowerShell/PowerShellEditorServices/releases/latest/download/PowerShellEditorServices.zip'
    Expand-Archive -Path $zip -DestinationPath $PsesBundle -Force
    Remove-Item $zip -ErrorAction SilentlyContinue
    if (-not (Test-Path $PsesLauncher)) {
        throw "PES bundle extracted but launcher not found at $PsesLauncher -- release layout may have changed."
    }
    Write-Info "Installed to $PsesBundle"
}

# --- verify everything the nvim config launches ---
Write-Step 'Verifying'
$failed = @()
foreach ($cmd in @('lua-language-server', 'shellcheck', 'shfmt', 'stylua', 'ruff',
                   'pyright-langserver', 'bash-language-server')) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Write-Info "${cmd}: ok"
    }
    else {
        Write-Info "${cmd}: MISSING (may need a new shell)"
        $failed += $cmd
    }
}
if (Get-Module -ListAvailable PSScriptAnalyzer) { Write-Info 'PSScriptAnalyzer: ok' } else { $failed += 'PSScriptAnalyzer' }
if (Test-Path $PsesLauncher) { Write-Info 'PowerShellEditorServices: ok' } else { $failed += 'PES' }
if ($failed.Count -gt 0) {
    Write-Info "Not resolvable in this session: $($failed -join ', '). Open a new shell and verify."
}

Write-Step 'Done'
Write-Info 'Launch nvim and run :checkhealth vim.lsp to confirm servers attach.'
exit 0
