#Requires -Version 7.3

# Best-effort Cloud Content / Experience policy layer. Several of these policies
# are formally scoped to Enterprise/Education, but stamping the documented policy
# values is harmless on Home and useful on SKUs/OEM images where Windows honors
# them. Default-user ContentDeliveryManager values are still stamped separately
# during setup as the Home-visible fallback.

Add-WinMintRegistryTweakModule @{
    id = 'cloud-content-policy'
    description = 'Disable cloud-backed Windows consumer content, Spotlight tips, Share Sheet promotions, and fallback suggestion surfaces.'
    scope = 'machine and default user policy registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Reduce Microsoft cloud recommendations, consumer-account content, welcome/tips surfaces, and promotional app suggestions without disabling Store, winget, or Windows Update.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\CloudContent'; name = 'DisableCloudOptimizedContent'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\CloudContent'; name = 'DisableConsumerAccountStateContent'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\CloudContent'; name = 'DisableSoftLanding'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\CloudContent'; name = 'DisableWindowsConsumerFeatures'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\CloudContent'; name = 'DisableWindowsSpotlightFeatures'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\CloudContent'; name = 'DisableWindowsSpotlightOnActionCenter'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\CloudContent'; name = 'DisableWindowsSpotlightOnSettings'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\CloudContent'; name = 'DisableWindowsSpotlightWindowsWelcomeExperience'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\CloudContent'; name = 'DisableShareAppPromotions'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\CloudContent'; name = 'DisableInlineCompose'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Policies\Microsoft\Windows\CloudContent'; name = 'DisableWindowsSpotlightFeatures'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Policies\Microsoft\Windows\CloudContent'; name = 'DisableWindowsSpotlightOnActionCenter'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Policies\Microsoft\Windows\CloudContent'; name = 'DisableWindowsSpotlightOnSettings'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Policies\Microsoft\Windows\CloudContent'; name = 'DisableWindowsSpotlightWindowsWelcomeExperience'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } }
    )
    remove = @()
}
