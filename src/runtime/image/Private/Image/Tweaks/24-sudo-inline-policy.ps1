#Requires -Version 7.6

# Developer group: enable Windows Sudo in Inline mode.

Add-WinMintRegistryTweakModule @{
    id = 'sudo-inline-policy'
    description = 'Enable Windows Sudo in Inline mode.'
    scope = 'machine registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Enable Windows Sudo in Inline mode for developer workstations.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\Sudo'; name = 'Enabled'; type = 'REG_DWORD'; value = '3'; undo = @{ type = 'REG_DWORD'; value = '0' } }
    )
    remove = @()
}
