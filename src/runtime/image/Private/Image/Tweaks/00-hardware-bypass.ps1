#Requires -Version 7.6

# Opt-in only: never part of a default build. Lets Windows Setup proceed on
# explicitly selected unsupported hardware (TPM 2.0 / Secure Boot / CPU / RAM / Storage).

Add-WinMintRegistryTweakModule @{
    id = 'hardware-bypass'
    description = 'Hardware compatibility bypass (TPM 2.0 / Secure Boot / CPU / RAM / Storage)'
    scope = 'offline registry'; risk = 'medium'; reversible = $true; phase = 'offline-image'
    intent = 'Allow Windows Setup to proceed on explicitly selected unsupported hardware.'
    appliesTo = { param($ctx) [bool]$ctx.TweakHardwareBypass }
    set = @(
        @{ path = 'zSYSTEM\Setup\MoSetup';   name = 'AllowUpgradesWithUnsupportedTPMOrCPU'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSYSTEM\Setup\LabConfig'; name = 'BypassTPMCheck';         type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSYSTEM\Setup\LabConfig'; name = 'BypassSecureBootCheck';  type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSYSTEM\Setup\LabConfig'; name = 'BypassCPUCheck';         type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSYSTEM\Setup\LabConfig'; name = 'BypassRAMCheck';         type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSYSTEM\Setup\LabConfig'; name = 'BypassStorageCheck';     type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } }
    )
    remove = @()
}

