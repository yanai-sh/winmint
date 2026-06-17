#Requires -Version 7.6

# Developer group: relax execution policy to RemoteSigned for Windows PowerShell
# and PowerShell 7 (locally authored scripts run; downloaded scripts stay gated).

Add-WinMintRegistryTweakModule @{
    id = 'powershell-remotesigned'
    description = 'PowerShell execution policy: RemoteSigned for Windows PowerShell and PowerShell 7'
    scope = 'machine registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Permit locally authored PowerShell scripts while keeping downloaded scripts signature-gated.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell'; name = 'ExecutionPolicy'; type = 'REG_SZ'; value = 'RemoteSigned'; undo = @{ action = 'delete' } },
        @{ path = 'zSOFTWARE\Microsoft\PowerShellCore\ShellIds\Microsoft.PowerShell'; name = 'ExecutionPolicy'; type = 'REG_SZ'; value = 'RemoteSigned'; undo = @{ action = 'delete' } }
    )
    remove = @()
}

