<#
.SYNOPSIS
    setup-audio-eq.ps1 - provision headphone EQ on Windows (Sennheiser HD 800 S, oratory1990)

.DESCRIPTION
    Standalone, hardware-scoped: run only on machines with the DAC/headphones.
    Deliberately NOT wired into the main machine-bootstrap chain.

    Engine is Equalizer APO; the vendored parametric txt is APO's native format.

    Modes:
      (default)   Direct APO include of the repo artifact, scoped to the DAC via
                  a 'Device:' directive, inside a marked block in config.txt.
                  Any 'Include: ...Peace.txt' line is disabled (marker-commented)
                  to prevent double EQ. Peace stays installed but inert.
      -Peace      Peace-managed mode: removes the direct block, restores the
                  Peace include, and prints the one-time GUI import step
                  (Peace preset import cannot be automated).
      -Remove     Return config.txt to its pre-script state: block removed,
                  disabled Peace include restored.
      -Status     Report current state.

    Requires an elevated shell on Windows (config.txt lives under Program Files).
    Equalizer APO hot-reloads config.txt on save; no restart is needed.

    First-time APO install remains manual by nature: install Equalizer APO,
    run Configurator to bind the APO to the FiiO endpoint, reboot, re-run this.

.PARAMETER Device
    Substring for APO's 'Device:' directive so the EQ rides only the DAC.
    Default: FiiO

.PARAMETER ConfigPath
    Path to Equalizer APO's config.txt. Default: the standard install path.
    Overriding this (tests) skips the elevation check.

.PARAMETER AssetsPath
    Override the assets directory. Default resolution mirrors the bash script:
    AUDIO_EQ_ASSETS env, then <repo>/assets/audio-eq relative to this script.
#>
[CmdletBinding(DefaultParameterSetName = 'Direct')]
param(
    [Parameter(ParameterSetName = 'Peace')]  [switch]$Peace,
    [Parameter(ParameterSetName = 'Remove')] [switch]$Remove,
    [Parameter(ParameterSetName = 'Status')] [switch]$Status,
    [string]$Device = 'FiiO',
    [string]$ConfigPath,
    [string]$AssetsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- constants ---------------------------------------------------------------
$TxtName        = 'hd800s-oratory1990-parametric.txt'
$BlockBegin     = '# >>> machine-bootstrap audio-eq >>>'
$BlockEnd       = '# <<< machine-bootstrap audio-eq <<<'
$DisabledMarker = '#[audio-eq-disabled] '
$PeaceIncludeRx = '^\s*Include:\s*.*Peace\.txt\s*$'
$DefaultConfig  = 'C:\Program Files\EqualizerAPO\config\config.txt'

# --- helpers -----------------------------------------------------------------
function Write-Step { param([string]$Msg) Write-Host "`n==> $Msg" -ForegroundColor Cyan }
function Write-Log  { param([string]$Msg) Write-Host "    $Msg" }
function Write-Warn { param([string]$Msg) Write-Warning $Msg }
function Fail       { param([string]$Msg) Write-Error $Msg -ErrorAction Continue; exit 1 }

function Resolve-Assets {
    $candidates = @(
        $AssetsPath,
        $env:AUDIO_EQ_ASSETS,
        (Join-Path $PSScriptRoot '..' 'assets' 'audio-eq'),
        (Join-Path $PSScriptRoot 'assets' 'audio-eq'),
        $PSScriptRoot
    ) | Where-Object { $_ }
    foreach ($d in $candidates) {
        $f = Join-Path $d $TxtName
        if (Test-Path -LiteralPath $f) { return (Resolve-Path -LiteralPath $d).Path }
    }
    Fail "assets not found (looked for $TxtName); pass -AssetsPath or set AUDIO_EQ_ASSETS"
}

function Test-Asset {
    param([string]$File)
    $raw = Get-Content -LiteralPath $File -Raw
    if ($raw -match "`r") {
        Fail "asset has CRLF line endings; keep the canonical artifact LF-only (PipeWire consumer requires it)"
    }
    $first = (Get-Content -LiteralPath $File -TotalCount 1)
    if ($first -notmatch '^Preamp:\s*-?[0-9.]+\s*dB') {
        Fail "line 1 of $File must be the 'Preamp: ... dB' line (PipeWire reads preamp only from line 1)"
    }
    $filters = @(Get-Content -LiteralPath $File | Where-Object { $_ -match '^Filter' }).Count
    $preamp  = [regex]::Match($first, '-?[0-9]+(\.[0-9]+)?').Value
    Write-Log "asset OK: $filters filters, preamp $preamp dB (APO applies the Preamp line natively)"
}

function Assert-Elevated {
    if (-not $IsWindows) { return }                       # container/CI testing
    if ($ConfigPath) { return }                           # explicit override = test context
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = [Security.Principal.WindowsPrincipal]::new($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Fail 'run from an elevated shell; config.txt lives under Program Files'
    }
}

function Get-ConfigFile {
    $path = if ($ConfigPath) { $ConfigPath } else { $DefaultConfig }
    if (-not (Test-Path -LiteralPath $path)) {
        Fail @"
Equalizer APO config not found at: $path
First-time setup is manual by nature:
  1. Install Equalizer APO (choco install equalizerapo, or the official installer)
  2. Run Configurator.exe and bind the APO to the FiiO playback endpoint
  3. Reboot
  4. Re-run this script
"@
    }
    return $path
}

function Read-Lines  { param([string]$Path) ,@(Get-Content -LiteralPath $Path) }
function Write-Lines {
    param([string]$Path, [string[]]$Lines)
    $bak = "$Path.audio-eq.bak"
    if (-not (Test-Path -LiteralPath $bak)) {
        Copy-Item -LiteralPath $Path -Destination $bak
        Write-Log "backup written: $bak"
    }
    Set-Content -LiteralPath $Path -Value $Lines
}

function Remove-Block {
    param([string[]]$Lines)
    $b = [array]::IndexOf($Lines, $BlockBegin)
    $e = [array]::IndexOf($Lines, $BlockEnd)
    if ($b -lt 0 -and $e -lt 0) { return ,$Lines }
    if ($b -lt 0 -or $e -lt 0 -or $e -lt $b) {
        Fail "config.txt has a corrupt audio-eq block (unmatched markers); repair manually"
    }
    # index-guarded loop: range slicing ($a..$b) descends when $a > $b and
    # resurrects markers when the block sits at the tail of the file
    $out = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($i -lt $b -or $i -gt $e) { $out.Add($Lines[$i]) }
    }
    return ,$out.ToArray()
}

