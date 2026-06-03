#Requires -Version 7.3

# Applied when AI removal policy is 'Core' (the Minimal default). Suppresses
# baseline Windows AI data analysis and Copilot policy surfaces while preserving
# Windows servicing. Mutually exclusive with windows-ai-full-policy.

Add-WinMintRegistryTweakModule @{
    id = 'windows-ai-core-policy'
    description = 'Windows AI core policy suppression'
    scope = 'machine policy registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Disable baseline Windows AI data analysis and Copilot policy surfaces while preserving Windows servicing.'
    appliesTo = { param($ctx) [string]$ctx.AiPolicy -eq 'Core' }
    set = @(
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\WindowsAI'; name = 'DisableAIDataAnalysis'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; name = 'TurnOffWindowsCopilot'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } }
    )
    remove = @()
}
