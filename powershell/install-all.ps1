<#
.SYNOPSIS
    One-command chain over the atomic setup scripts. Deliberately NOT
    fail-fast: each script runs independently, failures are recorded and
    the chain continues -- a broken browser install shouldn't block the
    Python toolchain. Exits non-zero if anything failed, with a summary
    table either way.

.NOTES
    setup-wsl.ps1 is deliberately excluded: enabling the WSL feature can
    require elevation and a reboot, which has no business appearing
    mid-way through an unattended chain. Run it separately.

    Every underlying script is idempotent, so re-running this after
    fixing a failure only redoes the broken pieces.
#>

[CmdletBinding()]
param()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Chain order: foundations first (git, uv), then everything else.
$Scripts = @(
    'setup-git.ps1'
    'setup-uv.ps1'
    'setup-cli-tools.ps1'
    'setup-nvim.ps1'
    'setup-oh-my-posh.ps1'
    'setup-gh-cli.ps1'
    'setup-obsidian.ps1'
    'setup-vscode.ps1'
    'setup-zen-browser.ps1'
    'setup-librewolf.ps1'
    'setup-claude-desktop.ps1'
    'setup-claude-code.ps1'
)

$passed = @()
$failed = @()

foreach ($script in $Scripts) {
    Write-Host "`n########## $script ##########"
    try {
        & (Join-Path $ScriptDir $script)
        if ($LASTEXITCODE -eq 0) {
            $passed += $script
        }
        else {
            $failed += "$script (exit $LASTEXITCODE)"
        }
    }
    catch {
        $failed += "$script (threw: $($_.Exception.Message))"
    }
}

Write-Host "`n########## Summary ##########"
foreach ($s in $passed) { Write-Host "  PASS  $s" }
foreach ($s in $failed) { Write-Host "  FAIL  $s" }

if ($failed.Count -gt 0) {
    Write-Host "`n$($failed.Count) of $($Scripts.Count) scripts failed. Fix and re-run -- everything is idempotent, only the broken pieces redo work."
    exit 1
}
Write-Host "`nAll $($Scripts.Count) scripts succeeded."
exit 0
