#requires -Version 7.6
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)] [string] $WorkDirectory,
    [Parameter(Mandatory)] [int] $DiskNumber,
    [string] $DestructiveToken = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UsbMediaLayout.ps1')

function Get-WinMintUsbDiskIdentity {
    param([Parameter(Mandatory)] [int] $DiskNumber)

    $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
    return [pscustomobject][ordered]@{
        Number = [int] $disk.Number
        UniqueId = ([string] $disk.UniqueId).Trim()
        SerialNumber = ([string] $disk.SerialNumber).Trim()
        Model = ([string] $disk.FriendlyName).Trim()
        Size = [long] $disk.Size
        BusType = [string] $disk.BusType
        IsBoot = [bool] $disk.IsBoot
        IsSystem = [bool] $disk.IsSystem
        IsOffline = [bool] $disk.IsOffline
        IsReadOnly = [bool] $disk.IsReadOnly
        PartitionStyle = [string] $disk.PartitionStyle
        Disk = $disk
    }
}

function Assert-WinMintUsbAdministrator {
    if (-not $IsWindows) { throw 'Write-UsbMedia requires Windows' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Write-UsbMedia requires an elevated PowerShell 7.6 process'
    }
}

function Get-WinMintUsbIdentityText {
    param([Parameter(Mandatory)] $Identity)
    return '{0}|{1}|{2}|{3}|{4}|{5}' -f @(
        [int] $Identity.Number,
        [string] $Identity.UniqueId,
        [string] $Identity.SerialNumber,
        [string] $Identity.Model,
        [long] $Identity.Size,
        [string] $Identity.BusType)
}

function Get-WinMintUsbDestructiveToken {
    param([Parameter(Mandatory)] $Identity)
    $bytes = [Text.Encoding]::UTF8.GetBytes((Get-WinMintUsbIdentityText -Identity $Identity))
    $sha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    return "ERASE-$($sha.Substring(0, 16))"
}

function Assert-WinMintUsbDiskSafe {
    param(
        [Parameter(Mandatory)] $Identity,
        [Parameter(Mandatory)] [long] $RequiredDiskBytes
    )
    if ([string] $Identity.BusType -cne 'USB') { throw "Disk $($Identity.Number) is not USB (bus=$($Identity.BusType))" }
    if ([string]::IsNullOrWhiteSpace([string] $Identity.UniqueId) `
        -and [string]::IsNullOrWhiteSpace([string] $Identity.SerialNumber)) {
        throw "Disk $($Identity.Number) has no stable UniqueId or SerialNumber"
    }
    Assert-WinMintUsbLayoutDisk -Identity $Identity -RequiredDiskBytes $RequiredDiskBytes
}

function Assert-WinMintUsbIdentityUnchanged {
    param(
        [Parameter(Mandatory)] $Expected,
        [Parameter(Mandatory)] $Actual
    )
    if ((Get-WinMintUsbIdentityText -Identity $Expected) -cne
        (Get-WinMintUsbIdentityText -Identity $Actual)) {
        throw "USB disk identity changed before destruction (expected '$(Get-WinMintUsbIdentityText $Expected)', got '$(Get-WinMintUsbIdentityText $Actual)')"
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Assert-WinMintUsbAdministrator
    $receipt = Read-WinMintUsbReceipt -WorkDirectory $WorkDirectory
    $mediaDir = Join-Path $WorkDirectory 'media'
    Assert-WinMintUsbReceiptSource -MediaDir $mediaDir -Receipt $receipt

    $requiredBytes = [long] $receipt.Document.layout.requiredDiskBytes
    $identity = Get-WinMintUsbDiskIdentity -DiskNumber $DiskNumber
    Assert-WinMintUsbDiskSafe -Identity $identity -RequiredDiskBytes $requiredBytes
    $expectedToken = Get-WinMintUsbDestructiveToken -Identity $identity
    Write-Output "Target disk: $(Get-WinMintUsbIdentityText -Identity $identity)"
    Write-Output "Destructive token: $expectedToken"

    if (-not $PSCmdlet.ShouldProcess(
            "USB disk $DiskNumber ($($identity.Model), $($identity.Size) bytes)",
            'erase, partition, copy, and verify WinMint media')) {
        Write-Output 'WriteUsbMedia preflight ok; disk unchanged'
        exit 0
    }
    if ($DestructiveToken -cne $expectedToken) {
        throw "DestructiveToken mismatch. Re-run with -DestructiveToken $expectedToken"
    }

    $fresh = Get-WinMintUsbDiskIdentity -DiskNumber $DiskNumber
    Assert-WinMintUsbDiskSafe -Identity $fresh -RequiredDiskBytes $requiredBytes
    Assert-WinMintUsbIdentityUnchanged -Expected $identity -Actual $fresh

    $bootPartition = $null
    $payloadPartition = $null
    $verificationPath = Join-Path $WorkDirectory 'logs\usb-write-verification.json'
    Remove-Item -LiteralPath $verificationPath -Force -ErrorAction SilentlyContinue
    try {
        Clear-Disk -InputObject $fresh.Disk -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
        $laidOut = Write-WinMintUsbPartitionContent -DiskNumber $DiskNumber -MediaDir $mediaDir -Receipt $receipt
        $bootPartition = $laidOut.BootPartition
        $payloadPartition = $laidOut.PayloadPartition

        $verification = [ordered]@{
            schemaVersion = 'winmint.usb-write-verification/v1'
            receiptSha256 = $receipt.Sha256
            diskIdentitySha256 = (Get-WinMintUsbDestructiveToken -Identity $identity).Substring(6)
            diskNumber = $DiskNumber
            bootPartitionNumber = [int] $bootPartition.PartitionNumber
            payloadPartitionNumber = [int] $payloadPartition.PartitionNumber
            verified = $true
        }
        $temp = "$verificationPath.$([guid]::NewGuid().ToString('N')).tmp"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $verificationPath) | Out-Null
        try {
            $verification | ConvertTo-Json | Set-Content -LiteralPath $temp -Encoding utf8
            Move-Item -LiteralPath $temp -Destination $verificationPath -Force
        }
        finally {
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        }
        Write-Output "WriteUsbMedia ok disk=$DiskNumber receiptSha256=$($receipt.Sha256)"
    }
    finally {
        foreach ($partition in @($bootPartition, $payloadPartition)) {
            Remove-WinMintUsbDriveLetter -DiskNumber $DiskNumber -Partition $partition
        }
    }
    exit 0
}
