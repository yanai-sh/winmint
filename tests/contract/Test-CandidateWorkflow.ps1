#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workflow = Get-Content -LiteralPath (Join-Path $repo '.github\workflows\ci.yml') -Raw
$candidateScript = Get-Content -LiteralPath (Join-Path $repo 'tools\ci\Publish-WinMintCandidate.ps1') -Raw
$publisher = Get-Content -LiteralPath (Join-Path $repo 'tools\release\Publish-WinMintRelease.ps1') -Raw
$provisioning = Get-Content -LiteralPath (Join-Path $repo 'src\WinMint.Provisioning\WinMint.Provisioning.csproj') -Raw
$winPeApply = Get-Content -LiteralPath (Join-Path $repo 'src\WinMint.WinPeApply\WinMint.WinPeApply.csproj') -Raw

function Assert-Contains([string] $Text, [string] $Needle, [string] $Label) {
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "candidate contract missing: $Label"
    }
}

function Get-CandidateJob([string] $Name) {
    $match = [regex]::Match($workflow, "(?ms)^  ${Name}:\r?\n(?<body>.*?)(?=^  (?! )[A-Za-z0-9_-]+:|\z)")
    if (-not $match.Success) { throw "CI job missing: $Name" }
    $match.Groups['body'].Value
}

$check = Get-CandidateJob 'check'
$candidate = Get-CandidateJob 'candidate'

Assert-Contains $candidate 'needs: check' 'candidate dependency'
Assert-Contains $candidate 'permissions:' 'candidate permissions block'
Assert-Contains $candidate 'contents: read' 'candidate read permission'
Assert-Contains $candidate 'runs-on: windows-11-arm' 'native ARM64 candidate runner'
Assert-Contains $candidate 'timeout-minutes: 45' 'larger candidate timeout'
Assert-Contains $candidate 'tools/ci/Publish-WinMintCandidate.ps1' 'candidate entrypoint'
Assert-Contains $candidate 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02' 'pinned proof upload'
Assert-Contains $candidate 'name: winmint-candidate-proof' 'focused proof artifact'
Assert-Contains $candidate 'retention-days: 1' 'short proof retention'
Assert-Contains $candidate 'if: always()' 'always-upload semantics'
Assert-Contains $candidate 'if-no-files-found: warn' 'failure-tolerant inventory handoff'
Assert-Contains $candidate '.scratch/candidate-proof/candidate-inventory.json' 'inventory proof'
Assert-Contains $candidate '.scratch/candidate-proof/candidate-build.log' 'build log proof'

if ($check -match '(?i)dotnet\s+publish|NativeAOT|AOT publish') {
    throw 'fast check job must not publish'
}
if ($candidate -match 'Invoke-CheckGate') {
    throw 'candidate must not duplicate the deterministic gate'
}
if ($workflow -match '(?im)^\s+contents:\s+write\b|softprops/action-gh-release|signpath|certificate') {
    throw 'CI candidate must remain read-only and unsigned'
}

Assert-Contains $candidateScript 'Publish-WinMintRelease.ps1' 'reuse release publisher'
Assert-Contains $candidateScript 'Get-WinMintReleaseInventory.ps1' 'inventory generation'
Assert-Contains $candidateScript '-Runtime win-arm64' 'candidate runtime'
Assert-Contains $candidateScript '-Configuration Release' 'Release configuration'
Assert-Contains $candidateScript '-Phase Unsigned' 'unsigned inventory'
Assert-Contains $candidateScript '-OutFile $inventoryPath' 'successful-path inventory output'
Assert-Contains $candidateScript 'doc.commit -cne $commit' 'commit-tied inventory validation'
Assert-Contains $candidateScript 'doc.tag -cne $tag' 'tag-tied inventory validation'
Assert-Contains $candidateScript 'if ($path -notin $paths)' 'required executable inventory entries'
Assert-Contains $candidateScript 'Stop-Transcript' 'safe transcript cleanup'
if ($candidateScript -match '(?i)continue-on-error') { throw 'candidate entrypoint must fail closed' }

$proofCreated = $candidateScript.IndexOf('New-Item -ItemType Directory -Force -Path $proofFull', [StringComparison]::Ordinal)
$transcript = $candidateScript.IndexOf('Start-Transcript -LiteralPath $logPath', [StringComparison]::Ordinal)
$commitRead = $candidateScript.IndexOf('(git rev-parse HEAD)', [StringComparison]::Ordinal)
if ($proofCreated -lt 0 -or $transcript -le $proofCreated -or $commitRead -le $transcript) {
    throw 'transcript must start after proof root creation and before commit setup'
}

$publishPatterns = @(
    'src\\WinMint\.Cli\\WinMint\.Cli\.csproj.*?-r \$Runtime --self-contained true',
    'src\\WinMint\.Wizard\\WinMint\.Wizard\.csproj.*?-r \$Runtime --self-contained true',
    'src\\WinMint\.Provisioning\\WinMint\.Provisioning\.csproj.*?-c \$Configuration.*?-r \$Runtime',
    'src\\WinMint\.WinPeApply\\WinMint\.WinPeApply\.csproj.*?-c \$Configuration.*?-r \$Runtime'
)
foreach ($pattern in $publishPatterns) {
    if ($publisher -notmatch "(?s)$pattern") { throw "release publisher missing exact surface: $pattern" }
}
foreach ($destination in @('bin\cli', 'bin\wizard', 'artifacts\provisioning', 'artifacts\winpe-apply')) {
    Assert-Contains $publisher $destination "staging destination $destination"
}
foreach ($project in @('WinMint.Cli', 'WinMint.Wizard')) {
    $pattern = '(?s)src\\{0}\\{0}\.csproj.*?-c \$Configuration.*?-r \$Runtime --self-contained true' -f $project
    if ($publisher -notmatch $pattern) {
        throw "self-contained win-arm64 publish missing: $project"
    }
}
Assert-Contains $provisioning '<PublishAot Condition="''$(Configuration)'' == ''Release''">true</PublishAot>' 'Provisioning Release NativeAOT'
Assert-Contains $winPeApply '<PublishAot Condition="''$(Configuration)'' == ''Release''">true</PublishAot>' 'WinPeApply Release NativeAOT'
if ($publisher -notmatch '(?s)WinMint\.Provisioning\.csproj.*?-c \$Configuration' -or
    $publisher -notmatch '(?s)WinMint\.WinPeApply\.csproj.*?-c \$Configuration') {
    throw 'AOT publish commands missing Release configuration'
}
Assert-Contains $candidateScript '$originalTagCommit' 'preserve existing candidate tag target'
Assert-Contains $candidateScript 'git update-ref "refs/tags/$tag" $originalTagRef' 'restore existing candidate tag'
Assert-Contains $candidateScript 'git tag --delete $tag' 'delete temporary candidate tag'
Assert-Contains $candidateScript 'finally' 'candidate tag cleanup'

if ($candidateScript -match 'Compress-WinMintRelease|action-gh-release|Set-AuthenticodeSignature|signpath') {
    throw 'candidate must not package, upload a release, or sign'
}

Write-Output 'Test-CandidateWorkflow ok'
