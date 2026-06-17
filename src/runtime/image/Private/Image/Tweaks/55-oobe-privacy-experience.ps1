#Requires -Version 7.6

# Baseline: skip the interactive Windows 11 OOBE "Choose privacy settings for your
# device" page. WinMint already configures telemetry, advertising ID, location,
# and tailored-experience posture through its own privacy policy (and FirstLogon
# restores the user-configured location), so the OOBE privacy page is redundant
# and only adds clicks. DisablePrivacyExperience suppresses the page and applies
# privacy-off defaults, which WinMint's own policy then governs.
#
# Combined with the local account, hidden EULA/account screens, and the
# International-Core block in the oobeSystem pass (which suppresses the
# region/keyboard pages), this leaves the network page as the only OOBE screen
# the user might see — and Windows shows that one only when there is no existing
# connection, so Wi-Fi is still prompted exactly when needed.

Add-WinMintRegistryTweakModule @{
    id = 'oobe-privacy-experience'
    description = 'Skip the OOBE privacy-settings page'
    scope = 'machine registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Suppress the redundant OOBE privacy-settings page so an otherwise-unattended install does not stop for it; WinMint privacy policy remains authoritative.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\OOBE'; name = 'DisablePrivacyExperience'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } }
    )
}

