# SetupComplete machine-phase module: telemetry scheduled-task hardening.
# Dot-sourced by SetupComplete.ps1; relies on its script-scope $logDir,
# $disableTelemetryTasks, and $telemetryTaskPatternsToDisable.

function Invoke-ScTelemetryTaskHardening {
    if (-not $disableTelemetryTasks) {
        Write-ScLog 'Skipping telemetry scheduled-task hardening by setup profile.'
        return
    }
    $patterns = @($telemetryTaskPatternsToDisable | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($patterns.Count -eq 0) { return }
    $result = [ordered]@{ scheduledTasksDisabled = @(); failed = @() }
    $pattern = '(' + (($patterns | ForEach-Object { [regex]::Escape([string]$_) }) -join '|') + ')'
    foreach ($task in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match $pattern -or $_.TaskPath -match $pattern })) {
        $name = "$($task.TaskPath)$($task.TaskName)"
        try {
            Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue | Out-Null
            $result.scheduledTasksDisabled += $name
            Write-ScLog "Disabled telemetry scheduled task: $name"
        }
        catch {
            $result.failed += [ordered]@{ action = 'DisableScheduledTask'; target = $name; error = [string]$_ }
            Write-ScWarn "Telemetry scheduled task disable failed for ${name}: $_"
        }
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $logDir 'SetupComplete_TelemetryTasks.json') -Encoding UTF8
}