function Disable-PeaceInclude {
    param([string[]]$Lines)
    ,@($Lines | ForEach-Object {
        if ($_ -match $PeaceIncludeRx -and -not $_.StartsWith($DisabledMarker)) {
            Write-Log "disabling Peace include (double-EQ guard): $_"
            "$DisabledMarker$_"
        } else { $_ }
    })
}

function Restore-PeaceInclude {
    param([string[]]$Lines)
    ,@($Lines | ForEach-Object {
        if ($_.StartsWith($DisabledMarker)) {
            Write-Log "restoring Peace include"
            $_.Substring($DisabledMarker.Length)
        } else { $_ }
    })
}

# --- modes -------------------------------------------------------------------
function Invoke-Direct {
    Write-Step 'Provisioning headphone EQ (direct APO include)'
    Assert-Elevated
    $config = Get-ConfigFile
    $assets = Resolve-Assets
    $txt    = Join-Path $assets $TxtName
    Test-Asset $txt

    $lines = Read-Lines $config
    $lines = Remove-Block $lines
    $lines = Disable-PeaceInclude $lines
    $lines += @(
        $BlockBegin
        "Device: $Device"
        "Include: $txt"
        $BlockEnd
    )
    Write-Lines $config $lines
    Write-Log "direct mode active: Device '$Device' -> $TxtName"
    Write-Log 'APO hot-reloads config.txt; the EQ is live now (verify with an A/B listen)'
    Write-Log 'Peace remains installed but inert; re-enable with -Peace'
}

function Invoke-Peace {
    Write-Step 'Provisioning headphone EQ (Peace-managed)'
    Assert-Elevated
    $config = Get-ConfigFile
    $assets = Resolve-Assets
    $txt    = Join-Path $assets $TxtName

    $lines = Read-Lines $config
    $lines = Remove-Block $lines
    $lines = Restore-PeaceInclude $lines
    if (-not ($lines | Where-Object { $_ -match $PeaceIncludeRx })) {
        Write-Log 'no Peace include found; adding one'
        $lines += 'Include: Peace.txt'
    }
    Write-Lines $config $lines

    $peaceExe = Join-Path (Split-Path (Split-Path $config)) 'Peace.exe'
    if ($IsWindows -and -not (Test-Path -LiteralPath $peaceExe)) {
        Write-Warn 'Peace.exe not found next to the APO install; install Peace (choco install peace) first'
    }
    Write-Log 'Peace mode active. One-time manual step (Peace preset import has no CLI):'
    Write-Log "  Peace -> Import -> select: $txt -> save as preset 'hd800s-oratory1990' -> activate"
}

function Invoke-Remove {
    Write-Step 'Removing provisioned headphone EQ'
    Assert-Elevated
    $config = Get-ConfigFile
    $lines  = Read-Lines $config
    $lines  = Remove-Block $lines
    $lines  = Restore-PeaceInclude $lines
    Write-Lines $config $lines
    Write-Log 'teardown complete: config.txt returned to pre-script state (APO/Peace left installed)'
}

function Invoke-Status {
    $path = if ($ConfigPath) { $ConfigPath } else { $DefaultConfig }
    if (-not (Test-Path -LiteralPath $path)) { Write-Log 'Equalizer APO: not installed'; return }
    $lines = Read-Lines $path
    $hasBlock    = $lines -contains $BlockBegin
    $peaceLive   = [bool]($lines | Where-Object { $_ -match $PeaceIncludeRx })
    $peaceParked = [bool]($lines | Where-Object { $_.StartsWith($DisabledMarker) })
    if ($hasBlock) {
        $dev = ($lines | Where-Object { $_ -match '^Device: ' } | Select-Object -First 1)
        Write-Log "mode: direct ($dev)"
        if ($peaceParked) { Write-Log 'Peace include: disabled by this script' }
    } elseif ($peaceLive) {
        Write-Log 'mode: peace (Peace include active, no direct block)'
    } else {
        Write-Log 'mode: none (no EQ provisioned by this script)'
    }
}

# --- main --------------------------------------------------------------------
switch ($PSCmdlet.ParameterSetName) {
    'Peace'  { Invoke-Peace }
    'Remove' { Invoke-Remove }
    'Status' { Invoke-Status }
    default  { Invoke-Direct }
}
