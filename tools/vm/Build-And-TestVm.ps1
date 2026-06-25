#Requires -Version 7.6
<#
.SYNOPSIS
    Build a WinMint ISO from a profile and boot it in a fresh Hyper-V test VM, in
    one elevated run.

.DESCRIPTION
    Orchestrates the full local acceptance loop:

      1. Stop (and remove) any existing test VM FIRST, before building. A running
         VM holds its full startup RAM; servicing a multi-GB WIM with DISM at the
         same time can starve the host and make the Hyper-V management service
         (vmms) shut down mid-build (event 14090), which leaves the VM unmanageable
         and vmconnect unable to reach the host. Freeing the VM's memory before the
         build avoids that contention.
      2. Build the ISO from the profile via `WinMint-CLI.ps1 build`.
      3. Create + boot a Gen 2 (UEFI + Secure Boot + vTPM) VM from the new ISO via
         New-WinMintTestVm.ps1 -Recreate.

    Requires an elevated PowerShell (WIM servicing and Hyper-V both need admin).

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\Build-And-TestVm.ps1 -ProfilePath .\output\vm-test.json

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\Build-And-TestVm.ps1 -ProfilePath .\tests\profiles\hyper-v-install-arm64.json -MemoryGB 4 -NoConnect
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProfilePath,
    [string]$VMName = 'WinMint-ARM-Test',
    [int]$MemoryGB = 6,
    [int]$DiskGB = 100,
    [int]$CpuCount = 4,
    [string]$SwitchName,
    [switch]$NoConnect,
    [switch]$ForceBuild,
    [switch]$FullImage
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Fingerprint of everything that determines the produced ISO: the profile, the
# whole build engine + staged payload (src\runtime), and the base ISO's identity
# (path|size|mtime - never hash the multi-GB file). If this matches the last
# build's, the existing ISO is byte-identical and we can boot it without
# rebuilding. ponytail: hashing src\runtime wholesale is conservative - any
# engine edit forces a rebuild, but the engine's serviced-wim cache keeps that
# rebuild fast (and a stale-ISO false-skip in a TEST harness is worse than a
# wasted rebuild). The "minor change -> tweak not full rebuild" tier is already
# the engine's: its serviced-wim cache key excludes FirstLogon/payload, so a
# FirstLogon-only change restores the 5 GB wim from cache and just re-stages.
function Get-WinMintVmBuildFingerprint {
    param([Parameter(Mandatory)][string]$ProfilePath, [Parameter(Mandatory)]$ProfileJson, [Parameter(Mandatory)][string]$RepoRoot, [string]$Quality = 'fast')
    $profileHash = (Get-FileHash -LiteralPath $ProfilePath -Algorithm SHA256).Hash
    $runtimeRoot = Join-Path $RepoRoot 'src\runtime'
    $runtimeParts = Get-ChildItem -LiteralPath $runtimeRoot -Recurse -File -ErrorAction Stop |
        Sort-Object FullName |
        ForEach-Object {
            $rel = $_.FullName.Substring($runtimeRoot.Length).TrimStart('\', '/').ToLowerInvariant()
            "$rel|$($_.Length)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
        }
    $srcIso = [string]$ProfileJson.source.isoPath
    $srcIdentity = 'none'
    if ($srcIso) {
        $resolvedSrc = if ([IO.Path]::IsPathRooted($srcIso)) { $srcIso } else { Join-Path $RepoRoot $srcIso }
        if (Test-Path -LiteralPath $resolvedSrc) {
            $it = Get-Item -LiteralPath $resolvedSrc
            $srcIdentity = "$($it.FullName)|$($it.Length)|$($it.LastWriteTimeUtc.Ticks)"
        }
    }
    $blob = "schema=2`nquality=$Quality`nprofile=$profileHash`nsrc=$srcIdentity`nruntime=$($runtimeParts -join ';')"
    return ([BitConverter]::ToString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($blob))) -replace '-', '').ToLowerInvariant()
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw 'Run this in an elevated PowerShell - building (WIM servicing) and Hyper-V both require Administrator.'
}
if (-not (Get-Command New-VM -ErrorAction SilentlyContinue)) {
    throw 'Hyper-V PowerShell module not found. Enable it: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All'
}

$resolvedProfile = if ([IO.Path]::IsPathRooted($ProfilePath)) { $ProfilePath } else { Join-Path $repoRoot $ProfilePath }
if (-not (Test-Path -LiteralPath $resolvedProfile)) {
    throw "Build profile not found: $resolvedProfile"
}
$profileJson = Get-Content -LiteralPath $resolvedProfile -Raw | ConvertFrom-Json
$delayNetworkUntilFirstLogon = $false
$guestUser = ''
$guestPassword = ''
if ($profileJson.identity -and [string]$profileJson.identity.accountMode -eq 'Local') {
    $delayNetworkUntilFirstLogon = $true
    $guestUser = [string]$profileJson.identity.accountName
    $guestPassword = [string]$profileJson.identity.password
    if ([string]::IsNullOrWhiteSpace($guestUser) -or [string]::IsNullOrWhiteSpace($guestPassword)) {
        throw 'Local-account VM delayed-network testing requires identity.accountName and identity.password in the profile.'
    }
}

