#Requires -Version 7.3

# Default builds remove imposed Copilot+ / Windows AI surfaces: the Windows
# Copilot app/shell surface, Edge AI APIs that websites can call, Notepad AI,
# and app access to system/generative AI models. Explicit user-invoked features
# such as Edge Copilot page-context chat, Paint AI, Click to Do, and the local
# Settings agent are left available; Office AI is license/app dependent and is
# not touched here. `-KeepCopilot` suppresses this whole module so a Copilot+ PC
# keeps these features — Recall stays disabled regardless (see
# 40-windows-ai-recall-policy).

Add-WinMintRegistryTweakModule @{
    id = 'windows-ai-features-removal'
    description = 'Remove imposed Copilot+ AI surfaces (Copilot app, Notepad AI, web AI APIs, app AI-model access) — kept with -KeepCopilot'
    scope = 'machine and default user policy registry'; risk = 'medium'; reversible = $true; phase = 'offline-image'
    intent = 'Remove imposed non-Recall Copilot+ AI surfaces by default while preserving explicit app-local tools; kept entirely when -KeepCopilot is selected.'
    appliesTo = { param($ctx) -not [bool]$ctx.KeepCopilot }
    set = @(
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; name = 'TurnOffWindowsCopilot'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'EdgeHistoryAISearchEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'BuiltInAIAPIsEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'AIGenThemesEnabled'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'ShareBrowsingHistoryWithCopilotSearchAllowed'; type = 'REG_DWORD'; value = '0'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Edge'; name = 'GenAILocalFoundationalModelSettings'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\WindowsNotepad'; name = 'DisableAIFeatures'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\AppPrivacy'; name = 'LetAppsAccessSystemAIModels'; type = 'REG_DWORD'; value = '2'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\AppPrivacy'; name = 'LetAppsAccessGenerativeAI'; type = 'REG_DWORD'; value = '2'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\generativeAI'; name = 'Value'; type = 'REG_SZ'; value = 'Deny'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\systemAIModels'; name = 'Value'; type = 'REG_SZ'; value = 'Deny'; undo = @{ action = 'delete' } },
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
