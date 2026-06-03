#Requires -Version 7.3

# Default builds remove the rest of the Copilot+ / Windows AI feature surface:
# the Copilot app, Edge AI (sidebar/page-context/history/built-in APIs/gen-themes/
# BingChat), Office Copilot, Paint + Notepad AI, the Windows AI settings agent,
# and app access to system/generative AI models. `-KeepCopilot` suppresses this
# whole module so a Copilot+ PC keeps these features — Recall stays disabled
# regardless (see 40-windows-ai-recall-policy).

Add-WinMintRegistryTweakModule @{
    id = 'windows-ai-features-removal'
    description = 'Remove Copilot+ AI features (Copilot app, Edge/Office/inbox AI, app AI-model access) — kept with -KeepCopilot'
    scope = 'machine and default user policy registry'; risk = 'medium'; reversible = $true; phase = 'offline-image'
    intent = 'Remove the non-Recall Copilot+ AI feature surface by default; kept entirely when -KeepCopilot is selected.'
    appliesTo = { param($ctx) -not [bool]$ctx.KeepCopilot }
    set = @(
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\WindowsAI'; name = 'DisableSettingsAgent'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Policies\Microsoft\Windows\WindowsAI'; name = 'DisableSettingsAgent'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; name = 'TurnOffWindowsCopilot'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'HubsSidebarEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'StandaloneHubsSidebarEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'CopilotPageContext'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'CopilotCDPPageContext'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'EdgeEntraCopilotPageContext'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'EdgeHistoryAISearchEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'BuiltInAIAPIsEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'AIGenThemesEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'ShareBrowsingHistoryWithCopilotSearchAllowed'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'GenAILocalFoundationalModelSettings'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'NewTabPageBingChatEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\WindowsNotepad'; name = 'DisableAIFeatures'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; name = 'DisableCocreator'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; name = 'DisableImageCreator'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; name = 'DisableGenerativeFill'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; name = 'DisableGenerativeErase'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; name = 'DisableRemoveBackground'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\AppPrivacy'; name = 'LetAppsAccessSystemAIModels'; type = 'REG_DWORD'; value = '2'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\AppPrivacy'; name = 'LetAppsAccessGenerativeAI'; type = 'REG_DWORD'; value = '2'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\generativeAI'; name = 'Value'; type = 'REG_SZ'; value = 'Deny'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\systemAIModels'; name = 'Value'; type = 'REG_SZ'; value = 'Deny'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Office\16.0\Word\Options'; name = 'EnableCopilot'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Office\16.0\Excel\Options'; name = 'EnableCopilot'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Office\16.0\OneNote\Options'; name = 'EnableCopilot'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Office\16.0\OneNote\Options\Copilot'; name = 'Enabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\WindowsCopilot'; name = 'AllowCopilotRuntime'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'ShowCopilotButton'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoInstalledPWAs'; name = 'CopilotPWAPreinstallCompleted'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\Microsoft.Copilot_8wekyb3d8bbwe'; name = 'Disabled'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{
            path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\Microsoft.Copilot_8wekyb3d8bbwe'
            name = 'DisabledByUser'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' }
        },
        @{
            path = 'zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
            name = '{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}'
            type = 'REG_SZ'; value = 'Ask Copilot'; undo = @{ action = 'delete' }
        }
    )
    remove = @()
}
