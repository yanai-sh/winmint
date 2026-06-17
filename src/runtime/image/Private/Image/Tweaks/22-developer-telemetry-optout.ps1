#Requires -Version 7.6

# Developer group: opt out of developer-toolchain telemetry via machine
# environment variables (.NET, PowerShell, and the cross-tool DO_NOT_TRACK).

Add-WinMintRegistryTweakModule @{
    id = 'developer-telemetry-optout'
    description = 'Opt out of developer toolchain telemetry via machine environment variables'
    scope = 'machine environment registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Disable opt-out telemetry for common developer runtimes (.NET, PowerShell) and honor the cross-tool DO_NOT_TRACK convention for Developer builds.'
    appliesTo = { param($ctx) $true }
    set = @(
        @{ path = 'zSYSTEM\ControlSet001\Control\Session Manager\Environment'; name = 'DOTNET_CLI_TELEMETRY_OPTOUT'; type = 'REG_SZ'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSYSTEM\ControlSet001\Control\Session Manager\Environment'; name = 'DOTNET_TRY_CLI_TELEMETRY_OPTOUT'; type = 'REG_SZ'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSYSTEM\ControlSet001\Control\Session Manager\Environment'; name = 'DOTNET_NOLOGO'; type = 'REG_SZ'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSYSTEM\ControlSet001\Control\Session Manager\Environment'; name = 'POWERSHELL_TELEMETRY_OPTOUT'; type = 'REG_SZ'; value = '1'; undo = @{ action = 'delete' } },
        @{ path = 'zSYSTEM\ControlSet001\Control\Session Manager\Environment'; name = 'DO_NOT_TRACK'; type = 'REG_SZ'; value = '1'; undo = @{ action = 'delete' } }
    )
    remove = @()
}

