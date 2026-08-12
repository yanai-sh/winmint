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
Write-ApplyStatus -Stage 'idle'

function Write-PlanFailure {
    # Elevated runs cannot redirect stdout (UAC needs UseShellExecute), so failure.json is the
    # only channel back to C#. Every exit path that is not success writes one.
    param(
        [Parameter(Mandatory)]
        [string] $Message,

        [string] $Opcode
    )
    @{
        schemaVersion = 'winmint.image.evidence/v1'
        message       = $Message
        opcode        = $Opcode
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $WorkDirectory 'failure.json') -Encoding utf8
    Write-ApplyStatus -Stage ('failed:' + ($Opcode ? $Opcode : 'plan'))
}

$stagesPath = Join-Path $WorkDirectory 'stages.json'
if (-not (Test-Path -LiteralPath $stagesPath)) {
    Write-PlanFailure -Message 'stages.json missing' -Opcode 'stages'
    exit 1
}

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
    # Host mounts live under %ProgramData%\WinMint\Servicing (not workdir).
    # Also discard legacy workdir mounts from older Applies. Discard only —
    # workdir/logs/media stay for diagnosis (IMAGESERVICING invariant 4).
    $roots = @(
        (Join-Path $env:ProgramData 'WinMint\Servicing')
        $WorkDirectory
    )
    foreach ($root in $roots) {
        foreach ($name in @('mount', 'boot-mount')) {
            $dir = Join-Path $root $name
            if (-not (Test-Path -LiteralPath $dir)) { continue }
            & dism.exe /English /Unmount-Image /MountDir:$dir /Discard 2>$null | Out-Null
        }
    }
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

    $sidePath = Join-Path $logDir 'digests.json'
    if (Test-Path -LiteralPath $sidePath) {
        $side = Get-Content -LiteralPath $sidePath -Raw | ConvertFrom-Json
        foreach ($p in $side.PSObject.Properties) {
            $digests[[string]$p.Name] = [string]$p.Value
        }
    }

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

    @{
        schemaVersion         = 'winmint.image.evidence/v1'
        outputIsoPath         = $outputIso
        shellStampTargetPath  = $shellTarget
        lane                  = $lane
        packageStrict         = $packageStrict
        digests               = $digests
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $WorkDirectory 'evidence.json') -Encoding utf8

    # Success clears prior stage failure crumbs (operators read failure.json as current).
    Remove-Item -LiteralPath (Join-Path $WorkDirectory 'failure.json') -Force -ErrorAction SilentlyContinue
}

# Fail closed: $failed clears only after evidence is on disk, so a throw anywhere — an unknown
# opcode, a malformed stages.json, a missing driver inventory — still writes failure.json and
# still discards the mount. It used to report stage=done and leak the mount for anything thrown
# outside the kernel call.
$failed = $true
$opcode = ''
try {
    $stagesDoc = Get-Content -LiteralPath $stagesPath -Raw | ConvertFrom-Json

    $index = 0
    foreach ($stage in $stagesDoc.stages) {
        $index++
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
    $failed = $false
}
catch {
    Write-PlanFailure -Message "$_" -Opcode $opcode
}
finally {
    if ($failed) { Clear-LeftoverMount } else { Write-ApplyStatus -Stage 'done' }
}

if ($failed) {
    exit 1
}

exit 0
