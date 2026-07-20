#Requires -Version 7.6

# Baseline (every build, unconditional): add "End Task" to the taskbar app
# right-click menu — the Windows 11 developer setting (Settings > System > For
# developers). Per-user value written into the default-user hive so every new
# account gets it. Off in stock Windows; rollback deletes the value.

Add-WinMintRegistryTweakModule @{
    id = 'taskbar-endtask'
    description = 'Enable End Task on the taskbar app right-click menu'
    scope = 'default user registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Always expose End Task on the taskbar right-click menu on every build, matching developer/power-user expectations.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings'; name = 'TaskbarEndTask'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } }
    )
    remove = @()
}

