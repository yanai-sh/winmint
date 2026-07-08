#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AppArgs = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'src\runtime\modules\WinMint.Bootstrap\WinMint.Bootstrap.psd1') -Force
$bootstrap = Invoke-WinMintRuntimeBootstrap -Entrypoint $PSCommandPath -Arguments @($AppArgs)
if ($bootstrap.Relaunched) {
    exit $bootstrap.ExitCode
}

$script:WinMintRepositoryRoot = $PSScriptRoot
. (Join-Path $PSScriptRoot 'src\runtime\image\Core.ps1')

$repoRoot = $PSScriptRoot
$shellRoot = Join-Path $repoRoot 'assets\runtime\setup\setup-shell'
$hostExe = Get-WinMintSetupShellHostPath -RepositoryRoot $repoRoot
$arguments = @(
    '--wizard',
    '--shell-root', $shellRoot,
    '--repo-root', $repoRoot,
    '--log'
)
if ('--preview' -in $AppArgs) {
    $arguments += '--preview'
}

& $hostExe @arguments
exit $LASTEXITCODE
