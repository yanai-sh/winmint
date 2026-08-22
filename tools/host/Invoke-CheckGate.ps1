#requires -Version 7.6
param([switch] $NoRun)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PsscriptAnalyzerVersion = '1.25.0'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location -LiteralPath $repo

function Invoke-CheckGate {
    param(
        [scriptblock] $NativeExecutor = { param($Command, $Arguments) & $Command @Arguments },
        [scriptblock] $ModuleFinder = { param($Name, $Version) Get-Module -ListAvailable -Name $Name | Where-Object Version -eq ([version]$Version) },
        [scriptblock] $ModuleInstaller = { param($Name, $Version) Install-Module -Name $Name -RequiredVersion $Version -Scope CurrentUser -Force -SkipPublisherCheck },
        [scriptblock] $ModuleImporter = { param($Name, $Version) Import-Module -Name $Name -RequiredVersion $Version -Force }
    )

    function Invoke-CheckedNative {
        param(
            [Parameter(Mandatory)][string] $Command,
            [Parameter(Mandatory)][string[]] $Arguments
        )

        & $NativeExecutor $Command $Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "$Command failed with exit code $LASTEXITCODE"
        }
    }

    Invoke-CheckedNative -Command 'dotnet' -Arguments @('format', '--verify-no-changes')
    Invoke-CheckedNative -Command 'dotnet' -Arguments @('restore')
    Invoke-CheckedNative -Command 'dotnet' -Arguments @('build', '--no-restore')
    Invoke-CheckedNative -Command 'dotnet' -Arguments @(
        'test', '--no-build', '--', '--filter-not-trait', 'Category=S4', '--filter-not-trait', 'Category=S5'
    )

    if (-not (& $ModuleFinder 'PSScriptAnalyzer' $PsscriptAnalyzerVersion)) {
        & $ModuleInstaller 'PSScriptAnalyzer' $PsscriptAnalyzerVersion
    }
    & $ModuleImporter 'PSScriptAnalyzer' $PsscriptAnalyzerVersion
    Invoke-CheckedNative -Command 'pwsh' -Arguments @(
        '-NoProfile', '-File', (Join-Path $repo 'tools\host\Invoke-ScriptAnalyzerGate.ps1'),
        '-PsscriptAnalyzerVersion', $PsscriptAnalyzerVersion
    )
    Invoke-CheckedNative -Command 'pwsh' -Arguments @(
        '-NoProfile', '-File', (Join-Path $repo 'tests\contract\Invoke-ContractTests.ps1')
    )
}

if (-not $NoRun) {
    Invoke-CheckGate
}
