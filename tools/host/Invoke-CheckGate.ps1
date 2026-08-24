#requires -Version 7.6
param(
    [switch] $NoRun,
    [string] $StatusPath = '',
    [string] $RunId = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PsscriptAnalyzerVersion = '1.25.0'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location -LiteralPath $repo
. (Join-Path $repo 'tools\host\CheckStatus.ps1')
. (Join-Path $repo 'tools\host\Write-WinMintHostProgress.ps1')

if ([string]::IsNullOrWhiteSpace($StatusPath)) {
    $StatusPath = Join-Path $repo '.scratch\check-status.json'
}
if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = [guid]::NewGuid().ToString('n')
}

function Invoke-CheckGate {
    param(
        [scriptblock] $NativeExecutor = { param($Command, $Arguments) & $Command @Arguments },
        [scriptblock] $ModuleFinder = { param($Name, $Version) Get-Module -ListAvailable -Name $Name | Where-Object Version -eq ([version]$Version) },
        [scriptblock] $ModuleInstaller = { param($Name, $Version) Install-Module -Name $Name -RequiredVersion $Version -Scope CurrentUser -Force -SkipPublisherCheck },
        [scriptblock] $ModuleImporter = { param($Name, $Version) Import-Module -Name $Name -RequiredVersion $Version -Force },
        [string] $StatusPath = $script:StatusPath,
        [string] $RunId = $script:RunId
    )

    function Write-GateProgress {
        param(
            [Parameter(Mandatory)][string] $Phase,
            [string] $Line = '',
            [string] $Leaf = '',
            [int] $Index = 0,
            [int] $Count = 0
        )
        Write-CheckStatus -Path $StatusPath -RunId $RunId -Phase $Phase -Leaf $Leaf `
            -LastHostLine $Line -Index $Index -Count $Count
        $phaseIndex = switch ($Phase) {
            'format' { 1 }
            'restore' { 2 }
            'build' { 3 }
            'test' { 4 }
            'analyzer' { 5 }
            'contract' { 6 }
            default { 0 }
        }
        if ($phaseIndex -gt 0) {
            Write-WinMintHostPhase -Lane Check -Name $Phase -Index $phaseIndex -Count 6
        }
    }

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

    try {
        Write-GateProgress -Phase format -Line 'dotnet format --verify-no-changes'
        Invoke-CheckedNative -Command 'dotnet' -Arguments @('format', '--verify-no-changes')
        Write-GateProgress -Phase restore -Line 'dotnet restore'
        Invoke-CheckedNative -Command 'dotnet' -Arguments @('restore')
        Write-GateProgress -Phase build -Line 'dotnet build --no-restore'
        Invoke-CheckedNative -Command 'dotnet' -Arguments @('build', '--no-restore')
        Write-GateProgress -Phase test -Line 'dotnet test --no-build'
        Invoke-CheckedNative -Command 'dotnet' -Arguments @(
            'test', '--no-build', '--', '--filter-not-trait', 'Category=S4', '--filter-not-trait', 'Category=S5'
        )

        Write-GateProgress -Phase analyzer -Line 'PSScriptAnalyzer'
        if (-not (& $ModuleFinder 'PSScriptAnalyzer' $PsscriptAnalyzerVersion)) {
            & $ModuleInstaller 'PSScriptAnalyzer' $PsscriptAnalyzerVersion
        }
        & $ModuleImporter 'PSScriptAnalyzer' $PsscriptAnalyzerVersion
        Invoke-CheckedNative -Command 'pwsh' -Arguments @(
            '-NoProfile', '-File', (Join-Path $repo 'tools\host\Invoke-ScriptAnalyzerGate.ps1'),
            '-PsscriptAnalyzerVersion', $PsscriptAnalyzerVersion
        )
        Write-GateProgress -Phase contract -Line 'Invoke-ContractTests'
        Invoke-CheckedNative -Command 'pwsh' -Arguments @(
            '-NoProfile', '-File', (Join-Path $repo 'tests\contract\Invoke-ContractTests.ps1'),
            '-StatusPath', $StatusPath,
            '-RunId', $RunId
        )
        Write-CheckStatus -Path $StatusPath -RunId $RunId -Phase passed -LastHostLine 'just check passed'
        Write-WinMintHostPhase -Lane Check -Name passed -Outcome ok
    }
    catch {
        Write-CheckStatus -Path $StatusPath -RunId $RunId -Phase failed -LastHostLine $_.Exception.Message
        Write-WinMintHostPhase -Lane Check -Name failed -Outcome fail
        throw
    }
}

if (-not $NoRun) {
    Invoke-CheckGate -StatusPath $StatusPath -RunId $RunId
}
