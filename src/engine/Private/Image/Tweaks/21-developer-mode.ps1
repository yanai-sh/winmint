#Requires -Version 7.3

# Developer group: enable Windows Developer Mode (symlinks without UAC elevation,
# app sideloading) expected by developer workstations.

Add-WinMintRegistryTweakModule @{
    id = 'developer-mode'
    description = 'Windows Developer Mode (symlinks without UAC elevation, app sideloading)'
    scope = 'machine registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Enable Windows Developer Mode features expected by developer workstations.'
    appliesTo = { param($ctx) [bool]$ctx.EnableDeveloperGroup }
    set = @(
        @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'; name = 'AllowAllTrustedApps';              type = 'REG_DWORD'; value = '1'; undo = @{ type = 'REG_DWORD'; value = '0' } },
        @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'; name = 'AllowDevelopmentWithoutDevLicense'; type = 'REG_DWORD'; value = '1'; undo = @{ type = 'REG_DWORD'; value = '0' } }
    )
    remove = @()
}
