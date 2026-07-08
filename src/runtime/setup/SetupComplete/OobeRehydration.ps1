# SetupComplete machine-phase module: suppress OOBE app rehydration jobs.
# Dot-sourced by SetupComplete.ps1; relies on its script-scope $logDir.

function Invoke-ScOobeRehydrationSuppression {
    $result = [ordered]@{
        generatedAt = Get-Date -Format o
        removedOobeKeys = @()
        workCompleted = @()
        failed = @()
    }
    foreach ($name in @('DevHomeUpdate', 'OutlookUpdate', 'ChatAutoInstall')) {
        $oobePath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\$name"
        try {
            if (Test-Path -LiteralPath $oobePath) {
                Remove-Item -LiteralPath $oobePath -Recurse -Force -ErrorAction Stop
                $result.removedOobeKeys += $name
                Write-ScLog "Removed OOBE rehydration key: $name"
            }
        }
        catch {
            $result.failed += [ordered]@{ action = 'RemoveOobeRehydrationKey'; target = $name; error = [string]$_ }
        }

        $schedulerPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\$name"
        try {
            if (-not (Test-Path -LiteralPath $schedulerPath)) {
                New-Item -Path $schedulerPath -Force -ErrorAction SilentlyContinue | Out-Null
            }
            Set-ItemProperty -LiteralPath $schedulerPath -Name 'workCompleted' -Type DWord -Value 1 -Force
            $result.workCompleted += $name
        }
        catch {
            $result.failed += [ordered]@{ action = 'SetOobeWorkCompleted'; target = $name; error = [string]$_ }
        }
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $logDir 'SetupComplete_OobeRehydration.json') -Encoding UTF8
}
