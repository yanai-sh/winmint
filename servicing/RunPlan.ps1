#requires -Version 7.6
<#
.SYNOPSIS
  Elevated ImageServicing entry: run plan stages in order (one UAC per Apply).
.NOTES
  Kernels are param-only — no Profile / DMA / edition branching here.
#>
param(
    [Parameter(Mandatory)]
    [string] $WorkDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$logDir = Join-Path $WorkDirectory 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$statusPath = Join-Path $WorkDirectory 'apply-status.txt'
Set-Content -LiteralPath $statusPath -Value "updated=$([datetime]::UtcNow.ToString('o'))`nstage=idle" -Encoding utf8

# Shared state for heartbeat ThreadJob (cannot see $script: from job).
$sync = [hashtable]::Synchronized(@{
        Opcode = 'idle'
        Log    = ''
        Stop   = $false
    })

$heartbeatJob = $null
try {
    # ponytail: ThreadJob polls every 30s; STALL_SUSPECT is advisory only (no kill).
    $heartbeatJob = Start-ThreadJob -ScriptBlock {
        param([string] $StatusPath, [hashtable] $Sync)
        $watchStage = ''
        $watchLogMtime = $null
        $watchWimCpu = $null
        $watchSince = $null
        while (-not $Sync.Stop) {
            try {
                $opcode = [string]$Sync.Opcode
                $logFile = [string]$Sync.Log
                $dismCpu = ''
                $wimCpu = ''
                $dism = Get-Process -Name Dism -ErrorAction SilentlyContinue | Select-Object -First 1
                $wim = Get-Process -Name wimserv -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($dism) { $dismCpu = [string][math]::Round([double]$dism.CPU, 2) }
                if ($wim) { $wimCpu = [string][math]::Round([double]$wim.CPU, 2) }

                $lastLine = ''
                $logMtime = $null
                if ($logFile -and (Test-Path -LiteralPath $logFile)) {
                    $logItem = Get-Item -LiteralPath $logFile
                    $logMtime = $logItem.LastWriteTimeUtc
                    $lines = @(Get-Content -LiteralPath $logFile -ErrorAction SilentlyContinue)
                    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
                        if (-not [string]::IsNullOrWhiteSpace($lines[$i])) {
                            $lastLine = ($lines[$i].Trim() -replace '\s+', ' ')
                            if ($lastLine.Length -gt 200) { $lastLine = $lastLine.Substring(0, 200) }
                            break
                        }
                    }
                }

                $wimCpuNum = $null
                if ($wimCpu -ne '') { $wimCpuNum = [double]$wimCpu }

                $stallSuspect = $false
                $stallReason = ''
                if ($opcode -ne $watchStage) {
                    $watchStage = $opcode
                    $watchLogMtime = $logMtime
                    $watchWimCpu = $wimCpuNum
                    $watchSince = [datetime]::UtcNow
                }
                else {
                    $logQuiet = ($null -ne $watchLogMtime -and $null -ne $logMtime -and $logMtime -eq $watchLogMtime) `
                        -or ($null -eq $logMtime -and $null -eq $watchLogMtime)
                    $cpuFlat = $false
                    if ($null -ne $wimCpuNum -and $null -ne $watchWimCpu) {
                        $cpuFlat = ([math]::Abs($wimCpuNum - $watchWimCpu) -lt 0.5)
                    }
                    elseif ($null -eq $wimCpuNum -and $null -eq $watchWimCpu) {
                        $cpuFlat = $true
                    }

                    if ($logQuiet -and $cpuFlat -and $null -ne $watchSince) {
                        $quietFor = ([datetime]::UtcNow - $watchSince).TotalMinutes
                        if ($quietFor -gt 10) {
                            $stallSuspect = $true
                            $stallReason = "stage=$opcode log quiet and wimserv CPU flat for $([int]$quietFor)m"
                        }
                    }
                    else {
                        $watchLogMtime = $logMtime
                        $watchWimCpu = $wimCpuNum
                        $watchSince = [datetime]::UtcNow
                    }
                }

                $linesOut = @(
                    "updated=$([datetime]::UtcNow.ToString('o'))"
                    "stage=$opcode"
                    "log=$logFile"
                    "last_line=$lastLine"
                    "dism_cpu=$dismCpu"
                    "wimserv_cpu=$wimCpu"
                )
                if ($stallSuspect) {
                    $linesOut += 'STALL_SUSPECT=1'
                    $linesOut += "STALL_REASON=$stallReason"
                }
                Set-Content -LiteralPath $StatusPath -Value ($linesOut -join "`n") -Encoding utf8
            }
            catch {
                # ponytail: heartbeat must not fail Apply
            }
            Start-Sleep -Seconds 30
        }
    } -ArgumentList $statusPath, $sync
}
catch {
    # ponytail: best-effort heartbeat
}

$stagesPath = Join-Path $WorkDirectory 'stages.json'
if (-not (Test-Path -LiteralPath $stagesPath)) {
    @{ schemaVersion = 'winmint.image.evidence/v1'; message = "stages.json missing"; opcode = $null } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $WorkDirectory 'failure.json') -Encoding utf8
    if ($heartbeatJob) {
        $sync.Stop = $true
        try { Wait-Job $heartbeatJob -Timeout 5 | Out-Null; Remove-Job $heartbeatJob -Force -ErrorAction SilentlyContinue } catch { }
    }
    exit 1
}

