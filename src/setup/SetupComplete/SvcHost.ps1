# SetupComplete machine-phase module: split svchost per service so Task Manager
# shows accurate per-process resource use. Dot-sourced by SetupComplete.ps1;
# relies on its script-scope $logDir.

function Invoke-ScSvcHostSplit {
    # Default threshold (3.5 GB) groups services on low-RAM machines; modern hardware always splits.
    try {
        $ramKB = [long]([math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1024))
        Set-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control' `
            -Name 'SvcHostSplitThresholdInKB' -Value $ramKB -Type DWord -Force
        Write-ScLog "SvcHostSplitThresholdInKB set to $ramKB KB (total physical RAM)."
    }
    catch {
        "SvcHostSplitThreshold failed: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
    }
}
