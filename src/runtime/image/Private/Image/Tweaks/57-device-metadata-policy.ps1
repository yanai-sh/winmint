#Requires -Version 7.6

# Baseline device hygiene: stop Windows from fetching device metadata packages
# (companion-app prompts / branded icons) over the network when hardware is
# plugged in. Complements driver-coinstaller-policy; Windows Update driver
# delivery stays enabled.

Add-WinMintRegistryTweakModule @{
    id = 'device-metadata-policy'
    description = 'Prevent device metadata retrieval from the network'
    scope = 'machine policy registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Block network device-metadata and companion-app prompts when plugging in hardware while preserving Windows Update driver delivery.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\Device Metadata'; name = 'PreventDeviceMetadataFromNetwork'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } }
    )
    remove = @()
}
