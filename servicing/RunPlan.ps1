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

$stagesPath = Join-Path $WorkDirectory 'stages.json'
if (-not (Test-Path -LiteralPath $stagesPath)) {
    @{ schemaVersion = 'winmint.image.evidence/v1'; message = "stages.json missing"; opcode = $null } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $WorkDirectory 'failure.json') -Encoding utf8
    Write-ApplyStatus -Stage 'failed:stages'
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
        'RemoveProvisionedAppx' { return Join-Path $scriptRoot 'Remove-ProvisionedAppx.ps1' }
        'RemoveCapabilities' { return Join-Path $scriptRoot 'Mutate-OfflineComponent.ps1' }
        'DisableOptionalFeatures' { return Join-Path $scriptRoot 'Mutate-OfflineComponent.ps1' }
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

$failed = $false
try {
    $index = 0
    foreach ($stage in $stagesDoc.stages) {
        $index++
        $opcode = [string]$stage.opcode
        $params = ConvertTo-ParamHashtable $stage.parameters
        if ($opcode -eq 'RemoveCapabilities') { $params['kind'] = 'capability' }
        elseif ($opcode -eq 'DisableOptionalFeatures') { $params['kind'] = 'feature' }
        $kernel = Resolve-KernelScript -Opcode $opcode
        $logFile = Join-Path $logDir ("{0:D2}-{1}.log" -f $index, $opcode)
        Write-ApplyStatus -Stage $opcode -Log $logFile
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
            Write-ApplyStatus -Stage "failed:$opcode"
            $failed = $true
            break
        }
    }
}
finally {
    if ($failed) { Clear-LeftoverMount }
    if (-not $failed) { Write-ApplyStatus -Stage 'done' }
}

if ($failed) {
    exit 1
}

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

@{
    schemaVersion         = 'winmint.image.evidence/v1'
    outputIsoPath         = $outputIso
    shellStampTargetPath  = $shellTarget
    lane                  = $lane
    digests               = $digests
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $WorkDirectory 'evidence.json') -Encoding utf8

exit 0
