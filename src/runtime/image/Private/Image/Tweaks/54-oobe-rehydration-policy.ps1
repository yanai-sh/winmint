#Requires -Version 7.6

# Baseline: suppress Dev Home / Outlook / Chat OOBE auto-install rehydration jobs
# by marking the orchestrator work complete and removing the OOBE scheduler keys.
# Does NOT disable Windows Update.

Add-WinMintRegistryTweakModule @{
    id = 'oobe-rehydration-policy'
    description = 'Block selected OOBE app rehydration jobs'
    scope = 'machine registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Prevent Dev Home, Outlook, and Chat auto-install rehydration after setup without disabling Windows Update.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate'; name = 'workCompleted'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate'; name = 'workCompleted'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\ChatAutoInstall'; name = 'workCompleted'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } }
    )
    remove = @(
        @{ path = 'zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate' },
        @{ path = 'zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' },
        @{ path = 'zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\ChatAutoInstall' }
    )
}

