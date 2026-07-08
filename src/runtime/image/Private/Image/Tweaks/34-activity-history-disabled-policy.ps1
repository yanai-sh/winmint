#Requires -Version 7.6

Add-WinMintRegistryTweakModule @{
    id = 'activity-history-disabled-policy'
    description = 'Disable activity history upload and feed publishing'
    scope = 'machine policy registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Keep activity history disabled unless the profile explicitly opts in to enabled.'
    appliesTo = { param($ctx) [bool]$ctx.PrivacyActivityHistoryDisabled }
    set = @(
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\System'; name = 'EnableActivityFeed'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\System'; name = 'PublishUserActivities'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\System'; name = 'UploadUserActivities'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } }
    )
    remove = @()
}
