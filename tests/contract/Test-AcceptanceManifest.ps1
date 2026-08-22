#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools\AcceptanceManifest.ps1')

function Assert-Throws {
    param([scriptblock] $Action, [string] $Message)
    try { & $Action } catch { return }
    throw $Message
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('winmint-acceptance-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $profile = Join-Path $tmp 'profile.json'
    $source = Join-Path $tmp 'source.iso'
    $output = Join-Path $tmp 'winmint_Test.iso'
    Set-Content -LiteralPath $profile -Value '{"schemaVersion":"winmint.profile/v1"}' -Encoding utf8NoBOM
    Set-Content -LiteralPath $source -Value 'source bytes' -NoNewline -Encoding utf8NoBOM
    Set-Content -LiteralPath $output -Value 'output bytes' -NoNewline -Encoding utf8NoBOM
    $manifestPath = Join-Path $tmp 'acceptance.manifest.json'
    Write-WinMintAcceptanceManifest -Path $manifestPath -AcceptanceKind HostApply -Outcome green `
        -Lane Test -RepositoryRoot $repo -CommitSha ('a' * 40) -ProfilePath $profile `
        -SourceIsoPath $source -OutputIsoPath $output `
        -SourceEvidenceSchemas @('winmint.image.evidence/v1', 'winmint.apply.acceptance/v1') `
        -ArtifactPaths @('winmint_Test.iso', 'evidence.json') | Out-Null
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    Assert-WinMintAcceptanceManifest -Manifest $manifest | Out-Null
    if ($manifest.sourceIso.length -le 0 -or $manifest.sourceIso.sha256 -notmatch '^[0-9a-f]{64}$') {
        throw 'green manifest did not bind Source ISO bytes'
    }
    if ([string]$manifest.profileSha256 -notmatch '^[0-9a-f]{64}$' -or
        [string]$manifest.outputIsoSha256 -notmatch '^[0-9a-f]{64}$') {
        throw 'green manifest did not bind profile/output bytes'
    }

    Assert-Throws { Assert-WinMintAcceptanceManifest -Manifest ([pscustomobject]@{
            schemaVersion = 'winmint.acceptance.manifest/v1'; acceptanceKind = 'GateB'; outcome = 'green'
            lane = 'Release'; sourceEvidenceSchemas = @('winmint.image.evidence/v1')
            artifactPaths = @('out.iso')
        }) } 'malformed green record was accepted'
    Assert-Throws { Assert-WinMintAcceptanceManifest -Manifest ([pscustomobject]@{
            schemaVersion = 'winmint.acceptance.manifest/v1'; acceptanceKind = 'Smoke'; outcome = 'green'
            commitSha = ('a' * 40); profileSha256 = ('b' * 64); outputIsoSha256 = ('c' * 64)
            sourceIso = @{ sha256 = ('d' * 64); length = 1 }; lane = 'Test'
            sourceEvidenceSchemas = @('winmint.image.evidence/v1')
            artifactPaths = @('C:/secret/out.iso')
        }) } 'absolute artifact path was accepted'
    Assert-Throws { Normalize-WinMintArtifactPath 'C:drive-relative.json' } 'drive-relative artifact path was accepted'
    Assert-Throws { Normalize-WinMintArtifactPath 'evidence/./result.json' } 'dot-segment artifact path was accepted'
    Assert-Throws { Normalize-WinMintArtifactPath 'Evidence/PASSWORDS/result.json' } 'secret artifact path was accepted'
    Assert-Throws { Assert-WinMintAcceptanceManifest -Manifest ([pscustomobject]@{
            schemaVersion = 'winmint.acceptance.manifest/v1'; acceptanceKind = 'Smoke'; outcome = 'green'
            commitSha = ('a' * 40); profileSha256 = ('b' * 64); outputIsoSha256 = ('c' * 64)
            sourceIso = @{ sha256 = ('d' * 64); length = 1 }; lane = 'Test'
            sourceEvidenceSchemas = @('winmint.image.evidence/v1')
            artifactPaths = @('tests/fixtures/smoke-evidence/evidence.json')
        }) } 'fixture-only green record was accepted'
    Assert-Throws { Assert-WinMintAcceptanceManifest -Manifest ([pscustomobject]@{
            schemaVersion = 'winmint.acceptance.manifest/v1'; acceptanceKind = 'GateB'; outcome = 'green'
            commitSha = ('a' * 40); profileSha256 = ('b' * 64); outputIsoSha256 = ('c' * 64)
            sourceIso = @{ sha256 = ('d' * 64); length = 1 }; lane = 'Release'; packageStrict = $false
            sourceEvidenceSchemas = @('winmint.image.evidence/v1', 'winmint.apply.acceptance/v1')
            artifactPaths = @('evidence.json')
        }) } 'non-strict Gate B record was accepted'
    Assert-Throws { Assert-WinMintAcceptanceManifest -Manifest ([pscustomobject]@{
            schemaVersion = 'winmint.acceptance.manifest/v1'; acceptanceKind = 'Primary'; outcome = 'green'
            commitSha = ('a' * 40); profileSha256 = ('b' * 64); outputIsoSha256 = ('c' * 64)
            sourceIso = @{ sha256 = ('d' * 64); length = 1 }; lane = 'Release'; packageStrict = $true
            sourceEvidenceSchemas = @('winmint.image.evidence/v1')
            artifactPaths = @('evidence.json')
        }) } 'Primary record without FirstLogon evidence was accepted'
    Assert-Throws { Assert-WinMintAcceptanceManifest -Manifest ([pscustomobject]@{
            schemaVersion = 'winmint.acceptance.manifest/v1'; acceptanceKind = 'Smoke'; outcome = 'green'
            commitSha = ('a' * 40); profileSha256 = ('b' * 64); outputIsoSha256 = ('c' * 64)
            sourceIso = @{ sha256 = ('d' * 64); length = 1 }; lane = 'Release'
            sourceEvidenceSchemas = @(
                'winmint.image.evidence/v1',
                'winmint.provisioning.evidence/v1',
                'winmint.smoke.acceptance/v1'
            )
            artifactPaths = @('evidence.json')
        }) } 'Release-lane Smoke record was accepted'

    $smoke = Get-Content -LiteralPath (Join-Path $repo 'tools\vm\Invoke-Smoke.ps1') -Raw
    $hostApply = Get-Content -LiteralPath (Join-Path $repo 'tools\apply\Invoke-HostApply.ps1') -Raw
    $gateB = Get-Content -LiteralPath (Join-Path $repo 'tools\apply\Invoke-PrimaryGate.ps1') -Raw
    $wizard = Get-Content -LiteralPath (Join-Path $repo 'tools\apply\Invoke-PrimaryGateWizard.ps1') -Raw
    if ($smoke -notmatch 'Write-WinMintAcceptanceManifest' -or
        $smoke -notmatch 'if \(-not \$SkipApply\)' -or
        $smoke.IndexOf('if ($AssertOnly)') -gt $smoke.IndexOf('Write-WinMintAcceptanceManifest')) {
        throw 'Smoke manifest wiring is not full-mode-only or follows AssertOnly'
    }
    if ($hostApply -notmatch 'Write-WinMintAcceptanceManifest' -or
        $hostApply -notmatch '\$AcceptanceKind' -or
        $hostApply -notmatch '-Outcome failed' -or
        $hostApply -notmatch 'if \(-not \$AssertOnly -and -not \$SkipApply' -or
        $hostApply.IndexOf('if ($AssertOnly)') -gt $hostApply.IndexOf('-Outcome green')) {
        throw 'Host Apply manifest wiring is missing or reachable from AssertOnly'
    }
    if ($gateB -notmatch 'AcceptanceKind GateB' -or $gateB -match 'AcceptanceKind Primary') {
        throw 'Gate B is not explicitly distinct from Primary'
    }
    if ($wizard -notmatch 'AcceptanceKind Primary' -or
        $wizard -notmatch 'Confirm-Yes ''packages\.evidence\.json green AND FU HKLM baseline present\?''' -or
        $wizard -notmatch 'primary-evidence' -or
        $wizard -notmatch 'Normalize-WinMintArtifactPath' -or
        $wizard -notmatch 'winmint\.packages\.evidence/v1' -or
        $wizard -notmatch 'preWipeOnly' -or
        $wizard -notmatch 'Gate B acceptance manifest is missing' -or
        $wizard -notmatch 'Primary evidence must be copied from outside the Gate B workdir' -or
        $wizard -notmatch 'Primary evidence lacks a complete live provisioning run') {
        throw 'Primary manifest is not behind the confirmed checklist'
    }

    if ($smoke -notmatch '\$runId = \[guid\]::NewGuid\(\)\.ToString' -or
        $smoke -notmatch 'if \(\$AssertOnly\)' -or
        $smoke -match 'if \(-not \$AssertOnly -and -not \$SkipApply\)') {
        throw 'Smoke full-mode failure projection is incomplete or AssertOnly can write acceptance'
    }

    $ledgerRoot = Join-Path $repo 'docs\evidence\acceptance'
    if (Test-Path -LiteralPath $ledgerRoot) {
        Get-ChildItem -LiteralPath $ledgerRoot -Filter '*.json' -File -Recurse |
            ForEach-Object {
                $ledger = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
                Assert-WinMintAcceptanceManifest -Manifest $ledger -AllowFailed | Out-Null
                if ((Split-Path -Leaf (Split-Path -Parent $_.FullName)) -cne [string]$ledger.commitSha) {
                    throw "ledger directory does not match commitSha: $($_.FullName)"
                }
            }
    }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Test-AcceptanceManifest ok'
exit 0
