#requires -Version 7.6
param([string] $PsscriptAnalyzerVersion)

# Shared `just check` / CI gate. Settings files own the host vs guest split.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($PsscriptAnalyzerVersion)) {
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        Write-Error 'PSScriptAnalyzer not installed. Run: Install-Module -Name PSScriptAnalyzer -Scope CurrentUser'
        exit 1
    }
    Import-Module -Name PSScriptAnalyzer -Force
}
else {
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer | Where-Object Version -eq ([version]$PsscriptAnalyzerVersion))) {
        Write-Error "PSScriptAnalyzer $PsscriptAnalyzerVersion not installed"
        exit 1
    }
    Import-Module -FullyQualifiedName @{ ModuleName = 'PSScriptAnalyzer'; RequiredVersion = $PsscriptAnalyzerVersion } -Force
}

if (-not (Get-Module -Name PSScriptAnalyzer)) {
    Write-Error 'PSScriptAnalyzer not installed. Run: Install-Module -Name PSScriptAnalyzer -Scope CurrentUser'
    exit 1
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$failed = $false

function Invoke-WinMintAnalyzer {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Settings,
        [switch] $Recurse
    )
    $fullPath = Join-Path $repo $Path
    $fullSettings = Join-Path $repo $Settings
    $issues = @(Invoke-ScriptAnalyzer -Path $fullPath -Settings $fullSettings -Recurse:$Recurse)
    if ($issues.Count -eq 0) {
        return
    }
    $script:failed = $true
    Write-Output "PSScriptAnalyzer: $Path"
    $issues | Format-Table -AutoSize | Out-String | Write-Output
}

Invoke-WinMintAnalyzer -Path 'servicing' -Settings 'servicing/PSScriptAnalyzerSettings.psd1' -Recurse
Invoke-WinMintAnalyzer -Path 'tools' -Settings 'tools/PSScriptAnalyzerSettings.psd1' -Recurse
Invoke-WinMintAnalyzer -Path 'tests/contract' -Settings 'tools/PSScriptAnalyzerSettings.psd1' -Recurse
Invoke-WinMintAnalyzer -Path 'payload' -Settings 'tools/PSScriptAnalyzerSettings.psd1' -Recurse
Invoke-WinMintAnalyzer -Path 'winmint.ps1' -Settings 'tools/PSScriptAnalyzerSettings.guest.psd1'

if ($failed) {
    exit 1
}
Write-Output 'PSScriptAnalyzer: clean'
