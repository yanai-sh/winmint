#requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $WorkDirectory,
    [Parameter(Mandatory)] [string] $ImagePath,
    [string] $RawImagePath = '',
    [string] $QemuImgPath = 'qemu-img',
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) { throw 'USB test-image creation requires Windows' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'USB test-image creation requires an elevated PowerShell 7.6 process'
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repo 'servicing\Write-UsbMedia.ps1') -WorkDirectory unused -DiskNumber 0

$work = (Resolve-Path -LiteralPath $WorkDirectory).Path
$image = [IO.Path]::GetFullPath($ImagePath)
if ([IO.Path]::GetExtension($image) -cne '.vhdx') {
    throw 'ImagePath must use the .vhdx extension'
}
if (-not [string]::IsNullOrWhiteSpace($RawImagePath)) {
    $raw = [IO.Path]::GetFullPath($RawImagePath)
    if ([IO.Path]::GetExtension($raw) -cne '.img') {
        throw 'RawImagePath must use the .img extension'
    }
}
else {
    $raw = ''
}

foreach ($path in @($image, $raw) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
    if (Test-Path -LiteralPath $path) {
        if (-not $Force) { throw "Output already exists (use -Force to replace it): $path" }
        Remove-Item -LiteralPath $path -Force
    }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
}

$receipt = Read-WinMintUsbReceipt -WorkDirectory $work
$mediaDir = Join-Path $work 'media'
Assert-WinMintUsbReceiptSource -MediaDir $mediaDir -Receipt $receipt
$probeChallenge = [guid]::NewGuid().ToString('N')

if (-not (Get-Command New-VHD -ErrorAction SilentlyContinue)) {
    throw 'Hyper-V PowerShell tools are required for New-VHD and Mount-VHD'
}

$oneMb = 1MB
$requiredBytes = [long] $receipt.Document.layout.requiredDiskBytes
$imageBytes = [long] ([Math]::Ceiling($requiredBytes / [double] $oneMb) * $oneMb)
$mounted = $null
$bootPartition = $null
$payloadPartition = $null
try {
    New-VHD -Path $image -SizeBytes $imageBytes -Dynamic -ErrorAction Stop | Out-Null
    $mounted = Mount-VHD -Path $image -Passthru -ErrorAction Stop
    $diskNumber = [int] $mounted.DiskNumber
    Set-Disk -Number $diskNumber -IsOffline $false -ErrorAction Stop
    Set-Disk -Number $diskNumber -IsReadOnly $false -ErrorAction Stop
    Initialize-Disk -Number $diskNumber -PartitionStyle GPT -ErrorAction Stop | Out-Null

    $bootPartition = New-Partition -DiskNumber $diskNumber `
        -Size ([long] $receipt.Document.layout.boot.partitionBytes) `
        -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' -AssignDriveLetter -ErrorAction Stop
    $payloadPartition = New-Partition -DiskNumber $diskNumber -UseMaximumSize `
        -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' -AssignDriveLetter -ErrorAction Stop
    $bootPartition | Format-Volume -FileSystem FAT32 -NewFileSystemLabel 'WINMINT_BOOT' `
        -Force -Confirm:$false -ErrorAction Stop | Out-Null
    $payloadPartition | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'WINMINT' `
        -Force -Confirm:$false -ErrorAction Stop | Out-Null

    $bootPartition = Get-Partition -DiskNumber $diskNumber -PartitionNumber $bootPartition.PartitionNumber
    $payloadPartition = Get-Partition -DiskNumber $diskNumber -PartitionNumber $payloadPartition.PartitionNumber
    $bootRoot = "$($bootPartition.DriveLetter):\"
    $payloadRoot = "$($payloadPartition.DriveLetter):\"
    Copy-WinMintUsbReceiptContent -MediaDir $mediaDir -BootRoot $bootRoot `
        -PayloadRoot $payloadRoot -Receipt $receipt
    Copy-Item -LiteralPath $receipt.Path -Destination (Join-Path $payloadRoot 'usb-media.json') -Force
    Set-Content -LiteralPath (Join-Path $payloadRoot 'winmint-boot-probe.txt') `
        -Value $probeChallenge -Encoding ascii -NoNewline
    Test-WinMintUsbReceiptContent -BootRoot $bootRoot -PayloadRoot $payloadRoot -Receipt $receipt

    Remove-PartitionAccessPath -DiskNumber $diskNumber `
        -PartitionNumber $bootPartition.PartitionNumber -AccessPath $bootRoot -ErrorAction Stop
    Set-Partition -DiskNumber $diskNumber `
        -PartitionNumber $bootPartition.PartitionNumber `
        -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -ErrorAction Stop
    $bootPartition = Get-Partition -DiskNumber $diskNumber -PartitionNumber $bootPartition.PartitionNumber
    if ([guid] $bootPartition.GptType -ne [guid] 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b') {
        throw 'USB test image boot partition was not converted to an EFI System Partition'
    }
}
finally {
    if ($null -ne $mounted) {
        Dismount-VHD -Path $image -ErrorAction SilentlyContinue
    }
}

if (-not [string]::IsNullOrWhiteSpace($raw)) {
    & $QemuImgPath convert -f vhdx -O raw $image $raw
    if ($LASTEXITCODE -ne 0) { throw "qemu-img convert failed with exit code $LASTEXITCODE" }
}

$manifest = [ordered]@{
    schemaVersion = 'winmint.usb-test-image/v1'
    receiptSha256 = $receipt.Sha256
    vhdx = [ordered]@{
        path = $image
        sha256 = (Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    raw = if ([string]::IsNullOrWhiteSpace($raw)) {
        $null
    }
    else {
        [ordered]@{
            path = $raw
            sha256 = (Get-FileHash -LiteralPath $raw -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    bootProbe = $true
    bootProbeChallenge = $probeChallenge
}
$manifestPath = "$image.json"
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Output "UsbTestImage ok image=$image manifest=$manifestPath"
