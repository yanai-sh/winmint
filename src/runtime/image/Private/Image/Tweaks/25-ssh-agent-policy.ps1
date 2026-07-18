#Requires -Version 7.6

# Developer group: set OpenSSH Authentication Agent service to Automatic.

Add-WinMintRegistryTweakModule @{
    id = 'ssh-agent-policy'
    description = 'Set OpenSSH Authentication Agent service to Automatic startup.'
    scope = 'offline registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Ensure the native Windows ssh-agent service starts automatically for developer environments.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSYSTEM\ControlSet001\Services\ssh-agent'; name = 'Start'; type = 'REG_DWORD'; value = '2'; undo = @{ type = 'REG_DWORD'; value = '4' } }
    )
    remove = @()
}
