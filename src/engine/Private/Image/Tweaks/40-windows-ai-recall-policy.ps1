#Requires -Version 7.3

# Always applied (security): disable Recall and its data-analysis / snapshot /
# Click-to-Do surface. Recall is the one Copilot+ AI feature treated as a blatant
# security concern, so it stays removed on EVERY build — including when
# -KeepCopilot keeps the rest of the Copilot+ AI features (see
# 42-windows-ai-features-removal). The Recall *optional feature* and its scheduled
# task are removed separately via the AI-removal config / SetupComplete.

Add-WinMintRegistryTweakModule @{
    id = 'windows-ai-recall-policy'
    description = 'Disable Windows Recall (snapshots, data analysis, Click-to-Do)'
    scope = 'machine and default user policy registry'; risk = 'medium'; reversible = $true; phase = 'offline-image'
    intent = 'Always disable Recall snapshot capture and data analysis as a security baseline, even when Copilot+ AI features are kept.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\WindowsAI'; name = 'DisableAIDataAnalysis'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\WindowsAI'; name = 'AllowRecallEnablement'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\WindowsAI'; name = 'TurnOffSavingSnapshots'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\WindowsAI'; name = 'DisableClickToDo'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Policies\Microsoft\Windows\WindowsAI'; name = 'DisableAIDataAnalysis'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Policies\Microsoft\Windows\WindowsAI'; name = 'AllowRecallEnablement'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Policies\Microsoft\Windows\WindowsAI'; name = 'TurnOffSavingSnapshots'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Policies\Microsoft\Windows\WindowsAI'; name = 'DisableClickToDo'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\Shell\ClickToDo'; name = 'DisableClickToDo'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } }
    )
    remove = @()
}
