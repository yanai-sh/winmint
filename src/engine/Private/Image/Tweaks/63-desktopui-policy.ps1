#Requires -Version 7.3

# DesktopUI group only: single-click activation and snap-assist behavior, without
# affecting Minimal or Gaming builds.

Add-WinMintRegistryTweakModule @{
    id = 'desktopui-policy'
    description = 'DesktopUI profile Explorer and snap behavior'
    scope = 'default user registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Apply DesktopUI-only shell preference defaults without affecting Minimal or Gaming builds.'
    appliesTo = { param($ctx) @($ctx.ProfileGroups) -contains 'DesktopUI' }
    set = @(
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'LastActiveClick'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'SnapAssist'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'EnableSnapBar'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'EnableSnapAssistFlyout'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } }
    )
    remove = @()
}
