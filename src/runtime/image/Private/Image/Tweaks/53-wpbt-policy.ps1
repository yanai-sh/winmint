#Requires -Version 7.6

# Baseline: disable Windows Platform Binary Table execution so firmware-staged OEM
# executables do not run during Windows setup.

Add-WinMintRegistryTweakModule @{
    id = 'wpbt-policy'
    description = 'Disable Windows Platform Binary Table execution'
    scope = 'offline registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Prevent firmware-staged OEM executables from running during Windows setup on all Minimal builds.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSYSTEM\ControlSet001\Control\Session Manager'; name = 'DisableWpbtExecution'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } }
    )
    remove = @()
}

