# SetupComplete machine-phase module: force VMConnect Basic console in Hyper-V guests.
# Dot-sourced by SetupComplete.ps1; relies on script-scope $logDir and profile helpers.
# ponytail: guest registry only; harmless on bare metal (key is ignored outside a VM).

function Invoke-ScHyperVGuestBasicConsole {
    if (-not (Get-ScSetupProfileBool -Section 'diagnostics' -Name 'vmGuestBasicConsole' -Default $false)) {
        return
    }

    try {
        $key = 'HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest'
        $null = New-Item -Path $key -Force
        $null = New-ItemProperty -Path $key -Name 'DisableEnhancedSessionConsoleConnection' `
            -PropertyType DWord -Value 1 -Force
        Write-ScLog 'Set DisableEnhancedSessionConsoleConnection=1 (VMConnect Basic-only; no Enhanced Session login).'
    }
    catch {
        "Hyper-V guest basic console policy failed: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
    }
}
