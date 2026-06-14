#Requires -Version 7.3
[CmdletBinding()]
param(
    [switch]$RunIsoDryRun,
    [switch]$RequireAdmin
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')

function Test-IntegrationAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Write-IntegrationSkip {
    param([string]$Reason)
    if ($RequireAdmin) { throw $Reason }
    Write-Warning "Skipping integration test: $Reason"
}

$isAdmin = Test-IntegrationAdministrator

if ($RunIsoDryRun) {
    if (-not $isAdmin) {
        Write-IntegrationSkip 'ISO dry-run integration requires an elevated PowerShell session.'
    }
    else {
        $iso = Get-WinMintTestIsoFixturePath
        $cli = Join-Path $root 'WinMint-CLI.ps1'
        $pwshPath = (Get-Process -Id $PID).Path
        $logDir = Join-Path (Join-Path $root 'output') 'integration-test'
        $null = New-Item -ItemType Directory -Path $logDir -Force
        $tempProfile = Join-Path $logDir 'iso-dry-run.profile.json'

        # Profile is the source of truth: author one with `new`, then `build` it.
        $newOut = Join-Path $logDir 'iso-dry-run.new.out.log'
        $newErr = Join-Path $logDir 'iso-dry-run.new.err.log'
        $newProc = Start-Process `
            -FilePath $pwshPath `
            -ArgumentList @(
                '-NoProfile',
                '-File', $cli,
                'new', $tempProfile,
                '-SourceIso', $iso,
                '-Architecture', 'arm64',
                '-Quiet'
            ) `
            -Wait -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput $newOut -RedirectStandardError $newErr
        if ($newProc.ExitCode -ne 0) {
            throw "ISO dry-run profile authoring failed with exit code $($newProc.ExitCode). Logs: $newOut $newErr"
        }

        $stdout = Join-Path $logDir 'iso-dry-run.out.log'
        $stderr = Join-Path $logDir 'iso-dry-run.err.log'
        $process = Start-Process `
            -FilePath $pwshPath `
            -ArgumentList @(
                '-NoProfile',
                '-File', $cli,
                'build', $tempProfile,
                '-DryRun',
                '-Quiet'
            ) `
            -Wait `
            -PassThru `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr
        if ($process.ExitCode -ne 0) {
            throw "ISO dry-run integration failed with exit code $($process.ExitCode). Logs: $stdout $stderr"
        }
        Write-Host 'ISO dry-run integration passed.'
    }
}

if (-not $RunIsoDryRun) {
    Write-Host 'No integration switches selected. Use -RunIsoDryRun.'
}
