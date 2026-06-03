#Requires -Version 7.3

# Developer group: add an elevated "Open Terminal Here as Administrator" entry to
# directory and directory-background context menus. Moved off the Minimal baseline
# (audit: an elevated-terminal context menu is a power-user feature, not a clean
# baseline item).

$script:Win11IsoOpenAdminTerminalCommand =
    'pwsh.exe -WindowStyle Hidden -Command "Start-Process cmd.exe -ArgumentList ''/c cd /d `\"%V`\" ^&^& start wt.exe'' -Verb RunAs"'

Add-WinMintRegistryTweakModule @{
    id = 'terminal-admin-context'
    description = 'Open Terminal Here as Administrator Context Menu'
    scope = 'offline registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Add a fast elevated terminal entry to directory context menus for developer workstations.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSOFTWARE\Classes\Directory\shell\OpenWTHereAsAdmin'; name = 'MUIVerb'; type = 'REG_SZ'; value = 'Open Terminal Here as Administrator'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Classes\Directory\shell\OpenWTHereAsAdmin'; name = 'Icon'; type = 'REG_SZ'; value = 'wt.exe'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Classes\Directory\shell\OpenWTHereAsAdmin'; name = 'HasLUAShield'; type = 'REG_SZ'; value = ''; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Classes\Directory\shell\OpenWTHereAsAdmin\command'; name = ''; type = 'REG_SZ'; value = $script:Win11IsoOpenAdminTerminalCommand; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Classes\Directory\Background\shell\OpenWTHereAsAdmin'; name = 'MUIVerb'; type = 'REG_SZ'; value = 'Open Terminal Here as Administrator'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Classes\Directory\Background\shell\OpenWTHereAsAdmin'; name = 'Icon'; type = 'REG_SZ'; value = 'wt.exe'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Classes\Directory\Background\shell\OpenWTHereAsAdmin'; name = 'HasLUAShield'; type = 'REG_SZ'; value = ''; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Classes\Directory\Background\shell\OpenWTHereAsAdmin\command'; name = ''; type = 'REG_SZ'; value = $script:Win11IsoOpenAdminTerminalCommand; undo = @{ action = 'delete' } }
    )
    remove = @()
}
