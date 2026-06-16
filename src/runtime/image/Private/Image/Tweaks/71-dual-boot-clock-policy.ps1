#Requires -Version 7.6

# DualBootReserved disk mode only: keep the RTC in UTC (RealTimeIsUniversal) to
# avoid clock drift against a Linux install on the same machine.

Add-WinMintRegistryTweakModule @{
    id = 'dual-boot-clock-policy'
    description = 'Dual boot: keep RTC in UTC'
    scope = 'offline registry'; risk = 'medium'; reversible = $true; phase = 'offline-image'
    intent = 'Set RealTimeIsUniversal only for dual-boot builds to avoid clock drift with Linux.'
    appliesTo = { param($ctx) [string]$ctx.DiskMode -eq 'DualBootReserved' }
    set = @(
        @{ path = 'zSYSTEM\ControlSet001\Control\TimeZoneInformation'; name = 'RealTimeIsUniversal'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } }
    )
    remove = @()
}

