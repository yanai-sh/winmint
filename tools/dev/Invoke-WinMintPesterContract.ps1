#Requires -Version 7.6
<#
.SYNOPSIS
    Run WinMint Pester contract tests (profile invariants + focused wiring gates).

.EXAMPLE
    pwsh -NoProfile -File .\tools\dev\Invoke-WinMintPesterContract.ps1
#>
[CmdletBinding()]
param(
    [string]$TestPath,
    [ValidateSet('Minimal', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Verbosity = 'Normal'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location -LiteralPath $repoRoot

$minVersion = [version]'5.5.0'
$pester = Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version -ge $minVersion } |
    Sort-Object Version -Descending |
    Select-Object -First 1
if (-not $pester) {
    Write-Host "Installing Pester $minVersion (CurrentUser scope via PSResourceGet)."
    if (-not (Get-Command Install-PSResource -ErrorAction SilentlyContinue)) {
        throw 'Install-PSResource was not found (Microsoft.PowerShell.PSResourceGet). Use PowerShell 7.4+ (WinMint requires 7.6.2+).'
    }
    # NuGet range: minimum inclusive 5.5.0 (PSResourceGet treats bare "5.5.0" as exact, not minimum).
    Install-PSResource -Name Pester -Version '[5.5.0,)' -Scope CurrentUser -TrustRepository -Quiet -AcceptLicense -ErrorAction Stop
}

Import-Module Pester -MinimumVersion $minVersion -ErrorAction Stop

$resolvedTestPath = if ($TestPath) { $TestPath } else { Join-Path $repoRoot 'tests\contract\WinMint.Contract.Tests.ps1' }
if (-not (Test-Path -LiteralPath $resolvedTestPath -PathType Leaf)) {
    throw "Pester test file not found: $resolvedTestPath"
}

$invokeParams = @{
    Path     = $resolvedTestPath
    PassThru = $true
}
if ($Verbosity -in @('Detailed', 'Diagnostic')) {
    $invokeParams['Output'] = 'Detailed'
}
$result = Invoke-Pester @invokeParams
if ($result.FailedCount -gt 0 -or [string]$result.Result -eq 'Failed') {
    exit 1
}
exit 0
