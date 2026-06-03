#Requires -Version 7.3

# Baseline Explorer quality-of-life: show file extensions and hidden files.
# (Formerly 'developer-qol'; renamed because it applies to every build, not just
# Developer profiles, and only governs Explorer visibility defaults.)

Add-WinMintRegistryTweakModule @{
    id = 'explorer-qol'
    description = 'Explorer QoL (file extensions and hidden files)'
    scope = 'default user registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Make Explorer friendlier by exposing file extensions and hidden files on every build.'
    appliesTo = { param($ctx) [bool]$ctx.TweakFileExtensions }
    set = @(
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'HideFileExt'; type = 'REG_DWORD'; value = '0'; undo = @{ type = 'REG_DWORD'; value = '1' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'Hidden'; type = 'REG_DWORD'; value = '1'; undo = @{ type = 'REG_DWORD'; value = '2' } }
    )
    remove = @()
}
