#Requires -Version 7.3

# Applied when gaming-apps removal is on (default; i.e. NOT a Gaming build).
# Suppresses the Game Bar capture prompt, GameDVR recording defaults, and
# post-removal Store prompts from ms-gamebar protocol activations.

Add-WinMintRegistryTweakModule @{
    id = 'gamebar-policy'
    description = 'Disable Xbox Game Bar / GameDVR prompts and no-op Game Bar protocols'
    scope = 'machine and default user registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Suppress Game Bar capture prompts, GameDVR recording defaults, and Store prompts caused by ms-gamebar protocol activations after Game Bar removal.'
    appliesTo = { param($ctx) -not [bool]$ctx.KeepGaming }
    set = @(
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\GameDVR'; name = 'AllowGameDVR'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Classes\ms-gamebar'; name = ''; type = 'REG_SZ'; value = 'URL:ms-gamebar'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Classes\ms-gamebar'; name = 'URL Protocol'; type = 'REG_SZ'; value = ''; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Classes\ms-gamebar'; name = 'NoOpenWith'; type = 'REG_SZ'; value = ''; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Classes\ms-gamebar\shell\open\command'; name = ''; type = 'REG_EXPAND_SZ'; value = '"%SystemRoot%\System32\systray.exe"'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Classes\ms-gamebarservices'; name = ''; type = 'REG_SZ'; value = 'URL:ms-gamebarservices'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Classes\ms-gamebarservices'; name = 'URL Protocol'; type = 'REG_SZ'; value = ''; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Classes\ms-gamebarservices'; name = 'NoOpenWith'; type = 'REG_SZ'; value = ''; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Classes\ms-gamebarservices\shell\open\command'; name = ''; type = 'REG_EXPAND_SZ'; value = '"%SystemRoot%\System32\systray.exe"'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR'; name = 'AppCaptureEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ type = 'REG_DWORD'; value = '1' } },
        @{ path = 'zNTUSER\System\GameConfigStore'; name = 'GameDVR_Enabled'; type = 'REG_DWORD'; value = '0'; undo = @{ type = 'REG_DWORD'; value = '1' } }
    )
    remove = @()
}
