#requires -Version 7.6
<#
.SYNOPSIS
  #164 proof gate: oobeLocal Output ISO → Hyper-V Online OOBE → Supervisor FirstLogon.

.DESCRIPTION
  Builds/applies with a portable Profile (no baked password), boots with OnlineOobe + Monitor,
  and waits for Smoke Complete using host-only -GuestSecretPath credentials.

  At interactive OOBE, create a local account matching:
    username = account.username in the Profile (default: proof)
    password = contents of .scratch/oobe-local.guest.password

  Expect possible double sign-in (deferred Shell / FirstLogonCommands logoff).

.EXAMPLE
  pwsh -NoProfile -File tools/vm/Start-OobeLocalProof.ps1
#>
param(
    [string] $Work = '.scratch/oobe-local-proof',
    [int] $WallClockMinutes = 180,
    [int] $StallMinutes = 45,
    [switch] $SkipApply,
    [switch] $ElevatedWorker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot
. (Join-Path $repoRoot 'tools/host/WinMintHostConsole.ps1')

$profilePath = Join-Path $repoRoot '.scratch\oobe-local.profile.json'
$guestPasswordPath = Join-Path $repoRoot '.scratch\oobe-local.guest.password'
$log = Join-Path $repoRoot $Work | ForEach-Object { Join-Path $_ 'elevated-oobe-local-proof.log' }

function Ensure-OobeLocalProofArtifacts {
    New-Item -ItemType Directory -Force -Path (Join-Path $repoRoot '.scratch') | Out-Null
    if (-not (Test-Path -LiteralPath $guestPasswordPath -PathType Leaf)) {
        $bytes = [byte[]]::new(18)
        [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
        $pw = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        Set-Content -LiteralPath $guestPasswordPath -Value $pw -NoNewline -Encoding utf8
        Write-Host "Wrote host-only guest password: $guestPasswordPath"
    }
    if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
        $sl7 = Get-Content -LiteralPath (Join-Path $repoRoot 'samples\sl7.profile.json') -Raw -Encoding utf8 | ConvertFrom-Json
        $sl7.account = [pscustomobject]@{
            mode                   = 'oobeLocal'
            username               = 'proof'
            requireWifiDuringOobe  = $true
        }
        $sl7 | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $profilePath -Encoding utf8NoBOM
        Write-Host "Wrote proof Profile: $profilePath"
    }
}

function Invoke-OobeLocalProofWorker {
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) {
        throw 'oobeLocal proof needs elevated pwsh (Apply + Hyper-V). Re-run Start-OobeLocalProof.ps1'
    }

    Ensure-OobeLocalProofArtifacts
    $fixture = Get-Content -LiteralPath (Join-Path $repoRoot 'tests\fixtures\maintainer-host.json') -Raw -Encoding utf8 | ConvertFrom-Json
    $iso = [string]$fixture.sourceIso.path
    if (-not (Test-Path -LiteralPath $iso -PathType Leaf)) {
        throw "Maintainer Source ISO missing: $iso"
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $log) | Out-Null
    Start-Transcript -LiteralPath $log -Force | Out-Null
    try {
        $proofUser = 'proof'
        try {
            $proofUser = [string](Get-Content -LiteralPath $profilePath -Raw -Encoding utf8 | ConvertFrom-Json).account.username
            if ([string]::IsNullOrWhiteSpace($proofUser)) { $proofUser = 'proof' }
        } catch { }
        Write-Host "OobeLocal proof HEAD=$(git rev-parse --short HEAD) Work=$Work"
        Write-Host "At OOBE create local user '$proofUser' with password from: $guestPasswordPath"
        Write-Host 'Expect possible second sign-in after deferred Shell (FirstLogonCommands logoff).'
        $smoke = Join-Path $repoRoot 'tools\vm\Invoke-Smoke.ps1'
        $args = @{
            Iso               = $iso
            Work              = $Work
            ProfilePath       = $profilePath
            WallClockMinutes  = $WallClockMinutes
            StallMinutes      = $StallMinutes
            GuestSecretPath  = $guestPasswordPath
            Monitor          = $true
            OnlineOobe       = $true
        }
        if ($SkipApply) { $args.SkipApply = $true }
        & $smoke @args
        exit $LASTEXITCODE
    }
    finally {
        Stop-Transcript | Out-Null
    }
}

if ($ElevatedWorker) {
    Invoke-OobeLocalProofWorker
    exit $LASTEXITCODE
}

Ensure-OobeLocalProofArtifacts
$self = Join-Path $repoRoot 'tools\vm\Start-OobeLocalProof.ps1'
$pwshExe = (Get-Command pwsh.exe -ErrorAction Stop).Source
$inner = @('-ElevatedWorker', '-Work', $Work, '-WallClockMinutes', "$WallClockMinutes", '-StallMinutes', "$StallMinutes")
if ($SkipApply) { $inner += '-SkipApply' }

$result = Start-WinMintHostConsole -Elevate -RepoRoot $repoRoot -Work $Work -File $self `
    -ArgumentList $inner -PwshExe $pwshExe -TranscriptPath $log

if ($result.disposition -eq 'RunHere') {
    Invoke-OobeLocalProofWorker
    exit $LASTEXITCODE
}

$proofUser = 'proof'
try {
    $proofUser = [string](Get-Content -LiteralPath $profilePath -Raw -Encoding utf8 | ConvertFrom-Json).account.username
    if ([string]::IsNullOrWhiteSpace($proofUser)) { $proofUser = 'proof' }
} catch { }
Write-Host "Spawned elevated oobeLocal proof ($($result.disposition)). Log: $log"
Write-Host "OOBE: create local user '$proofUser' / password in $guestPasswordPath"
exit 0
