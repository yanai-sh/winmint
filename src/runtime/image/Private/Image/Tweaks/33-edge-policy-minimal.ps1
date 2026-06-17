#Requires -Version 7.6

# Baseline Edge noise reduction (Tier 1 apply-by-default). Reduces promotional,
# commerce, telemetry, widget, inline compose, startup/background, new-tab
# content, and game-assist surfaces. (Audit: decoupled from the privacy toggles
# it was previously gated on - Edge cleanup is its own concern.) Keep the Edge
# sidebar available because Copilot page-context chat is a useful explicit
# browser feature, not background OS bloat.

Add-WinMintRegistryTweakModule @{
    id = 'edge-policy-minimal'
    description = 'Edge Minimal cleanup (noise/privacy, commerce, widgets, image enhancement, inline compose, startup/background, new tab)'
    scope = 'machine policy registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Reduce Edge promotional, commerce, telemetry, and inline compose noise for all builds while keeping explicit Copilot page-context chat available.'
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
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'AllowGamesMenu'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'ComposeInlineEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
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

