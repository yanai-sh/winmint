# SetupComplete machine-phase module: restore Windows Update / servicing policy.
# Tier 0 guardrail — keeps update infrastructure enabled. Dot-sourced by
# SetupComplete.ps1; relies on its script-scope $preserveWindowsUpdate.
#
# Uses Start-Process for reg.exe so non-zero exits (missing policy values) and
# native-command error preference never throw into SetupComplete_errors.log.
# This action only edits policy/service Start values — it must not query WU history.

function Invoke-ScRegExeBestEffort {
    param([Parameter(Mandatory)][string[]]$ArgumentList)

    try {
        $p = Start-Process -FilePath 'reg.exe' -ArgumentList $ArgumentList -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        return [int]$p.ExitCode
    }
    catch {
        return -1
    }
}

function Invoke-ScWindowsUpdateRestore {
    if (-not $preserveWindowsUpdate) {
        Write-ScLog 'Skipping Windows Update policy restoration by setup profile.'
        return
    }

    $ops = @(
        @{ Args = @('delete', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', '/v', 'NoAutoUpdate', '/f'); AllowNonZero = $true }
        @{ Args = @('delete', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', '/v', 'AUOptions', '/f'); AllowNonZero = $true }
        @{ Args = @('delete', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', '/v', 'UseWUServer', '/f'); AllowNonZero = $true }
        @{ Args = @('delete', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', '/v', 'DisableWindowsUpdateAccess', '/f'); AllowNonZero = $true }
        @{ Args = @('delete', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', '/v', 'WUServer', '/f'); AllowNonZero = $true }
        @{ Args = @('delete', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', '/v', 'WUStatusServer', '/f'); AllowNonZero = $true }
        @{ Args = @('delete', 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config', '/v', 'DODownloadMode', '/f'); AllowNonZero = $true }
        @{ Args = @('add', 'HKLM\SYSTEM\CurrentControlSet\Services\BITS', '/v', 'Start', '/t', 'REG_DWORD', '/d', '3', '/f'); AllowNonZero = $false }
        @{ Args = @('add', 'HKLM\SYSTEM\CurrentControlSet\Services\wuauserv', '/v', 'Start', '/t', 'REG_DWORD', '/d', '3', '/f'); AllowNonZero = $false }
        @{ Args = @('add', 'HKLM\SYSTEM\CurrentControlSet\Services\UsoSvc', '/v', 'Start', '/t', 'REG_DWORD', '/d', '2', '/f'); AllowNonZero = $false }
        @{ Args = @('add', 'HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc', '/v', 'Start', '/t', 'REG_DWORD', '/d', '3', '/f'); AllowNonZero = $false }
    )

    $failedAdds = [System.Collections.Generic.List[string]]::new()
    foreach ($op in $ops) {
        $code = Invoke-ScRegExeBestEffort -ArgumentList @($op.Args)
        if ($code -ne 0 -and -not [bool]$op.AllowNonZero) {
            $failedAdds.Add("$($op.Args -join ' ') (exit $code)") | Out-Null
        }
    }

    if ($failedAdds.Count -gt 0) {
        # Real restore failure (service Start could not be set) — hard channel.
        Write-ScError "Windows Update restore could not set service Start values: $($failedAdds -join ' | ')"
    }
    else {
        Write-ScLog 'Windows Update policy/service Start values restored (missing policy deletes ignored).'
    }
}
