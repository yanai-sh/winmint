#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
function Read-Policy([string] $Rel) {
    $path = Join-Path $root $Rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "missing policy file: $Rel"
    }
    Get-Content -LiteralPath $path -Raw
}

$security = Read-Policy 'SECURITY.md'
$privacy = Read-Policy 'PRIVACY.md'
$signing = Read-Policy 'docs/CODE_SIGNING.md'
$runbook = Read-Policy 'docs/runbooks/release-signing-incident.md'
$readme = Read-Policy 'README.md'
$all = $security + $privacy + $signing + $runbook + $readme

function Assert-Has([string] $Haystack, [string] $Needle, [string] $Label) {
    if ($Haystack.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "policy contract missing: $Label"
    }
}

Assert-Has $all 'Free code signing provided by SignPath.io, certificate by SignPath Foundation.' 'exact SignPath attribution'
Assert-Has $all 'SignPath Foundation' 'publisher'
Assert-Has $privacy 'WinMint does not transfer information to networked systems unless the operator requested that operation.' 'privacy statement'
Assert-Has $privacy 'GitHub' 'privacy GitHub'
Assert-Has $privacy 'Microsoft' 'privacy Microsoft'
Assert-Has $privacy 'WinGet' 'privacy WinGet'
Assert-Has $privacy 'Scoop' 'privacy Scoop'
Assert-Has $signing '## Roles' 'role heading'
Assert-Has $security '## Roles' 'security role heading'
Assert-Has $signing 'Authors / committers / reviewers' 'authors role'
Assert-Has $signing 'Approvers' 'approvers role'
Assert-Has $signing 'WinMint PE' 'artifact class WinMint PE'
Assert-Has $signing 'Upstream PE' 'artifact class upstream PE'
Assert-Has $signing 'Hash-only' 'artifact class hash-only'
Assert-Has $signing 'manual SignPath approval' 'manual approval'
Assert-Has $security 'Revocation' 'revocation heading'
Assert-Has $runbook 'Disable the `release` workflow' 'incident disable workflow'
Assert-Has $all 'signed ISO' 'signed-ISO denial mention'
Assert-Has $signing 'Calling it a signed ISO is false' 'signed-ISO denial'
Assert-Has $signing 'unsigned' 'unsigned status'
Assert-Has $signing 'Authenticode is deferred' 'deferred status'
Assert-Has $signing 'Do not apply to SignPath' 'do not apply to SignPath'
Assert-Has $security 'Authenticode is deferred' 'security deferred status'
Assert-Has $signing 'Authenticode' 'Authenticode term'
Assert-Has $readme 'Code signing policy' 'README Code signing policy link'
Assert-Has $security 'no installed WinMint service' 'no uninstall / portable'
Assert-Has $security 'Supervisor erases itself' 'self-erasing Supervisor'
Assert-Has $security 'LaunchApply' 'destructive WinPE'
Assert-Has $security 'no SmartScreen or antivirus guarantee' 'no SmartScreen guarantee'

Write-Output 'Test-ReleaseSigningPolicy ok'
