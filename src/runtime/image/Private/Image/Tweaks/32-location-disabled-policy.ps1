#Requires -Version 7.6

# Explicit opt-out only (privacy.location = false / -NoLocationServices). Default
# laptop-first builds keep location and Find My Device available.

Add-WinMintRegistryTweakModule @{
    id = 'location-disabled-policy'
    description = 'Disable Windows location services and Find My Device when explicitly selected'
    scope = 'machine policy registry'; risk = 'medium'; reversible = $true; phase = 'offline-image'
    intent = 'Apply the explicit no-location posture; default laptop-first builds leave location and Find My Device available.'
    appliesTo = { param($ctx) -not [bool]$ctx.PrivacyLocation }
    set = @(
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'; name = 'DisableLocation'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'; name = 'DisableWindowsLocationProvider'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'; name = 'DisableLocationScripting'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\FindMyDevice'; name = 'AllowFindMyDevice'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } }
    )
    remove = @()
}

