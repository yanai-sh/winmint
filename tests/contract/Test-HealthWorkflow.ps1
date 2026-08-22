#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workflow = Get-Content -LiteralPath (Join-Path $root '.github\workflows\health.yml') -Raw
$harness = Get-Content -LiteralPath (Join-Path $root 'tools\ci\Invoke-HealthCheck.ps1') -Raw

function Assert-Contains([string] $Text, [string] $Needle, [string] $Label) {
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "health workflow contract missing: $Label"
    }
}

function Assert-Matches([string] $Text, [string] $Pattern, [string] $Label) {
    if ($Text -notmatch $Pattern) {
        throw "health workflow contract missing: $Label"
    }
}

$triggerMatch = [regex]::Match($workflow, '(?ms)^on:\r?\n(?<body>.*?)(?=^permissions:)')
if (-not $triggerMatch.Success) { throw 'health workflow trigger block missing' }
$triggerLines = @($triggerMatch.Groups['body'].Value -split '\r?\n' |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
if (($triggerLines -join '|') -notmatch '^schedule:\|- cron: "[^"]+"\|workflow_dispatch:$') {
    throw "health workflow must trigger only on schedule and dispatch, got '$($triggerLines -join '|')'"
}
if ($workflow -match '(?m)^\s+needs:') {
    throw 'health health-signal jobs must not depend on one another'
}

Assert-Contains $workflow 'permissions:' 'workflow permissions'
Assert-Contains $workflow 'contents: read' 'read-only permissions'
if ($workflow -match '(?im)^\s+contents:\s+write\b') {
    throw 'health workflow must not request repository write permission'
}
foreach ($job in @('quality', 'packages')) {
    Assert-Matches $workflow "(?ms)^  ${job}:\r?\n(?<body>.*?)(?=^  (?! )[A-Za-z0-9_-]+:|\z)" "$job job"
    $body = [regex]::Match(
        $workflow,
        "(?ms)^  ${job}:\r?\n(?<body>.*?)(?=^  (?! )[A-Za-z0-9_-]+:|\z)"
    ).Groups['body'].Value
    Assert-Contains $body 'runs-on: windows-11-arm' "$job native ARM64 runner"
    Assert-Matches $body 'permissions:\r?\n      contents: read' "$job read permission"
    Assert-Contains $body 'if: always()' "$job always-upload step"
    Assert-Contains $body 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02' "$job full-SHA upload pin"
    Assert-Contains $body 'retention-days: 1' "$job short artifact retention"
}
Assert-Contains $harness "'packages-check'" 'existing package command reuse'
Assert-Contains $harness 'Invoke-QualityCheck.ps1' 'direct quality script'
Assert-Contains $harness 'Invoke-WinMintCli.ps1' 'direct package script'
if ($harness -match '(?im)\bjust\b') { throw 'health harness must not depend on just' }
Assert-Contains $workflow '.scratch/health/quality/quality-check.log' 'quality transcript artifact'
Assert-Contains $workflow '.scratch/health/packages/packages.proof.json' 'package proof artifact'
Assert-Contains $workflow '.scratch/health/packages/packages.proof.diff' 'package diff artifact'

Assert-Contains $harness "[ValidateSet('Quality', 'Packages')]" 'narrow mode parameter'
Assert-Contains $harness '& $pwsh -NoProfile -File $FilePath @Arguments' 'child command execution'
Assert-Contains $harness 'childExitCode = $LASTEXITCODE' 'child exit code capture'
Assert-Contains $harness 'Start-Transcript' 'focused transcript'
Assert-Contains $harness 'Copy-Item -LiteralPath $proofPath' 'proof capture'
Assert-Contains $harness '$proofDiff = & git diff --no-ext-diff -- config/packages.proof.json' 'reviewable proof diff'
Assert-Contains $harness 'git diff failed with exit code $LASTEXITCODE' 'proof diff failure propagation'
Assert-Contains $harness 'Stop-Transcript' 'transcript finalization'
Assert-Contains $harness 'throw $failure' 'command failure propagation'
if ($harness -match '(?im)^\s*exit\b') { throw 'health harness must throw rather than exit' }
Assert-Contains $harness 'function Invoke-HealthCheck' 'injectable command runner seam'
Assert-Contains $harness '[scriptblock] $CommandRunner' 'command runner injection'
Assert-Contains $harness '[string] $EvidenceRoot' 'evidence root injection'
$logCreated = $harness.IndexOf("New-Item -ItemType File -Force -Path `$logPath", [StringComparison]::Ordinal)
$commandCalled = $harness.IndexOf('$result = & $CommandRunner', [StringComparison]::Ordinal)
if ($logCreated -lt 0 -or $commandCalled -le $logCreated) {
    throw 'transcript path must be created before command execution'
}
Assert-Contains $harness "Test-Path -LiteralPath `$proofCopy -PathType Leaf" 'required proof validation'
Assert-Contains $harness "Test-Path -LiteralPath `$diffPath -PathType Leaf" 'required diff validation'
if ($harness -match '(?im)\bgit\s+(commit|push)\b') {
    throw 'health harness must never write back to the repository'
}

$healthScript = Join-Path $root 'tools\ci\Invoke-HealthCheck.ps1'
. $healthScript -NoRun
$fakeRoot = Join-Path ([IO.Path]::GetTempPath()) ("health-fake-repo-" + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $fakeRoot 'tools\host'), `
        (Join-Path $fakeRoot 'config') | Out-Null
    @'
Write-Output 'quality success output'
exit 0
'@ | Set-Content -LiteralPath (Join-Path $fakeRoot 'tools\host\Invoke-QualityCheck.ps1')
    @'
param([Parameter(ValueFromRemainingArguments)] [string[]] $Arguments)
Write-Output "packages args: $($Arguments -join ',')"
Set-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\config\packages.proof.json') `
    -Value '{"proof":"proposed"}'
exit 0
'@ | Set-Content -LiteralPath (Join-Path $fakeRoot 'tools\host\Invoke-WinMintCli.ps1')
    '{"proof":"baseline"}' | Set-Content -LiteralPath (Join-Path $fakeRoot 'config\packages.proof.json')
    & git -C $fakeRoot init --quiet
    & git -C $fakeRoot add .
    & git -C $fakeRoot -c user.name=Contract -c user.email=contract@example.invalid `
        commit --quiet -m baseline

    $qualityEvidence = Join-Path $fakeRoot '.scratch\quality'
    $packageEvidence = Join-Path $fakeRoot '.scratch\packages'
    Invoke-HealthCheck -Mode Quality -RepoRoot $fakeRoot -EvidenceRoot $qualityEvidence | Out-Null
    Invoke-HealthCheck -Mode Packages -RepoRoot $fakeRoot -EvidenceRoot $packageEvidence | Out-Null
    $qualityLog = Join-Path $qualityEvidence 'quality-check.log'
    $packageLog = Join-Path $packageEvidence 'packages-check.log'
    if ((Get-Content -LiteralPath $qualityLog -Raw) -notmatch 'quality success output') {
        throw 'child quality output was not retained in transcript'
    }
    if ((Get-Content -LiteralPath $packageLog -Raw) -notmatch 'health signal: .* -- packages-check' -or
        (Get-Content -LiteralPath $packageLog -Raw) -notmatch 'packages args: packages-check') {
        throw 'child package arguments were not retained in transcript'
    }
    foreach ($path in @(
            $qualityLog,
            $packageLog,
            (Join-Path $packageEvidence 'packages.proof.json'),
            (Join-Path $packageEvidence 'packages.proof.diff'))) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "health evidence file missing: $path"
        }
    }
    if ((Get-Content -LiteralPath (Join-Path $packageEvidence 'packages.proof.json') -Raw) `
            -notmatch 'proposed') {
        throw 'proposed package proof was not retained'
    }
    if ((Get-Content -LiteralPath (Join-Path $packageEvidence 'packages.proof.diff') -Raw) `
            -notmatch 'proposed') {
        throw 'package proof diff was not retained'
    }

    @'
Write-Output 'quality failure output'
exit 23
'@ | Set-Content -LiteralPath (Join-Path $fakeRoot 'tools\host\Invoke-QualityCheck.ps1')
    $failedEvidence = Join-Path $fakeRoot '.scratch\failed'
    $failed = $false
    try {
        Invoke-HealthCheck -Mode Quality -RepoRoot $fakeRoot -EvidenceRoot $failedEvidence | Out-Null
    }
    catch {
        $failed = $_.Exception.Message -like '*exit code 23*' -and
            (Test-Path -LiteralPath (Join-Path $failedEvidence 'quality-check.log') -PathType Leaf) -and
            ((Get-Content -LiteralPath (Join-Path $failedEvidence 'quality-check.log') -Raw) `
                -match 'quality failure output')
    }
    if (-not $failed) { throw 'failing child command did not propagate after finalization' }
}
finally {
    Remove-Item -LiteralPath $fakeRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Test-HealthWorkflow ok'
