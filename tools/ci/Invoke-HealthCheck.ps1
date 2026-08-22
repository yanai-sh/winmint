#requires -Version 7.6
<#
.SYNOPSIS
  Run one independent live health signal and preserve a short-lived transcript.
#>
param(
    [ValidateSet('Quality', 'Packages')]
    [string] $Mode = 'Quality',

    [string] $EvidenceRoot,

    [switch] $NoRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-HealthCheck {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Quality', 'Packages')]
        [string] $Mode,

        [Parameter(Mandatory)]
        [string] $RepoRoot,

        [string] $EvidenceRoot = (Join-Path $RepoRoot (Join-Path '.scratch\health' $Mode.ToLowerInvariant())),

        [scriptblock] $CommandRunner = {
            param([string] $FilePath, [string[]] $Arguments)
            $pwsh = (Get-Command pwsh -CommandType Application -ErrorAction Stop |
                Select-Object -First 1).Source
            $output = & $pwsh -NoProfile -File $FilePath @Arguments 2>&1 | Out-String
            $childExitCode = $LASTEXITCODE
            [pscustomobject]@{
                ExitCode = $childExitCode
                Output   = $output.TrimEnd()
            }
        }
    )

    $logName = if ($Mode -eq 'Quality') { 'quality-check.log' } else { 'packages-check.log' }
    $logPath = Join-Path $EvidenceRoot $logName
    $transcriptStarted = $false
    $failure = $null
    $exitCode = 0

    New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
    New-Item -ItemType File -Force -Path $logPath | Out-Null
    Set-Location -LiteralPath $RepoRoot

    try {
        Start-Transcript -LiteralPath $logPath -Force | Out-Null
        $transcriptStarted = $true

        $scriptPath = if ($Mode -eq 'Quality') {
            Join-Path $RepoRoot 'tools\host\Invoke-QualityCheck.ps1'
        }
        else {
            Join-Path $RepoRoot 'tools\host\Invoke-WinMintCli.ps1'
        }
        $arguments = if ($Mode -eq 'Quality') { @() } else { @('--', 'packages-check') }
        Write-Host "health signal: $scriptPath $($arguments -join ' ')"
        $result = & $CommandRunner $scriptPath ([string[]]$arguments)
        if ($null -ne $result.Output) { Write-Host $result.Output }
        $exitCode = [int]$result.ExitCode
        if ($exitCode -ne 0) {
            $failure = "Health command failed with exit code $exitCode"
        }
    }
    catch {
        $failure = $_
        $exitCode = 1
    }
    finally {
        try {
            if ($Mode -eq 'Packages') {
                $proofPath = Join-Path $RepoRoot 'config\packages.proof.json'
                $proofCopy = Join-Path $EvidenceRoot 'packages.proof.json'
                $diffPath = Join-Path $EvidenceRoot 'packages.proof.diff'
                if (Test-Path -LiteralPath $proofPath -PathType Leaf) {
                    Copy-Item -LiteralPath $proofPath -Destination $proofCopy -Force
                }
                $proofDiff = & git diff --no-ext-diff -- config/packages.proof.json
                if ($LASTEXITCODE -ne 0) { throw "git diff failed with exit code $LASTEXITCODE" }
                $proofDiff | Out-File -LiteralPath $diffPath -Encoding utf8
                if (-not (Test-Path -LiteralPath $proofCopy -PathType Leaf)) {
                    throw 'Expected config/packages.proof.json was not produced'
                }
                if (-not (Test-Path -LiteralPath $diffPath -PathType Leaf)) {
                    throw 'Expected packages.proof.diff was not produced'
                }
            }
        }
        catch {
            if ($null -eq $failure) { $failure = $_ }
            $exitCode = 1
        }
        finally {
            if ($transcriptStarted) { Stop-Transcript | Out-Null }
        }
    }

    if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
        $failure = 'Expected health transcript was not produced'
        $exitCode = 1
    }
    if ($null -ne $failure) {
        throw $failure
    }
    return $exitCode
}

if (-not $NoRun) {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $invokeArgs = @{
        Mode = $Mode
        RepoRoot = $repoRoot
    }
    if (-not [string]::IsNullOrWhiteSpace($EvidenceRoot)) {
        $invokeArgs.EvidenceRoot = $EvidenceRoot
    }
    Invoke-HealthCheck @invokeArgs | Out-Null
}
