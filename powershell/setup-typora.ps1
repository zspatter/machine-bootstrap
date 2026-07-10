<#
.SYNOPSIS
    Fresh-machine bootstrap: installs Typora via winget plus the house
    theme set (Blackout Gamer, Chernobyl, Drake) into the themes folder.

.NOTES
    Safe to re-run; each piece is install-if-missing.

    TWO MANUAL STEPS REMAIN, by design:
    - License: Typora is a paid one-time purchase; enter the key in
      Typora > Preferences after first launch.
    - Theme selection: pick from the Themes menu (Drake Vue3 is the
      house default). Typora persists the choice in profile.data, which
      also carries window state and isn't safely pre-seedable across
      versions.

    Settings extraction into sym-lattice dotfiles is deferred until
    Typora has run once -- conf\conf.user.json and friends don't exist
    until then, and there's nothing to capture from a fresh install.

    Themes land in %APPDATA%\Typora\themes:
    - Blackout Gamer + Chernobyl (green and blue variants): release
      assets of github.com/obscurefreeman/typora_theme_blackout
      (one repo distributes the author's whole Blackout series).
    - Drake family (drake-vue3.css among them): master zipball of
      github.com/liangjingkanji/DrakeTyporaTheme -- the css files plus
      the drake/ folder its fonts live in.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

# --- Typora itself ---
Write-Step 'Checking for Typora'
$TyporaExe = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Typora\Typora.exe'),
    (Join-Path $env:ProgramFiles 'Typora\Typora.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($TyporaExe) {
    Write-Info "Found $TyporaExe"
}
else {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Info 'No winget available; install manually from https://typora.io, then re-run.'
        exit 1
    }
    Write-Info 'Installing via winget.'
    winget install -e --id appmakes.Typora --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget install exited with code $LASTEXITCODE" }
    Write-Info 'Installed. Reminder: enter the license in Typora > Preferences (one-time purchase).'
}

# --- Themes ---
$ThemesDir = Join-Path $env:APPDATA 'Typora\themes'
New-Item -ItemType Directory -Force $ThemesDir | Out-Null

function Install-ThemeZip {
    param(
        [string]$Name,
        [string]$Url,
        # a file glob that proves this theme is already in place
        [string]$Marker,
        # what to copy out of the zip root; default everything (the
        # Blackout zips are curated for the themes dir as-is)
        [string[]]$Items = @('*')
    )
    if (Get-ChildItem $ThemesDir -Filter $Marker -ErrorAction SilentlyContinue) {
        Write-Info "$Name already present"
        return
    }
    Write-Info "Fetching $Name"
    $tmp = Join-Path $env:TEMP ('typora-theme-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $tmp | Out-Null
    try {
        $zip = Join-Path $tmp 'theme.zip'
        Invoke-WebRequest -UseBasicParsing -MaximumRetryCount 3 -RetryIntervalSec 2 -Uri $Url -OutFile $zip
        $extract = Join-Path $tmp 'x'
        Expand-Archive $zip -DestinationPath $extract
        # GitHub zipballs (and some release zips) wrap everything in a
        # single top-level folder -- unwrap so paths land flat.
        $root = $extract
        $top = @(Get-ChildItem $extract)
        if ($top.Count -eq 1 -and $top[0].PSIsContainer) { $root = $top[0].FullName }
        foreach ($item in $Items) {
            Copy-Item (Join-Path $root $item) $ThemesDir -Recurse -Force
        }
        Write-Info "$Name installed"
    }
    finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}

Write-Step 'Installing themes'
$BlackoutRelease = 'https://github.com/obscurefreeman/typora_theme_blackout/releases/latest/download'
Install-ThemeZip -Name 'Blackout Gamer' -Url "$BlackoutRelease/blackout_theme_gamer.zip" -Marker '*gamer*.css'
Install-ThemeZip -Name 'Chernobyl' -Url "$BlackoutRelease/blackout_theme_chernobyl.zip" -Marker '*chernobyl*.css'
Install-ThemeZip -Name 'Drake' -Url 'https://github.com/liangjingkanji/DrakeTyporaTheme/archive/refs/heads/master.zip' `
    -Marker 'drake-vue3.css' -Items @('*.css', 'drake')

Write-Step 'Done'
Write-Info 'Manual: enter the license, then Themes menu > Drake Vue3 (house default).'
exit 0
