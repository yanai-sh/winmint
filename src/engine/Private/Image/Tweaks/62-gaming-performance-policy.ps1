#Requires -Version 7.3

# Gaming group only: Game Mode, hardware-accelerated GPU scheduling (HAGS), and
# windowed-game (swapchain) optimizations.

Add-WinMintRegistryTweakModule @{
    id = 'gaming-performance-policy'
    description = 'Gaming profile performance defaults'
    scope = 'machine and default user registry'; risk = 'medium'; reversible = $true; phase = 'offline-image'
    intent = 'Enable Game Mode, hardware-accelerated GPU scheduling, and windowed-game optimizations only for Gaming builds.'
    appliesTo = { param($ctx) [bool]$ctx.KeepGaming }
    set = @(
        @{ path = 'zNTUSER\Software\Microsoft\GameBar'; name = 'AllowAutoGameMode'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\GameBar'; name = 'AutoGameModeEnabled'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSYSTEM\ControlSet001\Control\GraphicsDrivers'; name = 'HwSchMode'; type = 'REG_DWORD'; value = '2'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\DirectX\UserGpuPreferences'; name = 'DirectXUserGlobalSettings'; type = 'REG_SZ'; value = 'SwapEffectUpgradeEnable=1;'; undo = @{ action = 'delete' } }
    )
    remove = @()
}