$stagesDoc = Get-Content -LiteralPath $stagesPath -Raw | ConvertFrom-Json
$scriptRoot = $PSScriptRoot

function ConvertTo-ParamHashtable {
    param($ParametersObject)
    $map = @{}
    if ($null -eq $ParametersObject) { return $map }
    foreach ($p in $ParametersObject.PSObject.Properties) {
        $map[$p.Name] = [string]$p.Value
    }
    return $map
}

function Resolve-KernelScript {
    param([string] $Opcode)
    switch ($Opcode) {
        'MountInstallWim' { return Join-Path $scriptRoot 'Mount-InstallWim.ps1' }
        'StagePayload' { return Join-Path $scriptRoot 'Stage-Payload.ps1' }
        'InjectUnattend' { return Join-Path $scriptRoot 'Inject-Unattend.ps1' }
        'StampOfflineShell' { return Join-Path $scriptRoot 'Stamp-OfflineShell.ps1' }
        'ExportWim' { return Join-Path $scriptRoot 'Export-Wim.ps1' }
        'BuildIso' { return Join-Path $scriptRoot 'Build-Iso.ps1' }
        default { throw "Unknown opcode: $Opcode" }
    }
}

$failed = $false
try {
    $index = 0
    foreach ($stage in $stagesDoc.stages) {
        $index++
        $opcode = [string]$stage.opcode
        $params = ConvertTo-ParamHashtable $stage.parameters
        $kernel = Resolve-KernelScript -Opcode $opcode
        $logFile = Join-Path $logDir ("{0:D2}-{1}.log" -f $index, $opcode)
        $sync.Opcode = $opcode
        $sync.Log = $logFile
        try {
            & $kernel -Parameters $params *>&1 | Tee-Object -FilePath $logFile
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
                throw "Kernel exited $LASTEXITCODE"
            }
        }
        catch {
            @{
                schemaVersion = 'winmint.image.evidence/v1'
                message       = "$_"
                opcode        = $opcode
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $WorkDirectory 'failure.json') -Encoding utf8
            $sync.Opcode = "failed:$opcode"
            $failed = $true
            break
        }
    }
}
finally {
    if (-not $failed) { $sync.Opcode = 'done' }
    $sync.Stop = $true
    if ($heartbeatJob) {
        try {
            Wait-Job $heartbeatJob -Timeout 5 | Out-Null
            Remove-Job $heartbeatJob -Force -ErrorAction SilentlyContinue
        }
        catch { }
    }
    # Final snapshot
    @(
        "updated=$([datetime]::UtcNow.ToString('o'))"
        "stage=$($sync.Opcode)"
        "log=$($sync.Log)"
    ) | Set-Content -LiteralPath $statusPath -Encoding utf8
}

if ($failed) {
    exit 1
}

$shellTarget = $null
$outputIso = $null
foreach ($stage in $stagesDoc.stages) {
    if ($stage.opcode -eq 'StampOfflineShell' -and $stage.parameters.shellTarget) {
        $shellTarget = [string]$stage.parameters.shellTarget
    }
    if ($stage.opcode -eq 'BuildIso' -and $stage.parameters.outputIso) {
        $outputIso = [string]$stage.parameters.outputIso
    }
}

$digests = @{}
if ($outputIso -and (Test-Path -LiteralPath $outputIso)) {
    $sha = Get-FileHash -LiteralPath $outputIso -Algorithm SHA256
    $digests['outputIso.sha256'] = $sha.Hash.ToLowerInvariant()
}
$wimOut = Join-Path $WorkDirectory 'install.wim'
if (Test-Path -LiteralPath $wimOut) {
    $shaWim = Get-FileHash -LiteralPath $wimOut -Algorithm SHA256
    $digests['installWim.sha256'] = $shaWim.Hash.ToLowerInvariant()
}

@{
    schemaVersion         = 'winmint.image.evidence/v1'
    outputIsoPath         = $outputIso
    shellStampTargetPath  = $shellTarget
    digests               = $digests
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $WorkDirectory 'evidence.json') -Encoding utf8

exit 0
