#Requires -Version 5.1
<#
.SYNOPSIS
  Runs the WinMint engine build from an on-disk BuildProfile.json.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$ProfilePath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

Import-Module (Join-Path $RepositoryRoot 'src\runtime\modules\WinMint.Bootstrap\WinMint.Bootstrap.psd1') -Force
$bootstrapArgs = @(
    '-RepositoryRoot', $RepositoryRoot,
    '-ProfilePath', $ProfilePath
)
if ($DryRun) { $bootstrapArgs += '-DryRun' }
$bootstrap = Invoke-WinMintRuntimeBootstrap -Entrypoint $PSCommandPath -Arguments $bootstrapArgs
if ($bootstrap.Relaunched) {
    exit $bootstrap.ExitCode
}

$script:WinMintRepositoryRoot = $RepositoryRoot
. (Join-Path $PSScriptRoot 'WinMint.UiBridgeProtocol.ps1')
Import-Module (Join-Path $RepositoryRoot 'src\runtime\modules\WinMint.Engine\WinMint.Engine.psd1') -Force
Initialize-WinMintEngine -RepositoryRoot $RepositoryRoot -DryRun:$DryRun

$buildProfile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
$progress = [System.Collections.Generic.List[object]]::new()
$progressHandler = {
    param($ProgressEvent)
    $progress.Add($ProgressEvent) | Out-Null
}
# Mute Spectre/human console so JSON on stdout stays clean; verbose file still fills.
if (Get-Command Set-WinMintHumanConsoleMuted -ErrorAction SilentlyContinue) {
    Set-WinMintHumanConsoleMuted -Muted $true
}

try {
    $build = Start-WinMintBuild -BuildProfile $buildProfile -DryRun:$DryRun -ProgressHandler $progressHandler
    $outputDir = Get-WinMintOutputDirectory
    $manifestPath = Join-Path $outputDir 'WinMint-BuildManifest.json'
    $outputPath = if ($build -and $build.PSObject.Properties['OutputPath']) { [string]$build.OutputPath } else { '' }
    $result = [ordered]@{
        Ok           = $true
        DryRun       = [bool]$DryRun
        OutputPath   = $outputPath
        OutputIsoPath = if ($outputPath -match '(?i)\.iso$') { $outputPath } else { '' }
        ManifestPath = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { $manifestPath } else { '' }
        BuildDeltaPath = (Join-Path $outputDir 'WinMint-BuildDelta.json')
        ReportPath   = if ($build -and $build.Paths -and $build.Paths.PSObject.Properties['Json']) { [string]$build.Paths.Json } else { '' }
        Progress     = @($progress)
        Error        = ''
    }
    Write-WinMintUiBridgeResult -Result $result
}
catch {
    $outputDir = Get-WinMintOutputDirectory
    $manifestPath = Join-Path $outputDir 'WinMint-BuildManifest.json'
    $result = [ordered]@{
        Ok           = $false
        DryRun       = [bool]$DryRun
        OutputPath   = ''
        OutputIsoPath = ''
        ManifestPath = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { $manifestPath } else { '' }
        BuildDeltaPath = (Join-Path $outputDir 'WinMint-BuildDelta.json')
        ReportPath   = ''
        Progress     = @($progress)
        Error        = $_.Exception.Message
    }
    Write-WinMintUiBridgeResult -Result $result
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
