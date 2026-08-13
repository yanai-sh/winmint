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

$logDir = $null
$statusPath = $null
$evidencePath = $null
$failurePath = $null
$stagesPath = $null
$currentStage = 'idle'
$currentLog = ''
function Write-ApplyStatus {
    param([string] $Stage, [string] $Log = '')
    $script:currentStage = $Stage
    if ($Log) { $script:currentLog = $Log }
    @(
        "updated=$([datetime]::UtcNow.ToString('o'))"
        "stage=$Stage"
        "log=$script:currentLog"
    ) | Set-Content -LiteralPath $statusPath -Encoding utf8
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        $Value
    )

    $temporaryPath = "$Path.tmp"
    try {
        $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryPath -Encoding utf8
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-FinalizerFileRemoval {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    }
}

function Write-PlanFailure {
    # Elevated runs cannot redirect stdout (UAC needs UseShellExecute), so failure.json is the
    # only channel back to C#. Every exit path that is not success writes one.
    param(
        [Parameter(Mandatory)]
        [string] $Message,

        [string] $Opcode
    )

    # Reporting is deliberately decomposed: stale evidence cleanup, current failure JSON, and
    # current status each get an attempt even when another one fails.
    $messages = [System.Collections.Generic.List[string]]::new()
    $messages.Add($Message)
    try {
        Invoke-FinalizerFileRemoval -Path $evidencePath
    }
    catch {
        $messages.Add("evidence cleanup failed: $_")
    }

    $reportingErrors = [System.Collections.Generic.List[string]]::new()
    try {
        $failure = @{
            schemaVersion = 'winmint.image.evidence/v1'
            message       = ($messages -join '; ')
            opcode        = $Opcode
        }
        if ($null -ne $script:phaseTimings) {
            $failure = Merge-WinMintPreparedMediaEvidence -Evidence $failure -WorkDirectory $WorkDirectory -PhaseTimings $script:phaseTimings -RecoveryAction $script:recoveryAction
        }
        Write-JsonAtomic -Path $failurePath -Value $failure
    }
    catch {
        $reportingErrors.Add("failure.json write failed: $_")
    }

    try {
        Write-ApplyStatus -Stage ('failed:' + ($Opcode ? $Opcode : 'plan'))
    }
    catch {
        $reportingErrors.Add("apply status write failed: $_")
    }

    foreach ($reportingError in $reportingErrors) {
        [Console]::Error.WriteLine($reportingError)
    }
}

$scriptRoot = $PSScriptRoot
. (Join-Path $scriptRoot 'Resolve-WinMintMount.ps1')
. (Join-Path $scriptRoot 'Get-WinMintServicingWorkspace.ps1')

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
        'StageOobeUnattend' { return Join-Path $scriptRoot 'Stage-OobeUnattend.ps1' }
        'PatchBootWimApply' { return Join-Path $scriptRoot 'Patch-BootWimApply.ps1' }
        'StampOfflineShell' { return Join-Path $scriptRoot 'Stamp-OfflineShell.ps1' }
        'StampOfflinePolicies' { return Join-Path $scriptRoot 'Stamp-OfflinePolicies.ps1' }
        'RemoveProvisionedAppx' { return Join-Path $scriptRoot 'Remove-ProvisionedAppx.ps1' }
        'RemoveCapabilities' { return Join-Path $scriptRoot 'Set-OfflineComponent.ps1' }
        'DisableOptionalFeatures' { return Join-Path $scriptRoot 'Set-OfflineComponent.ps1' }
        'InjectDrivers' { return Join-Path $scriptRoot 'Inject-SurfaceDrivers.ps1' }
        'ExportWim' { return Join-Path $scriptRoot 'Export-Wim.ps1' }
        'BuildIso' { return Join-Path $scriptRoot 'Build-Iso.ps1' }
        default { throw "Unknown opcode: $Opcode" }
    }
}

function Clear-LeftoverMount {
    # ponytail: one Host Apply at a time; discard only the owned ProgramData mount dirs.
    Clear-WinMintOwnedMount
}

