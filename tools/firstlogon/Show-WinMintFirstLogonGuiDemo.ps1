#Requires -Version 7.3

[CmdletBinding()]
param(
    [string]$ProfilePath = '',
    [ValidateSet('Success', 'Warnings', 'Failure', 'LongRun')]
    [string]$Scenario = 'Success',
    [switch]$Release
)

$ErrorActionPreference = 'Stop'

function Resolve-DemoRepoRoot {
    $toolsDir = Split-Path -Parent $PSScriptRoot
    return Split-Path -Parent $toolsDir
}

function Resolve-DemoProfilePath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return Join-Path $Root 'tests\profiles\hyper-v-install-arm64.json'
    }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return Join-Path $Root $Path
}

$repoRoot = Resolve-DemoRepoRoot
$resolvedProfilePath = Resolve-DemoProfilePath -Root $repoRoot -Path $ProfilePath
if (-not (Test-Path -LiteralPath $resolvedProfilePath -PathType Leaf)) {
    throw "Profile not found: $resolvedProfilePath"
}

$demoRunId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
$demoRoot = Join-Path ([System.IO.Path]::GetTempPath().TrimEnd('\', '/')) ('WinMintFirstLogonGuiDemo-' + $demoRunId)
$logRoot = Join-Path $demoRoot 'Logs'
$null = New-Item -ItemType Directory -Path $logRoot -Force

$cargoArgs = @('run')
if ($Release) {
    $cargoArgs += '--release'
}
$cargoArgs += @(
    '-p',
    'winmint-firstlogon-gui',
    '--',
    '--profile',
    $resolvedProfilePath,
    '--logs',
    $logRoot,
    '--scenario',
    $Scenario
)

Push-Location $repoRoot
try {
    & cargo @cargoArgs
    if ($LASTEXITCODE -ne 0) {
        throw "cargo run failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}
