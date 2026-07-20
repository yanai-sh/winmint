# SetupComplete machine-phase module: split svchost per service so Task Manager
# shows accurate per-process resource use. Dot-sourced by SetupComplete.ps1;
# relies on its script-scope $logDir.

function Invoke-ScSvcHostSplit {
    # Per-service svchost processes give cleaner Task Manager attribution + better isolation,
    # but cost extra RAM (one process per service). Windows groups services into shared
    # svchost processes below the threshold to SAVE memory on constrained machines. WinMint is
    # laptop/low-RAM-first, so use a fixed 8 GB threshold: split on >=8 GB machines, but keep
    # Windows' memory-saving grouping on <8 GB laptops. (The old behavior set the threshold to
    # total RAM, which forced splitting on EVERY machine - counterproductive on low-RAM devices.)
    $thresholdKB = 8 * 1024 * 1024  # 8 GB in KB = 8388608
    try {
        Set-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control' `
            -Name 'SvcHostSplitThresholdInKB' -Value $thresholdKB -Type DWord -Force
        Write-ScLog "SvcHostSplitThresholdInKB set to $thresholdKB KB (8 GB): split on >=8 GB, group below."
    }
    catch {
        Write-ScError "SvcHostSplitThreshold failed: $_"
    }
}
