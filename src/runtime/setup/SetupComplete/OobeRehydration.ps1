# SetupComplete machine-phase module: suppress OOBE app rehydration jobs.
# Dot-sourced by SetupComplete.ps1; relies on its script-scope $logDir.
# Enumerate UScheduler_Oobe; only suppress known keys. Unknowns are left alone.

$script:WinMintKnownOobeRehydrationJobs = [ordered]@{
    OutlookUpdate = [ordered]@{
        documented = $true
        source     = 'learn-control-install-new-outlook'
        workCompleted = $true
        blockedOobeUpdater = 'MS_Outlook'
    }
    DevHomeUpdate = [ordered]@{
        documented = $false
        source     = 'community-best-effort'
        workCompleted = $true
        blockedOobeUpdater = $null
    }
    ChatAutoInstall = [ordered]@{
        documented = $false
        source     = 'community-best-effort'
        workCompleted = $true
        blockedOobeUpdater = $null
    }
}

function Invoke-ScOobeRehydrationSuppression {
    $oobeRoot = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe'
    $schedulerRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler'
    $result = [ordered]@{
        generatedAt       = Get-Date -Format o
        enumeratedKeys    = @()
        suppressed        = @()
        leftAlone         = @()
        blockedOobeUpdaters = @()
        removedOobeKeys   = @()
        workCompleted     = @()
        failed            = @()
    }

    $present = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $oobeRoot) {
        foreach ($child in @(Get-ChildItem -LiteralPath $oobeRoot -ErrorAction SilentlyContinue)) {
            $present.Add([string]$child.PSChildName) | Out-Null
        }
    }
    $result.enumeratedKeys = @($present)

    foreach ($name in @($script:WinMintKnownOobeRehydrationJobs.Keys)) {
        $meta = $script:WinMintKnownOobeRehydrationJobs[$name]
        $oobePath = Join-Path $oobeRoot $name
        $wasPresent = $present -contains $name
        $entry = [ordered]@{
            name        = $name
            documented  = [bool]$meta.documented
            source      = [string]$meta.source
            wasPresent  = $wasPresent
            removed     = $false
            workCompleted = $false
        }

        try {
            if ($wasPresent) {
                Remove-Item -LiteralPath $oobePath -Recurse -Force -ErrorAction Stop
                $entry.removed = $true
                $result.removedOobeKeys += $name
                Write-ScLog "Removed OOBE rehydration key: $name ($($meta.source))"
            }
        }
        catch {
            $result.failed += [ordered]@{ action = 'RemoveOobeRehydrationKey'; target = $name; error = [string]$_ }
        }

        if ([bool]$meta.workCompleted) {
            $schedulerPath = Join-Path $schedulerRoot $name
            try {
                if (-not (Test-Path -LiteralPath $schedulerPath)) {
                    New-Item -Path $schedulerPath -Force -ErrorAction SilentlyContinue | Out-Null
                }
                Set-ItemProperty -LiteralPath $schedulerPath -Name 'workCompleted' -Type DWord -Value 1 -Force
                $entry.workCompleted = $true
                $result.workCompleted += $name
            }
            catch {
                $result.failed += [ordered]@{ action = 'SetOobeWorkCompleted'; target = $name; error = [string]$_ }
            }
        }

        $result.suppressed += $entry
    }

    # Documented Win10 Outlook control; harmless when present on Win11.
    $outlookMeta = $script:WinMintKnownOobeRehydrationJobs['OutlookUpdate']
    if ($outlookMeta -and -not [string]::IsNullOrWhiteSpace([string]$outlookMeta.blockedOobeUpdater)) {
        try {
            if (-not (Test-Path -LiteralPath $oobeRoot)) {
                New-Item -Path $oobeRoot -Force -ErrorAction Stop | Out-Null
            }
            $blockedValue = '["{0}"]' -f [string]$outlookMeta.blockedOobeUpdater
            Set-ItemProperty -LiteralPath $oobeRoot -Name 'BlockedOobeUpdaters' -Type String -Value $blockedValue -Force
            $result.blockedOobeUpdaters += [ordered]@{
                name  = [string]$outlookMeta.blockedOobeUpdater
                value = $blockedValue
            }
            Write-ScLog "Set BlockedOobeUpdaters for Outlook: $blockedValue"
        }
        catch {
            $result.failed += [ordered]@{ action = 'SetBlockedOobeUpdaters'; target = 'MS_Outlook'; error = [string]$_ }
        }
    }

    foreach ($name in @($present)) {
        if (-not $script:WinMintKnownOobeRehydrationJobs.Contains($name)) {
            $result.leftAlone += $name
            Write-ScLog "Left unknown OOBE rehydration key alone: $name"
        }
    }

    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $logDir 'SetupComplete_OobeRehydration.json') -Encoding UTF8
}
