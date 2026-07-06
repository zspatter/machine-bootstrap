<#
.SYNOPSIS
    Fresh-machine bootstrap: installs the preferred Nerd Font families,
    per-user (no elevation) -- JetBrains Mono NF and Fira Code NF for
    editors (ligatures intact: NF patching only adds glyphs on top of the
    base font), Meslo LGM NF for terminal prompts (the oh-my-posh
    recommendation).

.NOTES
    Safe to re-run. The nerd-fonts release zips ship every size/spacing
    variant (Meslo alone: 72 ttfs across LGS/LGM/LGL x DZ x Mono/Propo;
    JetBrainsMono: 96) -- installing them all is exactly the font-picker
    clutter this script exists to avoid. Only the curated Match subsets
    below land (11 files total). Extend a Match regex if you ever want
    another weight; delete the family's Probe file and re-run to update.

    Per-user install = copy to %LOCALAPPDATA%\Microsoft\Windows\Fonts plus
    an HKCU Fonts registry value holding the full path (the same mechanism
    scoop/choco font packages use -- fonts outside C:\Windows\Fonts need
    full-path values). Apps started after the install see the fonts;
    already-running apps need a restart.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

# Asset = zip name in the ryanoasis/nerd-fonts release. Match = the curated
# subset actually installed (NL = no-ligatures, Mono/Propo = alternate glyph
# spacing, LGS/LGL/DZ = other Meslo line gaps -- all deliberately excluded).
# FiraCode has no italics; Retina is its signature between-weight.
$Fonts = @(
    @{ Asset = 'JetBrainsMono'; Match = '^JetBrainsMonoNerdFont-(Regular|Bold|Italic|BoldItalic)\.ttf$'; Probe = 'JetBrainsMonoNerdFont-Regular.ttf' }
    @{ Asset = 'FiraCode'; Match = '^FiraCodeNerdFont-(Regular|Retina|Bold)\.ttf$'; Probe = 'FiraCodeNerdFont-Regular.ttf' }
    @{ Asset = 'Meslo'; Match = '^MesloLGMNerdFont-(Regular|Bold|Italic|BoldItalic)\.ttf$'; Probe = 'MesloLGMNerdFont-Regular.ttf' }
)

$FontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$RegKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
New-Item -ItemType Directory -Force -Path $FontDir | Out-Null
if (-not (Test-Path $RegKey)) { New-Item -Path $RegKey -Force | Out-Null }

foreach ($font in $Fonts) {
    Write-Step "Installing $($font.Asset) Nerd Font (curated subset)"
    if (Test-Path (Join-Path $FontDir $font.Probe)) {
        Write-Info "$($font.Probe) already present -- skipping"
        continue
    }

    $zip = Join-Path $env:TEMP "$($font.Asset)-nf.zip"
    $extract = Join-Path $env:TEMP "$($font.Asset)-nf"
    Invoke-WebRequest -UseBasicParsing -MaximumRetryCount 3 -RetryIntervalSec 2 -OutFile $zip -Uri `
        "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$($font.Asset).zip"
    Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive -Path $zip -DestinationPath $extract -Force

    $installed = 0
    foreach ($ttf in Get-ChildItem $extract -Filter '*.ttf' | Where-Object Name -match $font.Match) {
        $target = Join-Path $FontDir $ttf.Name
        Copy-Item $ttf.FullName $target -Force
        # Filename-based registry name (the scoop/choco convention).
        New-ItemProperty -Path $RegKey -Name "$($ttf.BaseName) (TrueType)" `
            -Value $target -PropertyType String -Force | Out-Null
        $installed++
    }
    Remove-Item $zip, $extract -Recurse -Force -ErrorAction SilentlyContinue

    if ($installed -eq 0) {
        throw "No files in $($font.Asset).zip matched '$($font.Match)' -- release layout may have changed."
    }
    Write-Info "Installed $installed faces"
}

Write-Step 'Done'
Write-Info 'Restart terminals/editors to pick up the new fonts.'
exit 0
