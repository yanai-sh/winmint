#requires -Version 7.6
<#
.SYNOPSIS
  Contract test for the WinPE target-disk guard baked into LaunchApply.cmd, and for the patched-media
  contract the pre-wipe gate reads.
.NOTES
  LaunchApply runs `clean` on a disk with no operator present, so the decision of *which* disk is the
  most destructive line WinMint emits. It cannot be exercised in WinPE from a dev box, so this drives
  the real batch logic with pre-seeded diskpart output and asserts every branch, including refusal.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$payloadPath = Join-Path $repo 'payload/winpe/LaunchApply.cmd'
$body = Get-Content -LiteralPath $payloadPath -Raw -Encoding ascii

$lines = $body -split "\r?\n"
$start = [array]::IndexOf($lines, 'set WORK=%TEMP%\winmint')
$stop = [array]::IndexOf($lines, 'echo WinMint: erasing disk %TARGET%')
$sub = [array]::IndexOf($lines, ':winmint_pick')
if ($start -lt 0 -or $stop -le $start -or $sub -le $stop) { throw 'LaunchApply layout changed — update this test' }

$work = Join-Path $env:TEMP ('winmint-diskguard-' + [guid]::NewGuid().ToString('N'))
$usb = Join-Path $env:TEMP ('winmint-fake-usb-' + [guid]::NewGuid().ToString('N'))
$cmdPath = Join-Path $env:TEMP ('winmint-diskguard-' + [guid]::NewGuid().ToString('N') + '.cmd')

# Same decision logic, with the two diskpart reads pre-seeded. Nothing destructive is carried over.
$harness = @('@echo off', 'setlocal EnableExtensions', 'set INSTALL=Z') +
    ($lines[$start..$stop] | ForEach-Object {
        if ($_ -eq 'set WORK=%TEMP%\winmint') { "set WORK=$work" }
        elseif ($_ -match 'echo list disk \| diskpart') { 'rem pre-seeded' }
        else { $_ } }) +
    @('echo RESULT TARGET=%TARGET% EXTRA=%EXTRA%', 'exit /b 0', '') +
    ($lines[$sub..($lines.Length - 1)] | ForEach-Object {
        if ($_ -match '^\(echo select disk') { 'rem pre-seeded' } else { $_ } })

foreach ($danger in 'clean', 'Apply-Image', 'bcdboot', 'wpeutil', 'format') {
    if ($harness -match $danger) { throw "refusing to run: '$danger' leaked into the harness" }
}

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

# The guard only protects a wipe if the pre-wipe gate refuses media that lacks it. Patcher and gate
# both read servicing/WinPeApplyContract.ps1, so drive that contract directly — no DISM, no WinPE.
. (Join-Path $repo 'servicing/WinPeApplyContract.ps1')
$resolvedPayload = (Resolve-Path (Get-WinPeApplyPayloadPath)).Path
if ($resolvedPayload -cne (Resolve-Path $payloadPath).Path) {
    $failures += "repository payload resolution`n    expected: $payloadPath`n    actual:   $resolvedPayload"
}

$shipped = $body
$winpeshl = "[LaunchApps]`r`n%SYSTEMDRIVE%\Windows\System32\LaunchApply.cmd"
# Never executed — written to a fake mount and read back. Media looked like this before commit 114adc7.
$preGuard = @'
@echo off
call wpeinit
echo select disk 0 > "%TEMP%\dp.txt"
diskpart /s "%TEMP%\dp.txt"
dism /English /Apply-Image /ImageFile:D:\sources\install.wim /Index:1 /ApplyDir:W:\
'@
$mount = Join-Path $env:TEMP 'winmint-applycontract'