function Write-PlanDigestSidecar {
    $outputIso = $null
    foreach ($stage in $stagesDoc.stages) {
        if ($stage.opcode -eq 'BuildIso' -and $stage.parameters.outputIso) {
            $outputIso = [string]$stage.parameters.outputIso
        }
    }

    if ([string]::IsNullOrWhiteSpace($outputIso)) {
        throw 'BuildIso stage outputIso required'
    }
    if (-not (Test-Path -LiteralPath $outputIso -PathType Leaf)) {
        throw "BuildIso output missing: $outputIso"
    }

    $digests = @{}
    if (Test-Path -LiteralPath $ws.digests) {
        $side = Get-Content -LiteralPath $ws.digests -Raw | ConvertFrom-Json
        foreach ($p in $side.PSObject.Properties) {
            $digests[[string]$p.Name] = [string]$p.Value
        }
    }

    if (Test-Path -LiteralPath $ws.installWim -PathType Leaf) {
        $shaWim = Get-FileHash -LiteralPath $ws.installWim -Algorithm SHA256
        $digests['installWim.sha256'] = $shaWim.Hash.ToLowerInvariant()
    }

    $sha = Get-FileHash -LiteralPath $outputIso -Algorithm SHA256
    $digests['outputIso.sha256'] = $sha.Hash.ToLowerInvariant()

    $ranInjectDrivers = @($stagesDoc.stages | Where-Object { [string]$_.opcode -eq 'InjectDrivers' }).Count -gt 0
    if ($ranInjectDrivers) {
        $inventoryPath = Join-Path $ws.logs 'WinMint-DriverInventory.json'
        if (-not (Test-Path -LiteralPath $inventoryPath)) {
            throw "InjectDrivers ran but inventory missing at $inventoryPath (Host Apply ExpectDrivers would fail)"
        }
    }

    New-Item -ItemType Directory -Force -Path $ws.logs | Out-Null
    $digests | ConvertTo-Json | Set-Content -LiteralPath $ws.digests -Encoding utf8

    if (Test-Path -LiteralPath $ws.preparedMedia -PathType Leaf) {
        $preparedDoc = Get-Content -LiteralPath $ws.preparedMedia -Raw | ConvertFrom-Json
        $previousMedia = [string]$preparedDoc.'mediaCache.previousMedia'
        if (-not [string]::IsNullOrWhiteSpace($previousMedia) -and (Test-Path -LiteralPath $previousMedia)) {
            Remove-Item -LiteralPath $previousMedia -Recurse -Force
        }
    }

    Invoke-FinalizerFileRemoval -Path $ws.failure
}

# Fail closed: $failed clears only after evidence is on disk, so a throw anywhere — an unknown
# opcode, a malformed stages.json, a missing driver inventory — still writes failure.json and
# still discards the mount. It used to report stage=done and leak the mount for anything thrown
# outside the kernel call.
$failed = $true
$opcode = ''
$servicingLock = $null
$script:phaseTimings = @{}
$script:recoveryAction = 'none'
try {
    $ws = Get-WinMintServicingWorkspace -Root $WorkDirectory
    $logDir = $ws.logs
    $statusPath = $ws.applyStatus
    $evidencePath = $ws.evidence
    $failurePath = $ws.failure
    $stagesPath = $ws.stages
    $env:WINMINT_SERVICING_RUN_ID = [guid]::NewGuid().ToString('N')
    $env:WINMINT_SERVICING_WORK = $WorkDirectory

    $servicingLock = Enter-WinMintImageServicingLock
    $recovery = Resolve-WinMintStaleMount
    $script:recoveryAction = [string]$recovery.recoveryAction
    if ([string]::IsNullOrWhiteSpace($script:recoveryAction)) { $script:recoveryAction = 'none' }
    $env:WINMINT_RECOVERY_ACTION = $script:recoveryAction
    $script:phaseTimings = @{}

    New-Item -ItemType Directory -Force -Path $logDir | Out-Null

    # Remove stale green state, but keep the prior failure visible until this run either atomically
    # overwrites it with a current failure or commits evidence and removes it on success.
    Invoke-FinalizerFileRemoval -Path $evidencePath
    Write-ApplyStatus -Stage 'idle'

    if (-not (Test-Path -LiteralPath $stagesPath -PathType Leaf)) {
        $opcode = 'stages'
        throw 'stages.json missing'
    }

    $opcode = 'stages'
    $stagesDoc = Get-Content -LiteralPath $stagesPath -Raw | ConvertFrom-Json
    if ($null -eq $stagesDoc -or
        ([string]$stagesDoc.schemaVersion -ne 'winmint.servicing.stages/v1') -or
        -not ($stagesDoc.PSObject.Properties.Name -contains 'stages') -or
        $stagesDoc.stages -isnot [System.Array]) {
        throw 'stages.json malformed'
    }

    $index = 0
    foreach ($stage in $stagesDoc.stages) {
        $index++
        if ($null -eq $stage -or
            -not ($stage.PSObject.Properties.Name -contains 'opcode') -or
            -not ($stage.PSObject.Properties.Name -contains 'parameters') -or
            $null -eq $stage.parameters) {
            $opcode = 'stages'
            throw "stages.json malformed at stage $index"
        }
        $opcode = [string]$stage.opcode
        $params = ConvertTo-ParamHashtable $stage.parameters
        $kernel = Resolve-KernelScript -Opcode $opcode
        $logFile = Join-Path $logDir ("{0:D2}-{1}.log" -f $index, $opcode)
        Write-ApplyStatus -Stage $opcode -Log $logFile
        $phaseClock = [System.Diagnostics.Stopwatch]::StartNew()
        & $kernel @params *>&1 | Tee-Object -FilePath $logFile
        $phaseClock.Stop()
        if ($opcode -eq 'ExportWim') {
            $script:phaseTimings['exportMs'] = [int]$phaseClock.ElapsedMilliseconds
        }
        elseif ($opcode -eq 'BuildIso') {
            $script:phaseTimings['buildIsoMs'] = [int]$phaseClock.ElapsedMilliseconds
        }
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            throw "Kernel exited $LASTEXITCODE"
        }
    }

    $opcode = 'digests'
    Write-PlanDigestSidecar
    Write-ApplyStatus -Stage 'done'
    $failed = $false
}
catch {
    Write-PlanFailure -Message "$_" -Opcode $opcode
}
finally {
    if ($failed -and $null -ne $servicingLock) { Clear-LeftoverMount }
    Exit-WinMintImageServicingLock $servicingLock
}

if ($failed) {
    exit 1
}

exit 0
