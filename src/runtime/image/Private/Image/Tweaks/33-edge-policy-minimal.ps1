#Requires -Version 7.3

# Baseline Edge noise reduction (Tier 1 apply-by-default). Reduces promotional,
# commerce, telemetry, widget, sidebar, startup/background, new-tab content, and
# game-assist surfaces. (Audit: decoupled from the privacy toggles it was
# previously gated on - Edge cleanup is its own concern.)

Add-WinMintRegistryTweakModule @{
    id = 'edge-policy-minimal'
    description = 'Edge Minimal cleanup (noise/privacy, commerce, widgets, image enhancement, sidebar, startup/background, new tab)'
    scope = 'machine policy registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Reduce Edge promotional, commerce, telemetry, and sidebar noise for all builds.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSOFTWARE\Policies\Microsoft\EdgeUpdate'; name = 'CreateDesktopShortcutDefault'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'EdgeEnhanceImagesEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'PersonalizationReportingEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'ShowRecommendationsEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'HideFirstRunExperience'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'BackgroundModeEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'StartupBoostEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'NewTabPageContentEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'UserFeedbackAllowed'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'ConfigureDoNotTrack'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'AlternateErrorPagesEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'EdgeCollectionsEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'EdgeFollowEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'EdgeShoppingAssistantEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        # Game Assist ships as the Microsoft.Edge.GameAssist MSIX that Edge's component
        # updater rehydrates per-user AFTER first logon, so offline appx removal alone does
        # not hold (the live audit caught it reappearing). Microsoft documents NO policy to
        # prevent the install (only post-hoc Remove-AppxPackage, which recurs on Edge update).
        # These two documented policies disable its user-facing entry points - the games menu
        # and the hubs sidebar it surfaces in - which is the supported lever available.
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'AllowGamesMenu'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'HubsSidebarEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'MicrosoftEdgeInsiderPromotionEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'ShowMicrosoftRewards'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'WebWidgetAllowed'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'DiagnosticData'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'EdgeAssetDeliveryServiceEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'CryptoWalletEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'WalletDonationEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge\ExtensionInstallBlocklist'; name = '1'; type = 'REG_SZ'; value = 'ofefcgjbeghpigppfmkologfjadafddi'; undo = @{ action = 'delete' } }
    )
    remove = @()
}
