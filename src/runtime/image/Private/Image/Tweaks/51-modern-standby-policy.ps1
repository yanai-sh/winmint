#Requires -Version 7.3

# Baseline laptop-friendly Modern Standby: disconnect network during standby on
# both AC and DC to avoid background battery drain. Does not disable sleep.

Add-WinMintRegistryTweakModule @{
    id = 'modern-standby-policy'
    description = 'Modern Standby network disconnected by default'
    scope = 'machine policy registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Use laptop-friendly Modern Standby behavior that avoids background network drain on AC and DC.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9'; name = 'ACSettingIndex'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9'; name = 'DCSettingIndex'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } }
    )
    remove = @()
}
