# SetupComplete machine-phase module: restore Windows Update / servicing policy.
# Tier 0 guardrail — keeps update infrastructure enabled. Dot-sourced by
# SetupComplete.ps1; relies on its script-scope $preserveWindowsUpdate.

function Invoke-ScWindowsUpdateRestore {
    if (-not $preserveWindowsUpdate) {
        Write-ScLog 'Skipping Windows Update policy restoration by setup profile.'
        return
    }
    $regs = @(
        @('reg.exe', 'delete', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', '/v', 'NoAutoUpdate', '/f')
        @('reg.exe', 'delete', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', '/v', 'AUOptions', '/f')
        @('reg.exe', 'delete', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', '/v', 'UseWUServer', '/f')
        @('reg.exe', 'delete', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', '/v', 'DisableWindowsUpdateAccess', '/f')
        @('reg.exe', 'delete', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', '/v', 'WUServer', '/f')
        @('reg.exe', 'delete', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', '/v', 'WUStatusServer', '/f')
        @('reg.exe', 'delete', 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config', '/v', 'DODownloadMode', '/f')
        @('reg.exe', 'add', 'HKLM\SYSTEM\CurrentControlSet\Services\BITS', '/v', 'Start', '/t', 'REG_DWORD', '/d', '3', '/f')
        @('reg.exe', 'add', 'HKLM\SYSTEM\CurrentControlSet\Services\wuauserv', '/v', 'Start', '/t', 'REG_DWORD', '/d', '3', '/f')
        @('reg.exe', 'add', 'HKLM\SYSTEM\CurrentControlSet\Services\UsoSvc', '/v', 'Start', '/t', 'REG_DWORD', '/d', '2', '/f')
        @('reg.exe', 'add', 'HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc', '/v', 'Start', '/t', 'REG_DWORD', '/d', '3', '/f')
    )
    foreach ($a in $regs) {
        & $a[0] $a[1..($a.Count - 1)] 2>$null
    }
}
