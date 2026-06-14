#Requires -Version 7.3

# Start menu cleanup (apply-by-default). Hides the "Recommended" section - the seeded
# "Get Started"/tips/recent entries a stock Windows 11 Start menu shows - and ships a
# clean pinned-apps layout that replaces the default promotional pins (Store, Edge,
# bundled apps) with a minimal set (File Explorer, Settings, Terminal). Both are the
# documented Group Policy ADMX values; honoring on Home edition is not guaranteed, so
# verify on the build. Per-user Start tweaks (Start_IrisRecommendations, Start_TrackDocs,
# TaskbarDa) live in DefaultUser.ps1.

Add-WinMintRegistryTweakModule @{
    id = 'start-recommended-cleanup'
    description = 'Start menu: hide Recommended section and ship a clean pinned-apps layout'
    scope = 'machine policy registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Remove seeded Start recommendations and strip default promotional pins, leaving a minimal pin set.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\Explorer'; name = 'HideRecommendedSection'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{
            path = 'zSOFTWARE\Policies\Microsoft\Windows\Explorer'
            name = 'ConfigureStartPins'
            type = 'REG_SZ'
            value = '{"pinnedList":[{"desktopAppId":"Microsoft.Windows.Explorer"},{"packagedAppId":"windows.immutablecontrolpanel"},{"packagedAppId":"Microsoft.WindowsTerminal_8wekyb3d8bbwe!App"}]}'
            undo = @{ action = 'delete' }
        }
    )
    remove = @()
}
