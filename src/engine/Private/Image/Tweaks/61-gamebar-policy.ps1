#Requires -Version 7.3

# Applied when gaming-apps removal is on (default; i.e. NOT a Gaming build).
# Suppresses the Game Bar capture prompt and GameDVR recording defaults.

Add-WinMintRegistryTweakModule @{
    id = 'gamebar-policy'
    description = 'Disable Xbox Game Bar / GameDVR overlay popup on controller connect'
    scope = 'machine and default user registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Suppress Game Bar capture prompts and GameDVR recording defaults.'
    appliesTo = { param($ctx) [bool]$ctx.RemoveGaming }
    set = @(
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\GameDVR'; name = 'AllowGameDVR'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR'; name = 'AppCaptureEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ type = 'REG_DWORD'; value = '1' } },
        @{ path = 'zNTUSER\System\GameConfigStore'; name = 'GameDVR_Enabled'; type = 'REG_DWORD'; value = '0'; undo = @{ type = 'REG_DWORD'; value = '1' } }
    )
    remove = @()
}
