#Requires -Version 7.6

# DualBootReserved disk mode only: disable Fast Startup (HiberbootEnabled) and
# prevent automatic BitLocker device encryption, both of which cause dual-boot
# friction. Does not touch an already-active BitLocker volume.

Add-WinMintRegistryTweakModule @{
    id = 'dual-boot-windows-policy'
    description = 'Dual boot: disable Fast Startup and prevent automatic BitLocker device encryption'
    scope = 'offline registry'; risk = 'medium'; reversible = $true; phase = 'offline-image'
    intent = 'Avoid dual-boot friction from Fast Startup and surprise device encryption.'
    appliesTo = { param($ctx) [string]$ctx.DiskMode -eq 'DualBootReserved' }
    set = @(
        @{ path = 'zSYSTEM\ControlSet001\Control\BitLocker'; name = 'PreventDeviceEncryption'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSYSTEM\ControlSet001\Control\Session Manager\Power'; name = 'HiberbootEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ type = 'REG_DWORD'; value = '1' } }
    )
    remove = @()
}

