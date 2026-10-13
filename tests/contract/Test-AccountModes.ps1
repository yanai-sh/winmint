#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Assert-Text {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Description
    )
    $text = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    if ($text -notmatch $Pattern) {
        throw "Account-mode contract missing ($Description): $Path"
    }
}

function Assert-NoText {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Description
    )
    $text = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    if ($text -match $Pattern) {
        throw "Account-mode contract forbidden ($Description): $Path"
    }
}

function Assert-ProfileLocalAutoLogon {
    param([Parameter(Mandatory)][string]$ProfilePath)
    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
        throw "Profile missing: $ProfilePath"
    }
    $doc = Get-Content -LiteralPath $ProfilePath -Raw -Encoding utf8 | ConvertFrom-Json
    if ($doc.account.mode -ne 'localAutoLogon') {
        throw "Sample profile must be localAutoLogon: $ProfilePath (mode=$($doc.account.mode))"
    }
}

$profileCs = Join-Path $repo 'src\WinMint.Orchestrator\Profile.cs'
Assert-Text -Path $profileCs -Pattern 'LocalAutoLogonMode\s*=\s*"localAutoLogon"' -Description 'LocalAutoLogonMode constant'
Assert-NoText -Path $profileCs -Pattern 'OobeLocalMode|oobeLocal' -Description 'no oobeLocal mode'

$buildPlan = Join-Path $repo 'src\WinMint.Orchestrator\BuildPlan.cs'
Assert-Text -Path $buildPlan -Pattern 'AccountProfile\.LocalAutoLogonMode' -Description 'BuildPlan localAutoLogon'
Assert-Text -Path $buildPlan -Pattern 'account\.password\.missing' -Description 'BuildPlan requires password at parse'
Assert-NoText -Path $buildPlan -Pattern 'OobeLocalMode|defer Shell to Supervisor|FirstLogonCommands' -Description 'no deferred Shell / oobeLocal'

$wizardCompile = Join-Path $repo 'src\WinMint.Orchestrator\WizardDraftCompile.cs'
Assert-Text -Path $wizardCompile -Pattern 'AccountProfile\.LocalAutoLogonMode' -Description 'WizardDraftCompile bake-in'
Assert-NoText -Path $wizardCompile -Pattern 'OobeLocalMode|oobeLocal' -Description 'WizardDraftCompile no oobeLocal'
$wizardAccount = Join-Path $repo 'src\WinMint.Wizard\ViewModels\AccountStageViewModel.cs'
Assert-Text -Path $wizardAccount -Pattern 'IdentityReady' -Description 'Wizard IdentityReady gate'
Assert-NoText -Path $wizardAccount -Pattern 'IsPortable|OobeLocalMode' -Description 'Wizard Account no portable mode'

$proof = Join-Path $repo 'tools\vm\Start-OobeLocalProof.ps1'
if (Test-Path -LiteralPath $proof) {
    throw 'Start-OobeLocalProof.ps1 must be deleted (oobeLocal abandoned)'
}

$sl7 = Join-Path $repo 'samples\sl7.profile.json'
Assert-ProfileLocalAutoLogon -ProfilePath $sl7
$sl7Raw = Get-Content -LiteralPath $sl7 -Raw -Encoding utf8
if ($sl7Raw -notmatch '"passwordPath"') {
    throw 'sl7.profile.json must keep passwordPath (maintainer Smoke / Primary pin)'
}

foreach ($name in @('smoke.profile.json', 'acceptance.profile.json')) {
    Assert-ProfileLocalAutoLogon -ProfilePath (Join-Path $repo "samples\$name")
}

$justfile = Join-Path $repo 'Justfile'
Assert-Text -Path $justfile -Pattern 'samples/sl7\.profile\.json' -Description 'Justfile smoke default sl7 profile'

foreach ($smokeScript in @('tools\vm\Invoke-Smoke.ps1', 'tools\vm\Invoke-SmokeRecipe.ps1')) {
    $path = Join-Path $repo $smokeScript
    Assert-Text -Path $path -Pattern "samples/sl7\.profile\.json" -Description "Smoke default profile in $smokeScript"
    Assert-NoText -Path $path -Pattern 'GuestSecretPath|oobeLocal' -Description "no oobeLocal GuestSecretPath in $smokeScript"
}

Write-Output 'Test-AccountModes ok'
exit 0
