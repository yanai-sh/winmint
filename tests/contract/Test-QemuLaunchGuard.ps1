#requires -Version 7.6
# The Windows Hypervisor Platform must not be selected. Starting it on Snapdragon
# bugchecks the host (CLOCK_WATCHDOG_TIMEOUT, 0x101) and writes no dump.
# This contract does not execute QEMU.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools\usb\Assert-QemuLaunch.ps1')

$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Refused([string] $Label, [string[]] $Argument) {
    $threw = $false
    try {
        Assert-WinMintQemuLaunch -Argument $Argument
    }
    catch {
        $threw = $true
        if ($_.Exception.Message -notmatch 'CLOCK_WATCHDOG_TIMEOUT') {
            $script:failures.Add("$Label refused without naming CLOCK_WATCHDOG_TIMEOUT: $($_.Exception.Message)")
        }
    }
    if (-not $threw) { $script:failures.Add("$Label was allowed") }
}

# The argv that bugchecked this host: a WHPX virt machine, a CPU, and no firmware.
Assert-Refused 'empty WHPX machine' @(
    '-machine', 'virt,accel=whpx',
    '-cpu', 'host',
    '-display', 'none'
)
Assert-Refused 'split -accel whpx' @('-machine', 'virt', '-accel', 'whpx', '-cpu', 'host')
Assert-Refused 'whpx with pflash' @(
    '-machine', 'virt',
    '-accel', 'whpx',
    '-drive', 'if=pflash,format=raw,readonly=on,file=AAVMF_CODE.fd'
)

try {
    Assert-WinMintQemuLaunch -Argument @(
        '-machine', 'virt',
        '-accel', 'tcg',
        '-cpu', 'max',
        '-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=AAVMF_CODE.fd'
    )
}
catch {
    $failures.Add("TCG firmware probe was refused: $($_.Exception.Message)")
}

$probe = Get-Content -LiteralPath (Join-Path $repo 'tools\usb\Invoke-QemuUsbBootProbe.ps1') -Raw -Encoding utf8
$guardAt = $probe.IndexOf('Assert-WinMintQemuLaunch -Argument $arguments', [StringComparison]::Ordinal)
$startAt = $probe.IndexOf('$process.Start()', [StringComparison]::Ordinal)
if ($guardAt -lt 0 -or $startAt -lt 0 -or $guardAt -gt $startAt) {
    $failures.Add('USB QEMU probe must refuse the launch before Process.Start')
}
if ($probe -notmatch "(?s)'-accel',\s*'tcg'") {
    $failures.Add('USB QEMU probe must select the software emulator')
}
if ($probe -match '(?i)accel=whpx|-accel\s+whpx|-accel'',\s*''whpx''') {
    $failures.Add('USB QEMU probe selects the Windows Hypervisor Platform')
}

$files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($root in @('tools', 'servicing', 'src')) {
    Get-ChildItem -LiteralPath (Join-Path $repo $root) -Recurse -File -Include *.ps1, *.cs |
        Where-Object { $_.Name -ne 'Assert-QemuLaunch.ps1' } |
        ForEach-Object { $files.Add($_) }
}
$justfile = Get-Item -LiteralPath (Join-Path $repo 'Justfile')
$files.Add($justfile)
$hits = @($files | Select-String -Pattern '(?i)accel=whpx|-accel\s+whpx|-accel'',\s*''whpx''' -List)
foreach ($hit in $hits) {
    $failures.Add("WHPX accelerator selected in $($hit.Path):$($hit.LineNumber)")
}

if ($failures.Count -gt 0) {
    throw "QEMU launch guard failed:`n$($failures -join "`n")"
}

Write-Output 'Test-QemuLaunchGuard ok'
exit 0
