#requires -Version 7.6
<#
.SYNOPSIS
  Prove Prepared media isolation across two Applies (native ARM64, elevated).
.NOTES
  Not in `just check`. Requires a Source ISO, disk space, and ImageServicing time.
#>
param(
    [string] $SourceIso = '',
    [string] $ProfileA = 'samples/smoke.profile.json',
    [string] $ProfileB = 'samples/acceptance.profile.json',
    [string] $Work = '',
    [int] $WimIndex = 3,
    [switch] $IncludeSmoke,
    [switch] $WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $repoRoot

function Assert-WinMintNativeArm64 {
    $os = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    $proc = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    $pa = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE')
    $wow = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITEW6432')
    if ($os -ne 'Arm64' -or $proc -ne 'Arm64') {
        throw "warm-media acceptance requires native ARM64 (OSArchitecture=$os, ProcessArchitecture=$proc, PROCESSOR_ARCHITECTURE=$pa, PROCESSOR_ARCHITEW6432=$wow)"
    }
    [ordered]@{
        osArchitecture             = $os
        processArchitecture        = $proc
        processorArchitecture      = $pa
        processorArchitectureW6432 = $wow
        pwshVersion                = $PSVersionTable.PSVersion.ToString()
    }
}

function Get-Evidence([string] $Dir) {
    Get-Content -LiteralPath (Join-Path $Dir 'evidence.json') -Raw | ConvertFrom-Json
}

$diag = Assert-WinMintNativeArm64
if ($PSVersionTable.PSVersion -lt [version]'7.6') {
    throw "pwsh 7.6+ required, got $($PSVersionTable.PSVersion)"
}

Write-Output 'Warm-media acceptance matrix:'
$diag.GetEnumerator() | ForEach-Object { Write-Output ("  {0}={1}" -f $_.Key, $_.Value) }
Write-Output "  ProfileA=$ProfileA"
Write-Output "  ProfileB=$ProfileB"
Write-Output "  WimIndex=$WimIndex"

if ($WhatIf) {
    Write-Output 'WhatIf: no Apply, no Prepared-media mutation.'
    exit 0
}

if ([string]::IsNullOrWhiteSpace($SourceIso) -or -not (Test-Path -LiteralPath $SourceIso -PathType Leaf)) {
    throw 'SOURCE_ISO is required (official Microsoft Source ISO). Use -WhatIf to print the matrix without applying.'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'warm-media acceptance must run elevated'
}

if ([string]::IsNullOrWhiteSpace($Work)) {
    $Work = Join-Path $repoRoot '.scratch\warm-media-acceptance'
}
New-Item -ItemType Directory -Force -Path $Work | Out-Null

Write-Output 'Hashing Source ISO'
$sha = (Get-FileHash -LiteralPath $SourceIso -Algorithm SHA256).Hash.ToLowerInvariant()
$entry = Join-Path $env:ProgramData "WinMint\Servicing\media-cache\v1\$sha\index-$WimIndex"
if (Test-Path -LiteralPath $entry) {
    Write-Output "Removing Prepared-media key $entry"
    Remove-Item -LiteralPath $entry -Recurse -Force
}

$hostApply = Join-Path $repoRoot 'tools\apply\Invoke-HostApply.ps1'
Write-Output "Apply Profile A ($ProfileA)"
& $hostApply -Iso $SourceIso -Work $Work -Profile $ProfileA -ImageQuality Test
if ($LASTEXITCODE -ne 0) { throw "Profile A Apply failed: $LASTEXITCODE" }
$evidenceA = Get-Evidence $Work
if ([string]$evidenceA.'mediaCache.outcome' -notin @('miss-prepared', 'miss-rebuilt')) {
    throw "Profile A expected a Prepared-media miss, got $($evidenceA.'mediaCache.outcome')"
}
$installHash = [string]$evidenceA.'mediaCache.installWimSha256'
$bootHash = [string]$evidenceA.'mediaCache.bootWimSha256'
$isoA = [string]$evidenceA.outputIsoPath

Write-Output "Apply Profile B ($ProfileB)"
& $hostApply -Iso $SourceIso -Work $Work -Profile $ProfileB -ImageQuality Test
if ($LASTEXITCODE -ne 0) { throw "Profile B Apply failed: $LASTEXITCODE" }
$evidenceB = Get-Evidence $Work
if ([string]$evidenceB.'mediaCache.outcome' -cne 'hit') {
    throw "Profile B expected a Prepared-media hit, got $($evidenceB.'mediaCache.outcome')"
}
if ([string]$evidenceB.'mediaCache.installWimSha256' -cne $installHash) {
    throw 'Prepared install.wim hash changed across Applies'
}
if ([string]$evidenceB.'mediaCache.bootWimSha256' -cne $bootHash) {
    throw 'Prepared boot.wim hash changed across Applies'
}
if ([string]$evidenceB.'mediaCache.copyMode' -cne 'copy') {
    throw "expected copyMode=copy, got $($evidenceB.'mediaCache.copyMode')"
}
$isoB = [string]$evidenceB.outputIsoPath
$payloadAOnly = Join-Path $Work 'payload\from-run-a.txt'
if (Test-Path -LiteralPath $payloadAOnly) {
    throw 'Profile A payload residue survived Profile B'
}

Write-Output 'Corrupting Prepared-media entry'
$manifest = Join-Path $entry 'manifest.json'
Copy-Item -LiteralPath $manifest -Destination "$manifest.bak" -Force
Set-Content -LiteralPath $manifest -Value '{' -Encoding utf8
& $hostApply -Iso $SourceIso -Work $Work -Profile $ProfileB -ImageQuality Test
if ($LASTEXITCODE -ne 0) { throw "quarantine rebuild Apply failed: $LASTEXITCODE" }
$evidenceQ = Get-Evidence $Work
if ([string]$evidenceQ.'mediaCache.outcome' -cne 'miss-rebuilt') {
    throw "corrupt entry expected miss-rebuilt, got $($evidenceQ.'mediaCache.outcome')"
}

if ($IncludeSmoke) {
    $smoke = Join-Path $repoRoot 'tools\vm\Invoke-Smoke.ps1'
    & $smoke -Iso $isoA -Work (Join-Path $Work 'smoke-a') -Profile $ProfileA
    if ($LASTEXITCODE -ne 0) { throw "Smoke A failed: $LASTEXITCODE" }
    & $smoke -Iso $isoB -Work (Join-Path $Work 'smoke-b') -Profile $ProfileB
    if ($LASTEXITCODE -ne 0) { throw "Smoke B failed: $LASTEXITCODE" }
}

Write-Output "Warm-media acceptance ok install=$installHash boot=$bootHash isoA=$isoA isoB=$isoB"
exit 0
