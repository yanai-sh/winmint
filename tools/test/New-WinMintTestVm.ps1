#Requires -Version 7.3
<#
.SYNOPSIS
    Create and boot a Hyper-V Gen 2 VM (UEFI + Secure Boot + vTPM) from a WinMint
    ISO to test the install end to end.

.DESCRIPTION
    Builds the kind of VM Windows 11 requires (Generation 2, Secure Boot with the
    Microsoft Windows template, and a virtual TPM) from the newest ISO in .\output
    (or a -IsoPath you pass), attaches the Default Switch for internet if present,
    sets the DVD as the first boot device, starts the VM, and opens vmconnect.

    The guest architecture follows the Hyper-V host (an ARM64 host produces ARM64
    guests), so run this on the same architecture as the ISO you built.

    Requires an elevated PowerShell (Hyper-V management needs Administrator).

.EXAMPLE
    pwsh -NoProfile -File .\tools\test\New-WinMintTestVm.ps1

.EXAMPLE
    pwsh -NoProfile -File .\tools\test\New-WinMintTestVm.ps1 -Recreate -DiskGB 128 -MemoryGB 8
#>
[CmdletBinding()]
param(
    [string]$IsoPath,
    [string]$VMName = 'WinMint-ARM-Test',
    [int]$MemoryGB = 6,
    [int]$DiskGB = 100,
    [int]$CpuCount = 4,
    [string]$SwitchName,
    [switch]$Recreate,
    [switch]$NoConnect
)

$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw 'Run this in an elevated PowerShell — Hyper-V management requires Administrator.'
}
if (-not (Get-Command New-VM -ErrorAction SilentlyContinue)) {
    throw 'Hyper-V PowerShell module not found. Enable it: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All'
}

# Resolve the ISO: explicit -IsoPath, else the newest WinMint-*.iso in .\output.
if (-not $IsoPath) {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $outputDir = Join-Path $repoRoot 'output'
    $latest = Get-ChildItem -LiteralPath $outputDir -Filter 'WinMint-*.iso' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { throw "No WinMint-*.iso found in $outputDir. Pass -IsoPath explicitly." }
    $IsoPath = $latest.FullName
}
if (-not (Test-Path -LiteralPath $IsoPath)) { throw "ISO not found: $IsoPath" }

# Recreate or refuse if the VM already exists.
$existing = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($existing) {
    if (-not $Recreate) {
        throw "VM '$VMName' already exists. Re-run with -Recreate to delete and rebuild it (this destroys its disk)."
    }
    if ($existing.State -ne 'Off') { Stop-VM -Name $VMName -TurnOff -Force }
    $oldVhds = @($existing.HardDrives.Path)
    Remove-VM -Name $VMName -Force
    foreach ($p in $oldVhds) { if ($p -and (Test-Path -LiteralPath $p)) { Remove-Item -LiteralPath $p -Force } }
}

$vhdDir = Join-Path $env:USERPROFILE 'Hyper-V'
New-Item -ItemType Directory -Force -Path $vhdDir | Out-Null
$vhd = Join-Path $vhdDir "$VMName.vhdx"
if (Test-Path -LiteralPath $vhd) { Remove-Item -LiteralPath $vhd -Force }

# Attach the NAT "Default Switch" for internet (OOBE network / FirstLogon agent),
# unless the caller named a switch.
if (-not $SwitchName) {
    if (Get-VMSwitch -Name 'Default Switch' -ErrorAction SilentlyContinue) { $SwitchName = 'Default Switch' }
}

Write-Host "Creating $VMName from $IsoPath"
$null = New-VM -Name $VMName -Generation 2 -MemoryStartupBytes ($MemoryGB * 1GB) -NewVHDPath $vhd -NewVHDSizeBytes ($DiskGB * 1GB)
Set-VMProcessor -VMName $VMName -Count $CpuCount
# Static memory: Windows Setup is happier with a fixed allocation than dynamic.
Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false -StartupBytes ($MemoryGB * 1GB)
if ($SwitchName) { Connect-VMNetworkAdapter -VMName $VMName -SwitchName $SwitchName }
Add-VMDvdDrive -VMName $VMName -Path $IsoPath
# Windows 11 prerequisites: Secure Boot (Windows template) + virtual TPM.
Set-VMFirmware -VMName $VMName -SecureBootTemplate MicrosoftWindows
Set-VMKeyProtector -VMName $VMName -NewLocalKeyProtector
Enable-VMTPM -VMName $VMName
Set-VMFirmware -VMName $VMName -FirstBootDevice (Get-VMDvdDrive -VMName $VMName)

Start-VM -Name $VMName
Write-Host ("Started {0}: {1} GB RAM, {2} vCPU, {3} GB disk, switch '{4}'." -f `
    $VMName, $MemoryGB, $CpuCount, $DiskGB, ($SwitchName ? $SwitchName : 'none'))
Write-Host "Logs after install: C:\ProgramData\WinMint\Logs (inside the guest)."

if (-not $NoConnect) { vmconnect.exe localhost $VMName }
