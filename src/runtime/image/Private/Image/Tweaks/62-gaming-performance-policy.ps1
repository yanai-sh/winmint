#Requires -Version 7.6

# Baseline laptop gaming perf (Game Mode, HAGS, windowed-game prefs). Independent of
# keep.gaming, which only controls Xbox/Game Bar AppX retention and gamebar-policy.

Add-WinMintRegistryTweakModule @{
    id = 'gaming-performance-policy'
    description = 'Gaming profile performance defaults'
    scope = 'machine and default user registry'; risk = 'medium'; reversible = $true; phase = 'offline-image'
    intent = 'Enable Game Mode, hardware-accelerated GPU scheduling, and windowed-game optimizations as WinMint baseline (independent of keep.gaming).'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zNTUSER\Software\Microsoft\GameBar'; name = 'AllowAutoGameMode'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\GameBar'; name = 'AutoGameModeEnabled'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSYSTEM\ControlSet001\Control\GraphicsDrivers'; name = 'HwSchMode'; type = 'REG_DWORD'; value = '2'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\DirectX\UserGpuPreferences'; name = 'DirectXUserGlobalSettings'; type = 'REG_SZ'; value = 'SwapEffectUpgradeEnable=1;'; undo = @{ action = 'delete' } }
    )
    remove = @()
}

