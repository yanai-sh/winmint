#Requires -Version 7.3

[CmdletBinding()]
param(
    [string]$IsoPath = '',
    [int]$UsbDiskNumber = -1,
    [int]$ConfirmUsbDiskNumber = -1,
    [ValidateSet('amd64', 'arm64', 'x86', '')]
    [string]$Architecture = '',
    [switch]$AllowFixedUsbDisk,
    [switch]$ListUsbDisks
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 2.0

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'src\engine\WinMint.ps1')
Initialize-WinMintEngine -RepositoryRoot $repoRoot

if ($ListUsbDisks) {
    Get-WinMintUsbDiskCandidate |
        Format-Table DiskNumber, FriendlyName, BusType, SizeGB, PartitionStyle, IsBoot, IsSystem, IsReadOnly
    return
}

if ([string]::IsNullOrWhiteSpace($IsoPath)) { throw '-IsoPath is required unless -ListUsbDisks is used.' }
if ($UsbDiskNumber -lt 0) { throw '-UsbDiskNumber is required unless -ListUsbDisks is used.' }

Invoke-FlashWindowsInstallMediaToUsb `
    -IsoPath $IsoPath `
    -UsbDiskNumber $UsbDiskNumber `
    -ConfirmUsbDiskNumber $ConfirmUsbDiskNumber `
    -Architecture $Architecture `
    -AllowFixedUsbDisk:$AllowFixedUsbDisk
