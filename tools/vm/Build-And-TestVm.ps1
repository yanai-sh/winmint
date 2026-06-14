#Requires -Version 7.3
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
    [switch]$NoConnect
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

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

# 2. Build the ISO from the profile (verb CLI).
$cli = Join-Path $repoRoot 'WinMint-CLI.ps1'
$buildStartedAt = (Get-Date).AddSeconds(-5)
Write-Host "Building ISO from profile: $resolvedProfile"
& $cli build $resolvedProfile -Yes
if ($LASTEXITCODE -ne 0) {
    throw "Build failed (exit code $LASTEXITCODE). See the WinMint build report in .\output."
}
$outputDir = Join-Path $repoRoot 'output'
$builtIso = Get-ChildItem -LiteralPath $outputDir -Filter 'WinMint-*.iso' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $buildStartedAt } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $builtIso) {
    throw "Build completed but no WinMint-*.iso newer than $($buildStartedAt.ToString('o')) was found in $outputDir."
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
