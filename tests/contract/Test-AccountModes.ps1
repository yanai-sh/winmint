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

function Assert-ProfileLocalAutoLogon {
    param([Parameter(Mandatory)][string]$ProfilePath)
    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
        throw "Profile missing: $ProfilePath"
    }
    $doc = Get-Content -LiteralPath $ProfilePath -Raw -Encoding utf8 | ConvertFrom-Json
    if ($doc.account.mode -ne 'localAutoLogon') {
        throw "Sample profile must stay localAutoLogon (ADR-017 proof gate): $ProfilePath (mode=$($doc.account.mode))"
    }
}

$profileCs = Join-Path $repo 'src\WinMint.Orchestrator\Profile.cs'
Assert-Text -Path $profileCs -Pattern 'OobeLocalMode\s*=\s*"oobeLocal"' -Description 'OobeLocalMode constant'
Assert-Text -Path $profileCs -Pattern 'LocalAutoLogonMode\s*=\s*"localAutoLogon"' -Description 'LocalAutoLogonMode constant'

$buildPlan = Join-Path $repo 'src\WinMint.Orchestrator\BuildPlan.cs'
Assert-Text -Path $buildPlan -Pattern 'AccountProfile\.LocalAutoLogonMode' -Description 'BuildPlan localAutoLogon branch'
Assert-Text -Path $buildPlan -Pattern 'AccountProfile\.OobeLocalMode' -Description 'BuildPlan oobeLocal branch'
Assert-Text -Path $buildPlan -Pattern 'Expected.*LocalAutoLogonMode.*OobeLocalMode' -Description 'BuildPlan dual-mode allow-list error'

$curated = Join-Path $repo 'src\WinMint.Orchestrator\CuratedDefaults.cs'
Assert-Text -Path $curated -Pattern 'AccountProfile\.LocalAutoLogonMode' -Description 'CuratedDefaults emit localAutoLogon'
Assert-Text -Path $curated -Pattern 'curated emit stays localAutoLogon' -Description 'CuratedDefaults ADR-017 proof gate comment'

$wizardVm = Join-Path $repo 'src\WinMint.Wizard\ViewModels\WizardViewModel.cs'
Assert-Text -Path $wizardVm -Pattern 'UseBakeIn\(\)' -Description 'Wizard curated path forces bake-in'
Assert-Text -Path $wizardVm -Pattern 'curated.*stay localAutoLogon' -Description 'Wizard curated ADR-017 proof gate comment'

$wizardCompile = Join-Path $repo 'src\WinMint.Orchestrator\WizardDraftCompile.cs'
Assert-Text -Path $wizardCompile -Pattern 'AccountProfile\.LocalAutoLogonMode' -Description 'WizardDraftCompile localAutoLogon'
Assert-Text -Path $wizardCompile -Pattern 'AccountProfile\.OobeLocalMode' -Description 'WizardDraftCompile oobeLocal'

$sl7 = Join-Path $repo 'samples\sl7.profile.json'
Assert-ProfileLocalAutoLogon -ProfilePath $sl7
$sl7Raw = Get-Content -LiteralPath $sl7 -Raw -Encoding utf8
if ($sl7Raw -notmatch '"passwordPath"') {
    throw 'sl7.profile.json must keep passwordPath (maintainer Smoke / Primary pin)'
}

foreach ($name in @('smoke.profile.json', 'acceptance.profile.json', 'israel.profile.json')) {
    Assert-ProfileLocalAutoLogon -ProfilePath (Join-Path $repo "samples\$name")
}

$justfile = Join-Path $repo 'Justfile'
Assert-Text -Path $justfile -Pattern 'samples/sl7\.profile\.json' -Description 'Justfile smoke default sl7 profile'
if ((Get-Content -LiteralPath $justfile -Raw -Encoding utf8) -match 'samples/sl7\.profile\.json.*oobeLocal') {
    throw 'Justfile must not flip sl7 default to oobeLocal'
}

foreach ($smokeScript in @('tools\vm\Invoke-Smoke.ps1', 'tools\vm\Invoke-SmokeRecipe.ps1')) {
    $path = Join-Path $repo $smokeScript
    Assert-Text -Path $path -Pattern "samples/sl7\.profile\.json" -Description "Smoke default profile in $smokeScript"
}

Write-Output 'Test-AccountModes ok'
exit 0
