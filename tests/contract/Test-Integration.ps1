#Requires -Version 7.3
[CmdletBinding()]
param(
    [switch]$RunIsoDryRun,
    [switch]$RunUupHeavy,
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
        $logDir = Join-Path (Join-Path $root 'output') 'integration-test'
        $null = New-Item -ItemType Directory -Path $logDir -Force
        $stdout = Join-Path $logDir 'iso-dry-run.out.log'
        $stderr = Join-Path $logDir 'iso-dry-run.err.log'
        $process = Start-Process `
            -FilePath (Get-Process -Id $PID).Path `
            -ArgumentList @(
                '-NoProfile',
                '-File', (Join-Path $root 'WinMint-CLI.ps1'),
                '-SourceIso', $iso,
                '-Architecture', 'arm64',
                '-DryRun',
                '-NoProgress',
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

if ($RunUupHeavy) {
    if (-not $isAdmin) {
        Write-IntegrationSkip 'UUP heavy integration requires an elevated PowerShell session.'
    }
    else {
        . (Join-Path $root 'src\WinMint\Core.ps1')
        . (Join-Path $root 'src\WinMint\Private\SourcePrep.ps1')
        $script:WinMintRepositoryRoot = $root
        $zip = Get-WinMintTestUupDumpZipFixturePath
        if (-not (Test-WinMintUupDumpZip -Path $zip)) {
            throw "UUP Dump fixture zip is invalid: $zip"
        }
        $result = Invoke-WinMintUupDumpSourcePrep -UupDumpZip $zip -Yes
        if (-not [string]::IsNullOrWhiteSpace([string]$result.GeneratedIso) -and
            (Test-Path -LiteralPath ([string]$result.GeneratedIso) -PathType Leaf)) {
            Write-Host 'UUP heavy integration passed.'
        }
        else {
            throw 'UUP heavy integration did not produce or reuse an ISO.'
        }
    }
}

if (-not $RunIsoDryRun -and -not $RunUupHeavy) {
    Write-Host 'No integration switches selected. Use -RunIsoDryRun or -RunUupHeavy.'
}
