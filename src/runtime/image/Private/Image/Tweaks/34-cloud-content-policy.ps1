#Requires -Version 7.6

# Enterprise/Education CloudContent policies (best-effort). On Windows 11 Home the
# Home-effective quiet UX source of truth is ContentDeliveryManager + FirstLogon
# Set-WinMintFirstLogonQuietUxDefaults (DefaultUser hive + live HKCU), not these
# CloudContent stamps. Keep this tweak for Pro/Enterprise/OEM images that honor
# the policy path; do not treat CloudContent alone as Home quiet UX.

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

