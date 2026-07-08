#Requires -Version 7.6
<#
.SYNOPSIS
    Preview the WinMint setup splash or build wizard locally.

.DESCRIPTION
    -Native launches the native Direct2D splash host with --preview (Escape closes).
    -Wizard launches the WebView2 build wizard with --preview (Escape closes).
    Default is -Wizard when neither switch is passed.

.EXAMPLE
    pwsh -NoProfile -File .\tools\dev\Show-WinMintSplash.ps1

.EXAMPLE
    pwsh -NoProfile -File .\tools\dev\Show-WinMintSplash.ps1 -Native

.EXAMPLE
    pwsh -NoProfile -File .\tools\dev\Show-WinMintSplash.ps1 -Wizard
#>
[CmdletBinding()]
param(
    [switch]$Native,
    [switch]$Wizard
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:WinMintRepositoryRoot = $root
. (Join-Path $root 'src\runtime\image\Core.ps1')
. (Join-Path $root 'tests\setup-shell\SetupShell.TestSupport.ps1')
$shellAssets = Join-Path $root 'assets\runtime\setup\setup-shell'

if ($Native -and $Wizard) {
    throw 'Use -Native or -Wizard, not both.'
}

if (-not $Native) {
    $Wizard = $true
}

$hostExe = if ($Native) {
    Get-WinMintSetupShellNativeHostPath -RepositoryRoot $root
}
else {
    Get-WinMintSetupShellWizardHostPath -RepositoryRoot $root
}

if ($Wizard) {
    Write-Host ''
    Write-Host "WebView2 build wizard preview ($((Get-WinMintHostSetupShellBinArch))). Press Escape to close."
    Write-Host ''
    $arguments = @(
        '--wizard',
        '--shell-root', $shellAssets,
        '--repo-root', $root,
        '--preview',
        '--log'
    )
    $proc = Start-Process -FilePath $hostExe -ArgumentList $arguments -PassThru -Wait
    if ($proc.ExitCode -ne 0) {
        throw "WinMintSetupShell.exe exited with code $($proc.ExitCode). Is WebView2 runtime installed?"
    }
    Write-Host 'Wizard closed.'
    return
}

$workspace = New-WinMintSetupShellTestWorkspace -Root $root
Copy-Item -LiteralPath (Join-Path $root 'tests\fixtures\setup-shell\status-running.json') -Destination $workspace.StatusPath -Force
@{
    phase = 'running'; startedAt = (Get-Date -Format o); updatedAt = (Get-Date -Format o)
    profileName = 'Preview'; message = ''
} | ConvertTo-Json | Set-Content -LiteralPath $workspace.ControlPath -Encoding utf8

$argLine = @(
    "--shell-root `"$($workspace.WorkDir)`""
    "--status `"$($workspace.StatusPath)`""
    "--control `"$($workspace.ControlPath)`""
    '--poll-ms', '500', '--min-start-dwell-ms', '0', '--min-complete-dwell-ms', '400'
    '--preview', '--log'
) -join ' '

Write-Host ''
Write-Host "Native Direct2D splash preview ($((Get-WinMintHostSetupShellBinArch))). Press Escape to close."
Write-Host ''
$proc = Start-Process -FilePath $hostExe -ArgumentList $argLine -PassThru -Wait
if ($proc.ExitCode -ne 0) {
    throw "WinMintSetupShell.exe exited with code $($proc.ExitCode). Is WebView2 runtime installed?"
}
Write-Host 'Splash closed.'
