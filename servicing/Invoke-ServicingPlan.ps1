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
        Write-JsonAtomic -Path $failurePath -Value @{
            schemaVersion = 'winmint.image.evidence/v1'
            message       = ($messages -join '; ')
            opcode        = $Opcode
        }
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

function Write-PlanEvidence {
    $shellTarget = $null
    $outputIso = $null
    $lane = $null
    foreach ($stage in $stagesDoc.stages) {
        if ($stage.opcode -eq 'StampOfflineShell' -and $stage.parameters.shellTarget) {
            $shellTarget = [string]$stage.parameters.shellTarget
        }
        if ($stage.opcode -eq 'BuildIso' -and $stage.parameters.outputIso) {
            $outputIso = [string]$stage.parameters.outputIso
        }
        if ($stage.opcode -eq 'ExportWim' -and $stage.parameters.lane) {
            $lane = [string]$stage.parameters.lane
        }
    }

    if ([string]::IsNullOrWhiteSpace($outputIso)) {
        throw 'BuildIso stage outputIso required'
    }
    if (-not (Test-Path -LiteralPath $outputIso -PathType Leaf)) {
        throw "BuildIso output missing: $outputIso"
    }
    if ([string]::IsNullOrWhiteSpace($lane)) {
        throw 'ExportWim stage lane required'
    }
    if ([string]::IsNullOrWhiteSpace($shellTarget)) {
        throw 'StampOfflineShell stage shellTarget required'
    }

    $digests = @{}
    $sidePath = Join-Path $logDir 'digests.json'
    if (Test-Path -LiteralPath $sidePath) {
        $side = Get-Content -LiteralPath $sidePath -Raw | ConvertFrom-Json
        foreach ($p in $side.PSObject.Properties) {
            $digests[[string]$p.Name] = [string]$p.Value
        }
    }

    $wimOut = Join-Path $WorkDirectory 'install.wim'
    if (Test-Path -LiteralPath $wimOut -PathType Leaf) {
        $shaWim = Get-FileHash -LiteralPath $wimOut -Algorithm SHA256
        $digests['installWim.sha256'] = $shaWim.Hash.ToLowerInvariant()
    }

    # Authoritative ISO digest is computed last so no stale sidecar can replace it.
    $sha = Get-FileHash -LiteralPath $outputIso -Algorithm SHA256
    $digests['outputIso.sha256'] = $sha.Hash.ToLowerInvariant()

    # InjectDrivers writes logs/WinMint-DriverInventory.json — require it before greening evidence.
    $ranInjectDrivers = @($stagesDoc.stages | Where-Object { [string]$_.opcode -eq 'InjectDrivers' }).Count -gt 0
    if ($ranInjectDrivers) {
        $inventoryPath = Join-Path $logDir 'WinMint-DriverInventory.json'
        if (-not (Test-Path -LiteralPath $inventoryPath)) {
            throw "InjectDrivers ran but inventory missing at $inventoryPath (Host Apply ExpectDrivers would fail)"
        }
    }

    $packageStrict = $false
    $bundlePath = Join-Path $WorkDirectory 'payload\bundle.json'
    if (Test-Path -LiteralPath $bundlePath) {
        $bundle = Get-Content -LiteralPath $bundlePath -Raw | ConvertFrom-Json
        if ($bundle.PSObject.Properties.Name -contains 'packageStrict') {
            $packageStrict = [bool]$bundle.packageStrict
        }
    }

    Write-JsonAtomic -Path $evidencePath -Value @{
        schemaVersion         = 'winmint.image.evidence/v1'
        outputIsoPath         = $outputIso
        shellStampTargetPath  = $shellTarget
        lane                  = $lane
        packageStrict         = $packageStrict
        digests               = $digests
    }

    # Evidence is not green until stale failure state is gone. A deletion error returns to the
    # outer fail-closed handler, which removes/quarantines this fresh evidence and reports failure.
    Invoke-FinalizerFileRemoval -Path $failurePath
}

# Fail closed: $failed clears only after evidence is on disk, so a throw anywhere — an unknown
# opcode, a malformed stages.json, a missing driver inventory — still writes failure.json and
# still discards the mount. It used to report stage=done and leak the mount for anything thrown
# outside the kernel call.
$failed = $true
$opcode = ''
$servicingLock = $null
try {
    $logDir = Join-Path $WorkDirectory 'logs'
    $statusPath = Join-Path $WorkDirectory 'apply-status.txt'
    $evidencePath = Join-Path $WorkDirectory 'evidence.json'
    $failurePath = Join-Path $WorkDirectory 'failure.json'
    $stagesPath = Join-Path $WorkDirectory 'stages.json'
    $env:WINMINT_SERVICING_RUN_ID = [guid]::NewGuid().ToString('N')
    $env:WINMINT_SERVICING_WORK = $WorkDirectory

    $servicingLock = Enter-WinMintImageServicingLock
    Resolve-WinMintStaleMount | Out-Null

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
        & $kernel -Parameters $params *>&1 | Tee-Object -FilePath $logFile
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            throw "Kernel exited $LASTEXITCODE"
        }
    }

    $opcode = 'evidence'
    Write-PlanEvidence
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
