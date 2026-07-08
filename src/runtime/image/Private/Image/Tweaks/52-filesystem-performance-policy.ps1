#Requires -Version 7.6

# Baseline NTFS hygiene for modern SSDs: disable last-access timestamp updates
# and legacy 8.3 short-name generation. Undo values restore the Windows defaults
# (system-managed last-access, 8.3 per-volume).

Add-WinMintRegistryTweakModule @{
    id = 'filesystem-performance-policy'
    description = 'NTFS hygiene: disable last-access updates and 8.3 short-name creation'
    scope = 'offline registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Reduce NTFS metadata write overhead by disabling last-access timestamps and legacy 8.3 short-name generation, matching modern SSD-oriented defaults.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSYSTEM\ControlSet001\Control\FileSystem'; name = 'NtfsDisableLastAccessUpdate'; type = 'REG_DWORD'; value = '1'; undo = @{ type = 'REG_DWORD'; value = '2147483649' } },
        @{ path = 'zSYSTEM\ControlSet001\Control\FileSystem'; name = 'NtfsDisable8dot3NameCreation'; type = 'REG_DWORD'; value = '1'; undo = @{ type = 'REG_DWORD'; value = '2' } }
    )
    remove = @()
}

