#requires -Version 7.6
<#
.SYNOPSIS
  Writes and validates the provenance-only winmint.acceptance.manifest/v1 projection.

  This file is deliberately a dot-sourced helper. It never decides whether an
  acceptance predicate passed; callers invoke it only after their existing
  assertion has passed.
#>
Set-StrictMode -Version Latest

$script:WinMintAcceptanceKnownSchemas = @(
    'winmint.profile/v1',
    'winmint.jobs/v1',
    'winmint.provisioning.bundle/v1',
    'winmint.provisioning.evidence/v1',
    'winmint.packages.evidence/v1',
    'winmint.provisioning.checkpoint/v1',
    'winmint.smoke.acceptance/v1',
    'winmint.apply.acceptance/v1',
    'winmint.plan.stages/v1',
    'winmint.servicing.stages/v1',
    'winmint.image.evidence/v1',
    'winmint.prepared-media.audit/v1',
    'winmint.packages.proof/v1',
    'winmint.packages.check.request/v1',
    'winmint.packages.check.outcome/v1',
    'winmint.native-packages/v1',
    'winmint.expected-evidence/v1'
)

function Get-WinMintFileSha256 {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File not found: $Path"
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Normalize-WinMintArtifactPath {
    param([Parameter(Mandatory)][string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or
        $Path -match '^[A-Za-z]:' -or $Path -match '^[\\/]{2}' -or
        $Path -match '(^|[\\/])\.\.?([\\/]|$)') {
        throw "artifactPaths must be normalized relative paths: '$Path'"
    }
    $normalized = $Path.Replace('\', '/')
    if ($normalized -match '(?i)(^|/)(password|secret|credential)([^/]*)(/|$)' -or
        $normalized -match '(?i)(^|/)[^/]*\.(password|secret|pem|pfx|key)$') {
        throw "artifactPaths must not expose secrets: '$Path'"
    }
    return $normalized
}

function Assert-WinMintAcceptanceManifest {
    param(
        [Parameter(Mandatory)] $Manifest,
        [switch] $AllowFailed
    )

    if ([string]$Manifest.schemaVersion -cne 'winmint.acceptance.manifest/v1') {
        throw 'unexpected acceptance manifest schemaVersion'
    }
    if ([string]$Manifest.acceptanceKind -notin @('Smoke', 'HostApply', 'GateB', 'Primary')) {
        throw 'acceptanceKind must be Smoke, HostApply, GateB, or Primary'
    }
    $outcome = [string]$Manifest.outcome
    if ($outcome -notin @('green', 'failed')) { throw 'outcome must be green or failed' }
    if ($outcome -eq 'failed' -and -not $AllowFailed) {
        throw 'failed manifests require -AllowFailed'
    }
    if ([string]$Manifest.lane -notin @('Test', 'Release')) { throw 'lane must be Test or Release' }

    foreach ($field in @('commitSha')) {
        if ($Manifest.PSObject.Properties.Name -contains $field -and
            -not [string]::IsNullOrWhiteSpace([string]$Manifest.$field) -and
            [string]$Manifest.$field -notmatch '^[0-9a-f]{40}$') {
            throw "$field must be 40 lowercase hexadecimal characters"
        }
    }
    foreach ($field in @('profileSha256', 'outputIsoSha256')) {
        if ($Manifest.PSObject.Properties.Name -contains $field -and
            -not [string]::IsNullOrWhiteSpace([string]$Manifest.$field) -and
            [string]$Manifest.$field -notmatch '^[0-9a-f]{64}$') {
            throw "$field must be 64 lowercase hexadecimal characters"
        }
    }

    $hasSource = $Manifest.PSObject.Properties.Name -contains 'sourceIso' -and $null -ne $Manifest.sourceIso
    if ($hasSource) {
        if ([string]$Manifest.sourceIso.sha256 -notmatch '^[0-9a-f]{64}$') {
            throw 'sourceIso.sha256 must be 64 lowercase hexadecimal characters'
        }
        if ([long]$Manifest.sourceIso.length -le 0) { throw 'sourceIso.length must be positive' }
    }
    if ($outcome -eq 'green') {
        foreach ($field in @('commitSha', 'profileSha256', 'outputIsoSha256')) {
            $length = if ($field -eq 'commitSha') { 40 } else { 64 }
            if ([string]$Manifest.$field -notmatch ('^[0-9a-f]{' + $length + '}$')) {
                throw "green manifest missing/invalid $field"
            }
        }
        if (-not $hasSource) { throw 'green manifest missing sourceIso identity' }
        $requiredSchemas = switch ([string]$Manifest.acceptanceKind) {
            'Smoke' { @('winmint.image.evidence/v1', 'winmint.provisioning.evidence/v1', 'winmint.smoke.acceptance/v1') }
            'HostApply' { @('winmint.image.evidence/v1', 'winmint.apply.acceptance/v1') }
            'GateB' { @('winmint.image.evidence/v1', 'winmint.apply.acceptance/v1') }
            'Primary' { @('winmint.image.evidence/v1', 'winmint.provisioning.evidence/v1') }
        }
        foreach ($schema in $requiredSchemas) {
            if (@($Manifest.sourceEvidenceSchemas) -notcontains $schema) {
                throw "$($Manifest.acceptanceKind) green manifest missing source evidence schema '$schema'"
            }
        }
        if ($Manifest.acceptanceKind -eq 'Smoke' -and $Manifest.lane -ne 'Test') {
            throw 'Smoke green manifest must use the Test lane'
        }
        if ($Manifest.acceptanceKind -in @('GateB', 'Primary')) {
            if ($Manifest.lane -ne 'Release') { throw "$($Manifest.acceptanceKind) green manifest must use the Release lane" }
            $hasPackageStrict = $Manifest.PSObject.Properties.Name -contains 'packageStrict'
            if (-not $hasPackageStrict -or $Manifest.packageStrict -isnot [bool] -or -not $Manifest.packageStrict) {
                throw "$($Manifest.acceptanceKind) green manifest must be package-strict"
            }
        }
    }

    $schemas = @($Manifest.sourceEvidenceSchemas)
    if ($schemas.Count -eq 0) { throw 'sourceEvidenceSchemas must be nonempty' }
    foreach ($schema in $schemas) {
        if ($script:WinMintAcceptanceKnownSchemas -notcontains [string]$schema) {
            throw "unknown source evidence schema '$schema'"
        }
    }

    $paths = @($Manifest.artifactPaths)
    if ($paths.Count -eq 0) { throw 'artifactPaths must be nonempty' }
    foreach ($path in $paths) {
        $normalized = Normalize-WinMintArtifactPath ([string]$path)
        if ([string]$path -cne $normalized) { throw "artifactPath is not normalized: '$path'" }
        if ($outcome -eq 'green' -and $normalized -match '(^|/)tests/fixtures(/|$)|(^|/)fixture[^/]*(/|$)') {
            throw 'fixture-only artifacts cannot support a green acceptance manifest'
        }
    }
    if ($Manifest.PSObject.Properties.Name -contains 'packageStrict' -and
        $null -ne $Manifest.packageStrict -and $Manifest.packageStrict -isnot [bool]) {
        throw 'packageStrict must be boolean when present'
    }
    return $true
}

function Get-WinMintCurrentCommitSha {
    param([Parameter(Mandatory)][string] $RepositoryRoot)
    $sha = (& git -C $RepositoryRoot rev-parse HEAD 2>$null).Trim().ToLowerInvariant()
    if ($LASTEXITCODE -ne 0 -or $sha -notmatch '^[0-9a-f]{40}$') {
        throw 'Could not resolve current git commit SHA'
    }
    return $sha
}

function Write-WinMintAcceptanceManifest {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][ValidateSet('Smoke', 'HostApply', 'GateB', 'Primary')][string] $AcceptanceKind,
        [Parameter(Mandatory)][ValidateSet('green', 'failed')][string] $Outcome,
        [Parameter(Mandatory)][ValidateSet('Test', 'Release')][string] $Lane,
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][string[]] $SourceEvidenceSchemas,
        [Parameter(Mandatory)][string[]] $ArtifactPaths,
        [string] $ProfilePath,
        [string] $SourceIsoPath,
        [string] $OutputIsoPath,
        [string] $CommitSha,
        [string] $ProfileSha256,
        [string] $SourceIsoSha256,
        [long] $SourceIsoLength = 0,
        [string] $OutputIsoSha256,
        [Nullable[bool]] $PackageStrict
    )

    $manifest = [ordered]@{
        schemaVersion          = 'winmint.acceptance.manifest/v1'
        acceptanceKind         = $AcceptanceKind
        outcome                = $Outcome
        lane                   = $Lane
        sourceEvidenceSchemas  = @($SourceEvidenceSchemas)
        artifactPaths          = @($ArtifactPaths | ForEach-Object { Normalize-WinMintArtifactPath $_ })
    }
    if ($CommitSha) { $manifest.commitSha = $CommitSha.ToLowerInvariant() }
    if ($ProfileSha256) { $manifest.profileSha256 = $ProfileSha256.ToLowerInvariant() }
    if ($SourceIsoSha256 -and $SourceIsoLength -gt 0) {
        $manifest.sourceIso = [ordered]@{ sha256 = $SourceIsoSha256.ToLowerInvariant(); length = $SourceIsoLength }
    }
    if ($OutputIsoSha256) { $manifest.outputIsoSha256 = $OutputIsoSha256.ToLowerInvariant() }
    if ($null -ne $PackageStrict) { $manifest.packageStrict = [bool]$PackageStrict }

    if ($Outcome -eq 'green') {
        if (-not $manifest.Contains('commitSha')) { $manifest.commitSha = Get-WinMintCurrentCommitSha -RepositoryRoot $RepositoryRoot }
        if ($ProfilePath) {
            $actualProfileSha = Get-WinMintFileSha256 -Path $ProfilePath
            if ($manifest.Contains('profileSha256') -and $manifest.profileSha256 -ne $actualProfileSha) {
                throw 'profileSha256 does not match ProfilePath bytes'
            }
            $manifest.profileSha256 = $actualProfileSha
        }
        elseif (-not $manifest.Contains('profileSha256')) {
            throw 'green manifest requires profile bytes or profileSha256'
        }
        if (-not $manifest.Contains('sourceIso')) {
            if ($SourceIsoPath) {
                $manifest.sourceIso = [ordered]@{
                    sha256 = Get-WinMintFileSha256 -Path $SourceIsoPath
                    length = [long](Get-Item -LiteralPath $SourceIsoPath).Length
                }
            } else { throw 'green manifest requires source ISO identity or path' }
        }
        if (-not $manifest.Contains('outputIsoSha256')) { $manifest.outputIsoSha256 = Get-WinMintFileSha256 -Path $OutputIsoPath }
    }

    Assert-WinMintAcceptanceManifest -Manifest ([pscustomobject]$manifest) -AllowFailed:($Outcome -eq 'failed')
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
    return $Path
}