function Assert-Contract {
    param([string] $Name, [string] $Launch, [string] $Winpeshl, [string] $Expect)

    Remove-Item -LiteralPath $mount -Recurse -Force -ErrorAction SilentlyContinue
    $system32 = Join-Path $mount 'Windows\System32'
    New-Item -ItemType Directory -Force -Path $system32 | Out-Null
    if (-not [string]::IsNullOrEmpty($Launch)) {
        [IO.File]::WriteAllText(
            (Join-Path $system32 'LaunchApply.cmd'),
            $Launch,
            [Text.Encoding]::ASCII)
    }
    if (-not [string]::IsNullOrEmpty($Winpeshl)) {
        Set-Content -LiteralPath (Join-Path $system32 'winpeshl.ini') -Value $Winpeshl -Encoding ascii
    }

    $defects = Get-WinPeApplyDefect -MountDir $mount
    $actual = if ($defects.Count -eq 0) { 'none' } else { $defects -join '; ' }
    if ($actual -notmatch [regex]::Escape($Expect)) {
        $script:failures += "$Name`n    expected: $Expect`n    actual:   $actual"
    }
}

try {
    Assert-Contract 'shipped LaunchApply is apply media' $shipped $winpeshl 'none'
    Assert-Contract 'byte drift rejected' ($shipped + 'rem drift') $winpeshl 'bytes differ from authoritative payload'
    # The drift that mattered: pre-guard media satisfies /Index:1 and would erase disk 0 unattended.
    Assert-Contract 'pre-guard media rejected' $preGuard $winpeshl 'predates the target-disk guard'
    Assert-Contract 'source edition index rejected' ($shipped -replace '/Index:1', '/Index:3') $winpeshl 'wrong /Index:3'
    Assert-Contract 'missing launcher rejected' '' $winpeshl 'LaunchApply.cmd missing'
    Assert-Contract 'missing winpeshl rejected' $shipped '' 'winpeshl.ini missing'
    Assert-Contract 'winpeshl not launching apply rejected' $shipped '[LaunchApps]' 'must launch LaunchApply.cmd'
}
finally {
    Remove-Item -LiteralPath $mount -Recurse -Force -ErrorAction SilentlyContinue
}

$packagedRoot = Join-Path $env:TEMP "winmint-packaged-root-$([guid]::NewGuid().ToString('N'))"
try {
    New-Item -ItemType Directory -Force -Path `
        (Join-Path $packagedRoot 'servicing'), (Join-Path $packagedRoot 'payload\winpe') | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'servicing/WinPeApplyContract.ps1') `
        -Destination (Join-Path $packagedRoot 'servicing/WinPeApplyContract.ps1')
    Copy-Item -LiteralPath $payloadPath `
        -Destination (Join-Path $packagedRoot 'payload\winpe\LaunchApply.cmd')
    . (Join-Path $packagedRoot 'servicing/WinPeApplyContract.ps1')
    $expectedPackagedPayload = (Resolve-Path (Join-Path $packagedRoot 'payload\winpe\LaunchApply.cmd')).Path
    $resolvedPackagedPayload = (Resolve-Path (Get-WinPeApplyPayloadPath)).Path
    if ($resolvedPackagedPayload -cne $expectedPackagedPayload) {
        $failures += "packaged payload resolution`n    expected: $expectedPackagedPayload`n    actual:   $resolvedPackagedPayload"
    }
}
finally {
    Remove-Item -LiteralPath $packagedRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$missingPayloadRoot = Join-Path $env:TEMP "winmint-missing-payload-$([guid]::NewGuid().ToString('N'))"
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $missingPayloadRoot 'servicing') | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'servicing/WinPeApplyContract.ps1') `
        -Destination (Join-Path $missingPayloadRoot 'servicing/WinPeApplyContract.ps1')
    . (Join-Path $missingPayloadRoot 'servicing/WinPeApplyContract.ps1')
    Assert-Contract `
        'missing authoritative payload returns a defect' `
        $shipped `
        $winpeshl `
        'authoritative payload/winpe/LaunchApply.cmd missing'
}
finally {
    Remove-Item -LiteralPath $missingPayloadRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Output "Disk guard contract FAILED:`n$($failures -join "`n")"
    exit 1
}

Write-Output 'Disk guard contract tests passed.'
exit 0
