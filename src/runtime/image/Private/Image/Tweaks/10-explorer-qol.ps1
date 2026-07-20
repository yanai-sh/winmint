#Requires -Version 7.6

# Baseline Explorer quality-of-life: show file extensions and hidden files,
# keep Explorer Home as the launch page, show full path in the title bar,
# quiet Quick Access (frequent/recent/cloud), mute sync-provider tip balloons,
# enable File Explorer Git version-control surface (user still registers repo
# folders under Settings > System > Advanced), and remove Gallery namespace noise.
# (Formerly 'developer-qol'; renamed because it applies to every build, not just
# Developer profiles, and only governs Explorer visibility defaults.)

Add-WinMintRegistryTweakModule @{
    id = 'explorer-qol'
    description = 'Explorer QoL (extensions, hidden files, Home, full path, quiet Quick Access, Git FE toggle, Gallery hidden)'
    scope = 'default user registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Make Explorer friendlier by exposing file extensions and hidden files, keeping Home as the launch page, showing the full path, quieting Quick Access/cloud tips, enabling the Git version-control Explorer surface, and hiding Gallery on every build.'
    appliesTo = { param($ctx) [bool]$ctx.TweakFileExtensions }
    set = @(
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'HideFileExt'; type = 'REG_DWORD'; value = '0'; undo = @{ type = 'REG_DWORD'; value = '1' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'Hidden'; type = 'REG_DWORD'; value = '1'; undo = @{ type = 'REG_DWORD'; value = '2' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'LaunchTo'; type = 'REG_DWORD'; value = '2'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'FullPathAddress'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'ShowFrequent'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'ShowSyncProviderNotifications'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'NavPaneShowVersionControl'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer'; name = 'ShowRecent'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer'; name = 'ShowCloudFilesInQuickAccess'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}'; name = 'System.IsPinnedToNameSpaceTree'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } }
    )
    remove = @()
}

