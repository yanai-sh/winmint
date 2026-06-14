#Requires -Version 7.3

# Applied when the telemetry privacy default is on: stop the DiagTrack and
# SQM/CEIP ETW autologger sessions from auto-starting. Does not touch diagnostics
# needed for crash analysis.

Add-WinMintRegistryTweakModule @{
    id = 'telemetry-tracing-policy'
    description = 'Disable DiagTrack and CEIP ETW autologger sessions'
    scope = 'machine registry'; risk = 'low'; reversible = $true; phase = 'offline-image'
    intent = 'Stop the Connected User Experiences/DiagTrack and SQM/CEIP kernel trace sessions from auto-starting, without touching diagnostics needed for crash analysis.'
    appliesTo = { param($ctx) [bool]$ctx.PrivacyTelemetry }
    set = @(
        @{ path = 'zSYSTEM\ControlSet001\Control\WMI\Autologger\Diagtrack-Listener'; name = 'Start'; type = 'REG_DWORD'; value = '0'; undo = @{ type = 'REG_DWORD'; value = '1' } },
        @{ path = 'zSYSTEM\ControlSet001\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener'; name = 'Start'; type = 'REG_DWORD'; value = '0'; undo = @{ type = 'REG_DWORD'; value = '1' } },
        @{ path = 'zSYSTEM\ControlSet001\Control\WMI\Autologger\SQMLogger'; name = 'Start'; type = 'REG_DWORD'; value = '0'; undo = @{ type = 'REG_DWORD'; value = '1' } }
    )
    remove = @()
}
