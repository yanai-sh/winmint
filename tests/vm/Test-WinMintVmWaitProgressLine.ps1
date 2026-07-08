#Requires -Version 7.6
# Table-driven contract for VM wait progress line labels.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'tools\vm\WinMint-VmConsole.ps1')

$elapsed = [TimeSpan]::FromMinutes(1)
$remaining = [TimeSpan]::FromMinutes(34)

$cases = @(
    @{
        Name = 'poll-timeout'
        Snapshot = $null
        SeenAgentActivity = $true
        GuestPollTimedOut = $true
        Expected = 'guest=poll-timeout'
        Forbidden = 'firstlogon=post-cleanup'
    }
    @{
        Name = 'poll-unreachable'
        Snapshot = $null
        SeenAgentActivity = $true
        GuestPollTimedOut = $false
        Expected = 'guest=poll-unreachable'
        Forbidden = 'firstlogon=post-cleanup'
    }
    @{
        Name = 'active-no-state'
        Snapshot = [pscustomobject]@{ stateExists = $false; breadcrumb = $true; runStatus = ''; setupPhase = ''; currentStep = ''; completedSteps = 0; totalSteps = 0 }
        SeenAgentActivity = $true
        GuestPollTimedOut = $false
        Expected = 'firstlogon=active-no-state'
        Forbidden = 'firstlogon=post-cleanup'
    }
    @{
        Name = 'shell-progress'
        Snapshot = [pscustomobject]@{
            stateExists = $true
            breadcrumb = $false
            runStatus = 'running'
            setupPhase = 'running'
            setupShellProgressPct = 42
            setupShellTaskLabel = 'Installing tools'
            currentStep = 'module:wsl'
            completedSteps = 3
            totalSteps = 10
        }
        SeenAgentActivity = $true
        GuestPollTimedOut = $false
        Expected = 'pct=42'
        Forbidden = ''
    }
    @{
        Name = 'waiting-install'
        Snapshot = $null
        SeenAgentActivity = $false
        GuestPollTimedOut = $false
        Expected = 'guest=waiting (install/OOBE/autologon)'
        Forbidden = ''
    }
)

$failures = [System.Collections.Generic.List[string]]::new()
foreach ($case in $cases) {
    $line = Format-WinMintVmWaitProgressLine `
        -Snapshot $case.Snapshot `
        -Elapsed $elapsed `
        -Remaining $remaining `
        -VmState 'Running' `
        -SeenAgentActivity:$case.SeenAgentActivity `
        -GuestPollTimedOut:$case.GuestPollTimedOut
    if ($line -notmatch [regex]::Escape($case.Expected)) {
        $failures.Add("$($case.Name): expected '$($case.Expected)' in '$line'")
    }
    if ($case.Forbidden -and $line -match [regex]::Escape($case.Forbidden)) {
        $failures.Add("$($case.Name): forbidden '$($case.Forbidden)' in '$line'")
    }
}

$longLine = Format-WinMintVmWaitProgressLine `
    -Snapshot $null `
    -Elapsed ([TimeSpan]::FromMinutes(75)) `
    -Remaining ([TimeSpan]::FromMinutes(10)) `
    -VmState 'Running' `
    -SeenAgentActivity:$false `
    -GuestPollTimedOut:$false
if ($longLine -notmatch '1h 15m elapsed') {
    $failures.Add("long-duration: expected '1h 15m elapsed' in '$longLine'")
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "VM wait progress line contract: $($cases.Count) cases OK"
exit 0