$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
& $pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Test-WinMintHyperVProfile.ps1') -ProfilePath $resolvedProfile
if ($LASTEXITCODE -ne 0) {
    throw "Hyper-V profile validation failed with exit code $LASTEXITCODE."
}

# 1. Free the host before building: stop the existing test VM so it is not holding
#    RAM while DISM services the image. Remove it too so the build starts clean.
$existing = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($existing) {
    if ($existing.State -ne 'Off') {
        Write-Host "Stopping running test VM '$VMName' before build (frees RAM for DISM servicing)."
        Stop-VM -Name $VMName -TurnOff -Force
    }
    $oldVhds = @($existing.HardDrives.Path)
    Remove-VM -Name $VMName -Force
    foreach ($p in $oldVhds) { if ($p -and (Test-Path -LiteralPath $p)) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } }
    Write-Host "Removed prior '$VMName' so the build runs with no VM competing for resources."
}

# 2. Build the ISO from the profile (verb CLI) - unless nothing that affects the
#    ISO changed since the last build and that ISO is still on disk, in which case
#    boot it as-is and skip the multi-minute rebuild.
$cli = Join-Path $repoRoot 'WinMint-CLI.ps1'
$outputDir = Join-Path $repoRoot 'output'
$fingerprintPath = Join-Path $outputDir '.vm-build-fingerprint.json'
$imageQuality = if ($FullImage) { 'max' } else { 'fast' }
$currentFp = Get-WinMintVmBuildFingerprint -ProfilePath $resolvedProfile -ProfileJson $profileJson -RepoRoot $repoRoot -Quality $imageQuality

$builtIso = $null
if (-not $ForceBuild -and (Test-Path -LiteralPath $fingerprintPath)) {
    try {
        $prev = Get-Content -LiteralPath $fingerprintPath -Raw | ConvertFrom-Json
        if ([string]$prev.fingerprint -eq $currentFp -and $prev.isoPath -and (Test-Path -LiteralPath ([string]$prev.isoPath))) {
            $builtIso = Get-Item -LiteralPath ([string]$prev.isoPath)
            Write-Host "No build-affecting changes since the last run - reusing existing ISO (skipping build):"
            Write-Host "  $($builtIso.FullName)"
        }
    }
    catch { }  # unreadable sidecar -> fall through to a normal build
}

if (-not $builtIso) {
    $buildStartedAt = (Get-Date).AddSeconds(-5)
    # Default to -FastImage (skip recompression + WinSxS cleanup): WinMint is alpha
    # and the VM loop runs many times - install/FirstLogon behavior is identical, only
    # the final image size differs. Pass -FullImage for a production-quality ISO.
    Write-Host "Building ISO from profile ($imageQuality image): $resolvedProfile"
    if ($FullImage) { & $cli build $resolvedProfile -Yes }
    else { & $cli build $resolvedProfile -Yes -FastImage }
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed (exit code $LASTEXITCODE). See the WinMint build report in .\output."
    }
    $builtIso = Get-ChildItem -LiteralPath $outputDir -Filter 'WinMint-*.iso' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $buildStartedAt } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $builtIso) {
        throw "Build completed but no WinMint-*.iso newer than $($buildStartedAt.ToString('o')) was found in $outputDir."
    }
    # Record what we just built so an unchanged next run can skip straight to boot.
    ([ordered]@{ fingerprint = $currentFp; isoPath = $builtIso.FullName; builtUtc = [datetime]::UtcNow.ToString('o') } |
        ConvertTo-Json) | Set-Content -LiteralPath $fingerprintPath -Encoding UTF8
}

# 3. Create + boot the VM from the ISO produced by this build.
$vmArgs = @{
    VMName    = $VMName
    IsoPath   = $builtIso.FullName
    MemoryGB  = $MemoryGB
    DiskGB    = $DiskGB
    CpuCount  = $CpuCount
    Recreate  = $true
}
if ($SwitchName) { $vmArgs['SwitchName'] = $SwitchName }
if ($NoConnect) { $vmArgs['NoConnect'] = $true }
if ($delayNetworkUntilFirstLogon) {
    $vmArgs['DelayNetworkUntilFirstLogon'] = $true
    $vmArgs['GuestUser'] = $guestUser
    $vmArgs['GuestPassword'] = $guestPassword
}
& (Join-Path $PSScriptRoot 'New-WinMintTestVm.ps1') @vmArgs

