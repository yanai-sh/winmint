# SetupComplete machine-phase module: serviceable Windows AI cleanup.
# Dot-sourced by SetupComplete.ps1; relies on its script-scope $logDir and the
# parsed $aiPolicy / $aiRemoveRecall / $aiDisableServices / $aiServicesToDisable /
# $aiDisableTasks / $aiTaskPatternsToDisable variables.

function Invoke-ScAiServiceableCleanup {
    $result = [ordered]@{
        generatedAt = Get-Date -Format o
        policy = $aiPolicy
        optionalFeaturesRemoved = @()
        servicesDisabled = @()
        scheduledTasksDisabled = @()
        failed = @()
    }

    if ($aiRemoveRecall) {
        try {
            $r = Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.State -eq 'Enabled' -and $_.FeatureName -like 'Recall' }
            if ($r) {
                Disable-WindowsOptionalFeature -Online -FeatureName 'Recall' -Remove -ErrorAction SilentlyContinue
                $result.optionalFeaturesRemoved += 'Recall'
                Write-ScLog 'Removed Recall optional feature during SetupComplete.'
            }
        }
        catch {
            $result.failed += [ordered]@{ action = 'RemoveOptionalFeature'; target = 'Recall'; error = [string]$_ }
            Write-ScWarn "Recall removal failed: $_"
        }
    }

    if ($aiDisableServices) {
        foreach ($svcName in @($aiServicesToDisable)) {
            if ([string]::IsNullOrWhiteSpace([string]$svcName)) { continue }
            try {
                $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                if (-not $svc) { continue }
                Stop-Service -Name $svcName -ErrorAction SilentlyContinue
                Set-Service -Name $svcName -StartupType Disabled -ErrorAction SilentlyContinue
                $null = & reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\$svcName" /v Start /t REG_DWORD /d 4 /f 2>$null
                $result.servicesDisabled += [string]$svcName
                Write-ScLog "Disabled AI service: $svcName"
            }
            catch {
                $result.failed += [ordered]@{ action = 'DisableService'; target = [string]$svcName; error = [string]$_ }
                Write-ScWarn "AI service disable failed for ${svcName}: $_"
            }
        }
    }

    if ($aiDisableTasks) {
        $pattern = '(' + (($aiTaskPatternsToDisable | ForEach-Object { [regex]::Escape([string]$_) }) -join '|') + ')'
        if (-not [string]::IsNullOrWhiteSpace($pattern) -and $pattern -ne '()') {
            foreach ($task in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match $pattern -or $_.TaskPath -match $pattern })) {
                $name = "$($task.TaskPath)$($task.TaskName)"
                try {
                    Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue | Out-Null
                    $result.scheduledTasksDisabled += $name
                    Write-ScLog "Disabled AI scheduled task: $name"
                }
                catch {
                    $result.failed += [ordered]@{ action = 'DisableScheduledTask'; target = $name; error = [string]$_ }
                    Write-ScWarn "AI scheduled task disable failed for ${name}: $_"
                }
            }
        }
    }

    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $logDir 'SetupComplete_AiRemoval.json') -Encoding UTF8
}
