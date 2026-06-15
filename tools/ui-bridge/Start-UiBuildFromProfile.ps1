#Requires -Version 7.3
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

$script:WinMintRepositoryRoot = $RepositoryRoot
. (Join-Path $RepositoryRoot 'src\runtime\image\Core.ps1')
$engine = Get-WinMintPath -Name RuntimeImageEntry
. $engine
Initialize-WinMintEngine -RepositoryRoot $RepositoryRoot -DryRun:$DryRun

$buildProfile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
$progress = [System.Collections.Generic.List[object]]::new()
$progressHandler = {
    param($Event)
    $progress.Add($Event) | Out-Null
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
        ReportPath   = if ($build -and $build.Paths -and $build.Paths.PSObject.Properties['Json']) { [string]$build.Paths.Json } else { '' }
        Progress     = @($progress)
        Error        = ''
    }
    [pscustomobject]$result | ConvertTo-Json -Depth 12 -Compress
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
        ReportPath   = ''
        Progress     = @($progress)
        Error        = $_.Exception.Message
    }
    [pscustomobject]$result | ConvertTo-Json -Depth 12 -Compress
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
