#Requires -Version 7.3

# Baseline Explorer quality-of-life: show file extensions and hidden files,
# keep Explorer Home as the launch page, and remove Gallery namespace noise.
# (Formerly 'developer-qol'; renamed because it applies to every build, not just
# Developer profiles, and only governs Explorer visibility defaults.)

Add-WinMintRegistryTweakModule @{
    id = 'explorer-qol'
    description = 'Explorer QoL (extensions, hidden files, Gallery hidden)'
    scope = 'default user registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Make Explorer friendlier by exposing file extensions and hidden files, keeping Home as the launch page, and hiding Gallery on every build.'
    appliesTo = { param($ctx) [bool]$ctx.TweakFileExtensions }
    set = @(
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'HideFileExt'; type = 'REG_DWORD'; value = '0'; undo = @{ type = 'REG_DWORD'; value = '1' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'Hidden'; type = 'REG_DWORD'; value = '1'; undo = @{ type = 'REG_DWORD'; value = '2' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'LaunchTo'; type = 'REG_DWORD'; value = '2'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}'; name = 'System.IsPinnedToNameSpaceTree'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } }
    )
    remove = @()
}
