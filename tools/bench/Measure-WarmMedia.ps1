#requires -Version 7.6
<#
.SYNOPSIS
  Measure Prepared-media cold vs warm Apply timings on native ARM64.
#>
param(
    [string] $SourceIso = '',
    [string] $BaselineWorktree = '',
    [string] $Profile = 'samples/smoke.profile.json',
    [string] $OutDir = '',
    [int] $WimIndex = 3,
    [switch] $WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $repoRoot

$os = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
$proc = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
$pa = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE')
$wow = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITEW6432')
if ($os -ne 'Arm64' -or $proc -ne 'Arm64') {
    throw "bench-warm-media requires native ARM64 (OSArchitecture=$os, ProcessArchitecture=$proc, PROCESSOR_ARCHITECTURE=$pa, PROCESSOR_ARCHITEW6432=$wow)"
}

$matrix = [ordered]@{
    osArchitecture             = $os
    processArchitecture        = $proc
    processorArchitecture      = $pa
    processorArchitectureW6432 = $wow
    pwshVersion                = $PSVersionTable.PSVersion.ToString()
    dotnetVersion              = (dotnet --version)
    winmintCommit              = (git -C $repoRoot rev-parse HEAD)
    profile                    = $Profile
    wimIndex                   = $WimIndex
    runs                       = @(
        '1 untimed prime'
        '5 new cold Applies'
        '5 new warm Applies'
        '5 #94 cold-baseline Applies from -BaselineWorktree'
    )
}

Write-Output 'Warm-media benchmark matrix:'
$matrix.GetEnumerator() | ForEach-Object {
    if ($_.Key -eq 'runs') {
        Write-Output '  runs:'
        foreach ($run in $_.Value) { Write-Output "    - $run" }
    }
    else {
        Write-Output ("  {0}={1}" -f $_.Key, $_.Value)
    }
}

if ($WhatIf) {
    Write-Output 'WhatIf: no Apply, no Prepared-media mutation.'
    exit 0
}

if ([string]::IsNullOrWhiteSpace($SourceIso) -or -not (Test-Path -LiteralPath $SourceIso -PathType Leaf)) {
    throw 'SOURCE_ISO is required. Use -WhatIf to print the matrix without applying.'
}
if ([string]::IsNullOrWhiteSpace($BaselineWorktree) -or -not (Test-Path -LiteralPath $BaselineWorktree)) {
    throw 'BaselineWorktree is required (a #94 worktree that precedes Prepared media).'
}
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $repoRoot 'docs\evidence'
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$matrix['baselineCommit'] = (git -C $BaselineWorktree rev-parse HEAD)

$hostApply = Join-Path $repoRoot 'tools\apply\Invoke-HostApply.ps1'
$work = Join-Path $repoRoot '.scratch\warm-media-bench'
$samples = [System.Collections.Generic.List[object]]::new()
$jsonPath = Join-Path $OutDir 'warm-media-benchmark.json'
$mdPath = Join-Path $OutDir 'warm-media-benchmark.md'
$sha = (Get-FileHash -LiteralPath $SourceIso -Algorithm SHA256).Hash.ToLowerInvariant()

function Get-JsonProperty {
    param($Object, [string] $Name)
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Write-BenchRecord {
    $record = [ordered]@{
        schemaVersion   = 'winmint.warm-media.bench/v1'
        capturedUtc     = [datetime]::UtcNow.ToString('o')
        host            = $matrix
        sourceIso       = $SourceIso
        sourceIsoSha256 = $sha
        samples         = @($samples)
    }
    ($record | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $jsonPath -Encoding utf8
    @(
        '# Warm-media benchmark'
        ''
        "- Commit: $($matrix.winmintCommit)"
        "- Baseline commit: $($matrix.baselineCommit)"
        "- Source ISO SHA-256: $sha"
        "- Captured: $($record.capturedUtc)"
        ''
        '| label | totalMs | outcome |'
        '| --- | ---: | --- |'
    ) + @(
        $samples | ForEach-Object { "| $($_.label) | $($_.totalMs) | $($_.outcome) |" }
    ) | Set-Content -LiteralPath $mdPath -Encoding utf8
}

function Invoke-TimedApply {
    param([string] $Label, [string] $ApplyScript, [string] $ApplyWork)
    Write-Output $Label
    New-Item -ItemType Directory -Force -Path $ApplyWork | Out-Null
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $ApplyScript -Iso $SourceIso -Work $ApplyWork -Profile $Profile -ImageQuality Test
    $sw.Stop()
    if ($LASTEXITCODE -ne 0) { throw "$Label Apply failed: $LASTEXITCODE" }
    $evidence = Get-Content -LiteralPath (Join-Path $ApplyWork 'evidence.json') -Raw | ConvertFrom-Json
    $digests = Get-JsonProperty $evidence 'digests'
    $samples.Add([ordered]@{
            label           = $Label
            totalMs         = [int]$sw.ElapsedMilliseconds
            outcome         = [string](Get-JsonProperty $evidence 'mediaCache.outcome')
            sourceHashMs    = [int](Get-JsonProperty $evidence 'timings.sourceHashMs')
            cacheValidateMs = [int](Get-JsonProperty $evidence 'timings.cacheValidateMs')
            cachePrepareMs  = [int](Get-JsonProperty $evidence 'timings.cachePrepareMs')
            runMediaCopyMs  = [int](Get-JsonProperty $evidence 'timings.runMediaCopyMs')
            mountMs         = [int](Get-JsonProperty $evidence 'timings.mountMs')
            exportMs        = [int](Get-JsonProperty $evidence 'timings.exportMs')
            buildIsoMs      = [int](Get-JsonProperty $evidence 'timings.buildIsoMs')
            outputIsoSha256 = [string](Get-JsonProperty $digests 'outputIso.sha256')
        })
    Write-BenchRecord
}

Write-Output 'Prime (untimed)'
& $hostApply -Iso $SourceIso -Work (Join-Path $work 'prime') -Profile $Profile -ImageQuality Test | Out-Null

$entry = Join-Path $env:ProgramData "WinMint\Servicing\media-cache\v1\$sha\index-$WimIndex"

1..5 | ForEach-Object {
    if (Test-Path -LiteralPath $entry) { Remove-Item -LiteralPath $entry -Recurse -Force }
    Invoke-TimedApply -Label "cold-$_" -ApplyScript $hostApply -ApplyWork (Join-Path $work "cold-$_")
}
1..5 | ForEach-Object {
    Invoke-TimedApply -Label "warm-$_" -ApplyScript $hostApply -ApplyWork (Join-Path $work "warm-$_")
}

$baselineApply = Join-Path $BaselineWorktree 'tools\apply\Invoke-HostApply.ps1'
1..5 | ForEach-Object {
    Invoke-TimedApply -Label "baseline-cold-$_" -ApplyScript $baselineApply -ApplyWork (Join-Path $work "baseline-$_")
}

Write-BenchRecord
Write-Output "Wrote $jsonPath"
Write-Output "Wrote $mdPath"
exit 0
