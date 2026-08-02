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

$stagesPath = Join-Path $WorkDirectory 'stages.json'
if (-not (Test-Path -LiteralPath $stagesPath)) {
    @{ schemaVersion = 'winmint.image.evidence/v1'; message = "stages.json missing"; opcode = $null } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $WorkDirectory 'failure.json') -Encoding utf8
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

$index = 0
foreach ($stage in $stagesDoc.stages) {
    $index++
    $opcode = [string]$stage.opcode
    $params = ConvertTo-ParamHashtable $stage.parameters
    $kernel = Resolve-KernelScript -Opcode $opcode
    $logFile = Join-Path $logDir ("{0:D2}-{1}.log" -f $index, $opcode)
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
        exit 1
    }
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

@{
    schemaVersion         = 'winmint.image.evidence/v1'
    outputIsoPath         = $outputIso
    shellStampTargetPath  = $shellTarget
    digests               = @{}
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $WorkDirectory 'evidence.json') -Encoding utf8

exit 0
