#requires -Version 7.6
<#
.SYNOPSIS
  Contract test for the WinPE target-disk guard baked into LaunchApply.cmd.
.NOTES
  LaunchApply runs `clean` on a disk with no operator present, so the decision of *which* disk is the
  most destructive line WinMint emits. It cannot be exercised in WinPE from a dev box, so this drives
  the real batch logic with pre-seeded diskpart output and asserts every branch, including refusal.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$patchScript = Join-Path $repo 'servicing/Patch-BootWimApply.ps1'
$body = [regex]::Match(
    (Get-Content -LiteralPath $patchScript -Raw),
    '(?s)\$launchApply = @"\r?\n(.*?)\r?\n"@').Groups[1].Value
if ([string]::IsNullOrWhiteSpace($body)) { throw 'cannot extract LaunchApply body — the scan is broken, not clean' }

$lines = ($body -replace '\$applyWimIndex', '1') -split "\r?\n"
$start = [array]::IndexOf($lines, 'set WORK=%TEMP%\winmint')
$stop = [array]::IndexOf($lines, 'echo WinMint: erasing disk %TARGET%')
$sub = [array]::IndexOf($lines, ':winmint_pick')
if ($start -lt 0 -or $stop -le $start -or $sub -le $stop) { throw 'LaunchApply layout changed — update this test' }

# Same decision logic, with the two diskpart reads pre-seeded. Nothing destructive is carried over.
$harness = @('@echo off', 'setlocal EnableExtensions', 'set INSTALL=Z') +
    ($lines[$start..$stop] | ForEach-Object {
        if ($_ -match 'echo list disk \| diskpart') { 'rem pre-seeded' } else { $_ } }) +
    @('echo RESULT TARGET=%TARGET% EXTRA=%EXTRA%', 'exit /b 0', '') +
    ($lines[$sub..($lines.Length - 1)] | ForEach-Object {
        if ($_ -match '^\(echo select disk') { 'rem pre-seeded' } else { $_ } })

foreach ($danger in 'clean', 'Apply-Image', 'bcdboot', 'wpeutil', 'format') {
    if ($harness -match $danger) { throw "refusing to run: '$danger' leaked into the harness" }
}

$work = Join-Path $env:TEMP 'winmint'
$usb = Join-Path $env:TEMP 'winmint-fake-usb'
$cmdPath = Join-Path $env:TEMP 'winmint-diskguard-contract.cmd'
Set-Content -LiteralPath $cmdPath -Value ($harness -join "`r`n") -Encoding ascii
New-Item -ItemType Directory -Force -Path $usb | Out-Null
& subst Z: /D 2>&1 | Out-Null
& subst Z: $usb
if ($LASTEXITCODE -ne 0) { throw 'cannot map Z: for the override case' }

$failures = @()
function Assert-Case {
    param([string] $Name, [object[]] $Disks, [string] $Override, [string] $Expect)

    Remove-Item "$work\*" -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    Remove-Item 'Z:\winmint-target-disk.txt' -Force -ErrorAction SilentlyContinue

    $list = "`r`n  Disk ###  Status         Size     Free     Dyn  Gpt`r`n  --------  ----`r`n"
    for ($i = 0; $i -lt $Disks.Count; $i++) {
        $list += "  Disk $i    Online          953 GB      0 B        *`r`n"
        [IO.File]::WriteAllText("$work\d$i.txt", "$($Disks[$i][1])`r`nType   : $($Disks[$i][0])`r`nStatus : Online`r`n")
    }
    [IO.File]::WriteAllText("$work\disks.txt", $list)
    if ($Override) { [IO.File]::WriteAllText('Z:\winmint-target-disk.txt', $Override) }

    $out = (& cmd /c $cmdPath) -join ' '
    if ($out -notmatch [regex]::Escape($Expect)) {
        $script:failures += "$Name`n    expected: $Expect`n    actual:   $($out -replace '\s+', ' ')"
    }
}

try {
    # The everyday case: one internal disk, still fully unattended.
    Assert-Case 'single internal disk' @(, @('NVMe', 'HFS001')) '' 'TARGET=0 EXTRA='
    # The installer must never erase the media it booted from.
    Assert-Case 'internal disk plus USB stick' @(@('NVMe', 'HFS001'), @('USB', 'Cruzer')) '' 'TARGET=0 EXTRA='
    Assert-Case 'USB enumerated first' @(@('USB', 'Cruzer'), @('NVMe', 'HFS001')) '' 'TARGET=1 EXTRA='
    # Two candidates is exactly where size heuristics guess wrong, so refuse instead.
    Assert-Case 'two internal disks refuses' @(@('NVMe', 'HFS001'), @('NVMe', 'Samsung')) '' 'refusing to guess'
    Assert-Case 'no fixed disk refuses' @(@('USB', 'Cruzer'), @('USB', 'Kingston')) '' 'no fixed disk to erase'
    # Operator escape hatch for the ambiguous case, which must not widen the USB exclusion.
    Assert-Case 'override resolves ambiguity' @(@('NVMe', 'HFS001'), @('NVMe', 'Samsung')) 'Samsung' 'TARGET=1 EXTRA='
    Assert-Case 'override matching nothing refuses' @(@('NVMe', 'HFS001'), @('NVMe', 'Samsung')) 'Toshiba' 'no fixed disk'
    Assert-Case 'override cannot select a USB' @(@('NVMe', 'HFS001'), @('USB', 'Samsung BAR')) 'Samsung' 'no fixed disk'
}
finally {
    & subst Z: /D 2>&1 | Out-Null
    Remove-Item $usb, $work -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $cmdPath -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Output "Disk guard contract FAILED:`n$($failures -join "`n")"
    exit 1
}

Write-Output 'Disk guard contract tests passed.'
exit 0
