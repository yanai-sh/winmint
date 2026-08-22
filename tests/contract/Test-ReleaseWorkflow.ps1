#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workflow = Get-Content -LiteralPath (Join-Path $root '.github\workflows\release.yml') -Raw

function Assert-Contains([string] $Text, [string] $Needle, [string] $Label) {
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "release workflow contract missing: $Label"
    }
}

function Assert-Matches([string] $Text, [string] $Pattern, [string] $Label) {
    if ($Text -notmatch $Pattern) {
        throw "release workflow contract missing: $Label"
    }
}

function Get-ReleaseJob([string] $Name) {
    $match = [regex]::Match($workflow, "(?ms)^  ${Name}:\r?\n(?<body>.*?)(?=^  (?! )[A-Za-z0-9_-]+:|\z)")
    if (-not $match.Success) { throw "release workflow job missing: $Name" }
    $match.Groups['body'].Value
}

function Get-ActionWith([string] $Job, [string] $Action) {
    $escapedAction = [regex]::Escape($Action)
    $match = [regex]::Match(
        $Job,
        "(?ms)^ {8}uses: $escapedAction@[^\r\n]+\r?\n^ {8}with:\r?\n(?<body>.*?)(?=^ {6}- name:|\z)"
    )
    if (-not $match.Success) { throw "release workflow action missing: $Action" }
    $match.Groups['body'].Value
}

$gate = Get-ReleaseJob 'gate'
$pack = Get-ReleaseJob 'pack'
$upload = Get-ReleaseJob 'upload'

$triggerMatch = [regex]::Match($workflow, '(?ms)^on:\r?\n(?<body>.*?)(?=^permissions:)')
if (-not $triggerMatch.Success) { throw 'release workflow trigger block missing' }
$triggerLines = @($triggerMatch.Groups['body'].Value -split '\r?\n' |
    ForEach-Object { $_.Trim() } | Where-Object { $_ })
if (($triggerLines -join '|') -cne 'push:|tags:|- "v*"') {
    throw "release workflow must trigger only from v* tags, got '$($triggerLines -join '|')'"
}

Assert-Contains $gate 'runs-on: windows-11-arm' 'native ARM64 gate runner'
Assert-Contains $pack 'runs-on: windows-11-arm' 'native ARM64 pack runner'
Assert-Contains $upload 'runs-on: windows-11-arm' 'native ARM64 upload runner'
Assert-Matches $gate 'permissions:\r?\n      contents: read' 'gate read permission'
Assert-Matches $pack 'permissions:\r?\n      contents: read' 'pack read permission'
Assert-Matches $upload 'permissions:\r?\n      contents: write' 'upload write permission'
Assert-Contains $gate 'pwsh -NoProfile -File tools/host/Invoke-CheckGate.ps1' 'shared check gate invocation'
Assert-Contains $pack 'needs: gate' 'pack depends on gate'
Assert-Contains $upload 'needs: pack' 'upload depends on pack'

$uploadArtifact = 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02'
$downloadArtifact = 'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093'
Assert-Contains $pack $uploadArtifact 'pinned official upload-artifact action'
Assert-Contains $upload $downloadArtifact 'pinned official download-artifact action'
Assert-Contains $pack 'name: winmint-release-assets' 'exact artifact name'
Assert-Contains $upload 'name: winmint-release-assets' 'exact downloaded artifact name'

$zip = 'WinMint-${{ github.ref_name }}.zip'
$sha = 'WinMint-${{ github.ref_name }}.zip.sha256'
$artifactWith = Get-ActionWith $pack 'actions/upload-artifact'
$releaseWith = Get-ActionWith $upload 'softprops/action-gh-release'
$assetLinePattern = '(?m)^[ \t]+\.scratch/release/WinMint-\$\{\{ github\.ref_name \}\}\.zip(?:\.sha256)?[ \t]*$'
foreach ($handoff in @(@($artifactWith, 'artifact path handoff'), @($releaseWith, 'release file handoff'))) {
    $paths = [regex]::Matches($handoff[0], $assetLinePattern)
    if ($paths.Count -ne 2 -or
        $paths[0].Value.Trim() -ne ".scratch/release/$zip" -or
        $paths[1].Value.Trim() -ne ".scratch/release/$sha") {
        throw "$($handoff[1]) must contain exactly the zip and SHA sidecar"
    }
}
if ($workflow -match '(?i)sign(?:ing|ed|ature)?|signpath|certificate') {
    throw 'release workflow must remain unsigned and contain no signing step'
}

$jobsMatch = [regex]::Match($workflow, '(?ms)^jobs:\r?\n(?<body>.*)')
$jobNames = @([regex]::Matches($jobsMatch.Groups['body'].Value, '(?m)^ {2}([A-Za-z0-9_-]+):$') |
    ForEach-Object { $_.Groups[1].Value })
$writeJobs = @($jobNames | Where-Object { (Get-ReleaseJob $_) -match 'contents: write' })
if ($writeJobs.Count -ne 1 -or $writeJobs[0] -cne 'upload') {
    throw "only final upload job may declare contents: write, got '$($writeJobs -join ',')'"
}

Write-Output 'Test-ReleaseWorkflow ok'
