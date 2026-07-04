<#
.SYNOPSIS
    One-command update sweep across every package domain the bootstrap
    scripts installed -- the `apt upgrade` experience for this machine.
    NOT part of the install-all chain; run it when you want updates.

.NOTES
    Domains covered: winget packages, uv tools, npm globals, the Roslyn
    dotnet tool, PSScriptAnalyzer. Continue-on-error like install-all: a
    failing domain reports and the sweep moves on.

    Deliberately NOT covered (each has its own owner):
      - nvim plugins     : vim.pack.update() inside nvim (review buffer)
      - treesitter parsers: :TSUpdate inside nvim (also runs on plugin update)
      - PowerShell Editor Services: delete the bundle dir + re-run
        setup-nvim-tooling.ps1
      - pinned winget packages: `winget pin add <id>` exempts a package
        from --all; list with `winget pin list`
#>

[CmdletBinding()]
param()

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

$failed = @()

Write-Step 'winget packages'
winget upgrade --all --accept-package-agreements --accept-source-agreements --include-unknown
# 0x8A15002B = "no applicable upgrade found" -- that's success for a sweep.
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { $failed += 'winget' }

Write-Step 'uv tools'
if (Get-Command uv -ErrorAction SilentlyContinue) {
    uv tool upgrade --all
    if ($LASTEXITCODE -ne 0) { $failed += 'uv-tools' }
}
else { Write-Info 'uv not installed; skipping.' }

Write-Step 'npm globals'
if (Get-Command npm -ErrorAction SilentlyContinue) {
    npm update -g
    if ($LASTEXITCODE -ne 0) { $failed += 'npm' }
}
else { Write-Info 'npm not installed; skipping.' }

Write-Step 'dotnet tools (roslyn)'
if ((Get-Command dotnet -ErrorAction SilentlyContinue) -and
    (Get-Command roslyn-language-server -ErrorAction SilentlyContinue)) {
    dotnet tool update -g roslyn-language-server --prerelease `
        --add-source https://pkgs.dev.azure.com/azure-public/vside/_packaging/vs-impl/nuget/v3/index.json
    if ($LASTEXITCODE -ne 0) { $failed += 'roslyn' }
}
else { Write-Info 'roslyn-language-server not installed; skipping.' }

Write-Step 'PSScriptAnalyzer'
if (Get-Module -ListAvailable PSScriptAnalyzer) {
    try { Update-Module PSScriptAnalyzer -ErrorAction Stop } catch { $failed += 'PSScriptAnalyzer' }
}
else { Write-Info 'PSScriptAnalyzer not installed; skipping.' }

Write-Step 'Summary'
if ($failed.Count -eq 0) {
    Write-Info 'All domains updated.'
}
else {
    Write-Info "Failed domains: $($failed -join ', ')"
}
Write-Info 'Editor-owned updates: vim.pack.update() and :TSUpdate inside nvim.'
exit ($failed.Count -gt 0 ? 1 : 0)
