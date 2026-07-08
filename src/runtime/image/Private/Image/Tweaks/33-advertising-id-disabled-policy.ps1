#Requires -Version 7.6

Add-WinMintRegistryTweakModule @{
    id = 'advertising-id-disabled-policy'
    description = 'Disable the Windows advertising ID for the default user profile'
    scope = 'default user registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Keep the advertising ID off unless the profile explicitly opts in to enabled.'
    appliesTo = { param($ctx) [bool]$ctx.PrivacyAdvertisingIdDisabled }
    set = @(
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; name = 'Enabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } }
    )
    remove = @()
}
