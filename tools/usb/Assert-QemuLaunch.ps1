#requires -Version 7.6
# Refuse a QEMU argv that would enter the Windows Hypervisor Platform.
# On Snapdragon that call does not return and the host bugchecks 0x101.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-WinMintQemuSelectsWhpx {
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Argument)

    for ($i = 0; $i -lt $Argument.Count; $i++) {
        $token = $Argument[$i]
        if ($token -match '(?i)(?:^|,)accel=whpx(?:$|,)') { return $true }
        if ($token -match '(?i)^-accel(?:=whpx)$') { return $true }
        if ($token -match '(?i)^-accel$' -and ($i + 1) -lt $Argument.Count -and $Argument[$i + 1] -match '(?i)^whpx$') {
            return $true
        }
    }
    return $false
}

function Assert-WinMintQemuLaunch {
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Argument)

    if (Test-WinMintQemuSelectsWhpx -Argument $Argument) {
        throw 'QEMU launch refused: the Windows Hypervisor Platform accelerator calls WHvRunVirtualProcessor. On Snapdragon that hypercall does not return and the host bugchecks CLOCK_WATCHDOG_TIMEOUT (0x101).'
    }
}
