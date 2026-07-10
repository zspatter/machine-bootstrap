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

      lua-language-server, marksman (markdown),
        shellcheck, shfmt, stylua                     : winget
      tree-sitter-cli                                 : winget (>=0.26.1)
      MSVC Build Tools (VC workload)                  : winget -- the C compiler
        nvim-treesitter parser compiles need; cc discovers it via vswhere, so
        no PATH/vcvars setup is required
      pyright, bash-language-server,
        vscode-langservers-extracted (json),
        yaml-language-server, @taplo/cli (toml),
        prettier (markdown formatter)                 : npm (Node LTS via winget)
      roslyn-language-server (C#)                     : dotnet tool from the Azure
        DevOps feed (same source VS Code uses; nuget.org lags). Skipped when no
        .NET SDK is present -- plugins/roslyn.lua gates on the exe either way.
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
    'marksman'            = 'Artempyanykh.Marksman'
    'shellcheck'          = 'koalaman.shellcheck'
    'shfmt'               = 'mvdan.shfmt'
    'stylua'              = 'JohnnyMorganz.StyLua'
    'tree-sitter'         = 'tree-sitter.tree-sitter-cli'
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

# --- MSVC Build Tools: the C compiler for nvim-treesitter parser compiles ---
# tree-sitter's build step (rust cc crate) locates MSVC through vswhere, so
# nothing here touches PATH and no vcvars shell is ever needed. Lighter
# compilers were evaluated and rejected (2026-07-03): standalone LLVM lacks
# the Windows SDK headers clang-cl needs, and the cc crate mishandles both
# multi-word CC values ("zig cc") and zig's target-triple spelling. ~3GB,
# but it's the one path upstream actually supports.
Write-Step 'Installing MSVC Build Tools (treesitter parser compiles)'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
function Test-VcTools {
    (Test-Path $vswhere) -and
        (& $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -latest -property installationPath)
}
if (Test-VcTools) {
    Write-Info 'VC tools already present'
}
else {
    winget install -e --id Microsoft.VisualStudio.2022.BuildTools `
        --accept-package-agreements --accept-source-agreements `
        --override '--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
    # 3010 = success, reboot pending -- fine for a compiler.
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 3010) {
        throw "winget install BuildTools exited with code $LASTEXITCODE"
    }
}

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
# npm i -g installs AND updates -- this doubles as the update path for all.
npm install -g pyright bash-language-server vscode-langservers-extracted yaml-language-server '@taplo/cli' prettier
if ($LASTEXITCODE -ne 0) { throw "npm install exited with code $LASTEXITCODE" }

# --- Roslyn C# language server (dotnet global tool) ---
# `dotnet tool update` installs when absent and updates when present, so one
# command is both paths. The Azure DevOps feed is what VS Code itself pulls
# from and updates far more often than nuget.org.
Write-Step 'Installing Roslyn language server (C#)'
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    # The tool package carries its DotnetToolSettings.xml under
    # tools/net10.0/ -- older SDKs can't see it and fail with "settings
    # file not found" (hit live on 8.0.422; nupkg inspected to confirm).
    # SDK 10 installs side-by-side, so existing projects keep building.
    $sdkMajors = dotnet --list-sdks | ForEach-Object { [int]($_ -split '\.')[0] }
    if (-not ($sdkMajors | Where-Object { $_ -ge 10 })) {
        Write-Info 'No .NET SDK >= 10 (required by the tool package format); installing side-by-side.'
        winget install -e --id Microsoft.DotNet.SDK.10 --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) { throw "winget install .NET SDK 10 exited with code $LASTEXITCODE" }
        Update-SessionPath
    }
    # --add-source, not --source: SDK 8's tool commands only know the former;
    # newer SDKs accept both, so this is the portable spelling. It adds the
    # feed alongside nuget.org rather than replacing it -- prerelease
    # resolution still lands on the freshest builds.
    dotnet tool update -g roslyn-language-server --prerelease `
        --add-source https://pkgs.dev.azure.com/azure-public/vside/_packaging/vs-impl/nuget/v3/index.json
    if ($LASTEXITCODE -ne 0) { throw "dotnet tool update roslyn-language-server exited with code $LASTEXITCODE" }
}
else {
    Write-Info 'No dotnet SDK on PATH; skipping (install the .NET SDK and re-run for C# LSP).'
}

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
    Invoke-WebRequest -UseBasicParsing -MaximumRetryCount 3 -RetryIntervalSec 2 -OutFile $zip -Uri `
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
$expected = @('lua-language-server', 'marksman', 'shellcheck', 'shfmt', 'stylua', 'ruff',
              'pyright-langserver', 'bash-language-server', 'tree-sitter',
              'vscode-json-language-server', 'yaml-language-server', 'taplo', 'prettier')
# roslyn only expected where dotnet exists (see install step above)
if (Get-Command dotnet -ErrorAction SilentlyContinue) { $expected += 'roslyn-language-server' }
foreach ($cmd in $expected) {
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
if (Test-VcTools) { Write-Info 'MSVC VC tools: ok' } else { $failed += 'MSVC-VC-tools' }
if ($failed.Count -gt 0) {
    Write-Info "Not resolvable in this session: $($failed -join ', '). Open a new shell and verify."
}

Write-Step 'Done'
Write-Info 'Launch nvim and run :checkhealth vim.lsp to confirm servers attach.'
exit 0
