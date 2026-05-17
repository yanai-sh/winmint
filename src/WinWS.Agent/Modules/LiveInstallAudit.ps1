#Requires -Version 7.3

function Invoke-WinWSAgentLiveInstallAuditBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    [void]$AgentProfile
    [void]$State

    $setupScripts = 'C:\Windows\Setup\Scripts'
    $auditScript = Join-Path $setupScripts 'Audit-LiveInstall.ps1'
    if (-not (Test-Path -LiteralPath $auditScript)) {
        return [pscustomobject]@{
            Id      = 'liveInstallAudit'
            Status  = 'failed'
            Message = "Live install audit script not found: $auditScript"
        }
    }

    $programData = if ($env:ProgramData) { $env:ProgramData } else { 'C:\ProgramData' }
    $reportPath = Join-Path $programData 'WinWS\Logs\LiveInstallAudit.json'
    $setupProfilePath = Join-Path $setupScripts 'WinWSSetupProfile.json'
    $ps = Resolve-AgentPowerShellHost
    $auditArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $auditScript,
        '-SetupProfilePath', $setupProfilePath,
        '-OutputPath', $reportPath,
        '-AsJson'
    )

    try {
        $json = & $ps @auditArgs 2>&1 | Out-String
    }
    catch {
        return [pscustomobject]@{
            Id      = 'liveInstallAudit'
            Status  = 'failed'
            Message = "Live install audit failed to start: $($_.Exception.Message)"
        }
    }

    try {
        $report = $json | ConvertFrom-Json
        $errors = [int]$report.summary.error
        $warnings = [int]$report.summary.warning
        return [pscustomobject]@{
            Id      = 'liveInstallAudit'
            Status  = 'ok'
            Message = "Live install audit wrote $reportPath; errors=$errors; warnings=$warnings"
            Report  = $reportPath
            Summary = $report.summary
        }
    }
    catch {
        return [pscustomobject]@{
            Id      = 'liveInstallAudit'
            Status  = 'failed'
            Message = "Live install audit emitted malformed JSON: $($_.Exception.Message)"
        }
    }
}
