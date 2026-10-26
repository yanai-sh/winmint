#requires -Version 7.6
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)] [string] $WorkDirectory,
    [Parameter(Mandatory)] [int] $DiskNumber,
    [string] $DestructiveToken = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
    if ([bool] $Identity.IsBoot -or [bool] $Identity.IsSystem) {
        throw "Disk $($Identity.Number) is a boot/system disk"
    }
    if ([bool] $Identity.IsOffline) { throw "Disk $($Identity.Number) is offline" }
    if ([bool] $Identity.IsReadOnly) { throw "Disk $($Identity.Number) is read-only" }
    if ([string]::IsNullOrWhiteSpace([string] $Identity.UniqueId) `
        -and [string]::IsNullOrWhiteSpace([string] $Identity.SerialNumber)) {
        throw "Disk $($Identity.Number) has no stable UniqueId or SerialNumber"
    }
    if ([long] $Identity.Size -lt $RequiredDiskBytes) {
        throw "Disk $($Identity.Number) is too small: $($Identity.Size) bytes (need $RequiredDiskBytes)"
    }
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

function Resolve-WinMintUsbEntryPath {
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [string] $RelativePath
    )
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath)) {
        throw "USB receipt path must be relative: $RelativePath"
    }
    $parts = $RelativePath -split '/'
    if ($parts.Count -eq 0 -or @($parts | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
        throw "USB receipt path is not normalized: $RelativePath"
    }
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $full = [IO.Path]::GetFullPath((Join-Path $rootFull ($parts -join [IO.Path]::DirectorySeparatorChar)))
    if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "USB receipt path escapes root: $RelativePath"
    }
    return $full
}

function Read-WinMintUsbReceipt {
    param([Parameter(Mandatory)] [string] $WorkDirectory)

    $receiptPath = Join-Path $WorkDirectory 'usb-media.json'
    $digestPath = Join-Path $WorkDirectory 'logs\digests.json'
    $evidencePath = Join-Path $WorkDirectory 'evidence.json'
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { throw "USB receipt missing: $receiptPath" }
    if (-not (Test-Path -LiteralPath $digestPath -PathType Leaf)) { throw "Digest map missing: $digestPath" }
    if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
        throw "Successful Apply evidence missing: $evidencePath"
    }

    $receiptSha = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $digests = Get-Content -LiteralPath $digestPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ([string] $digests.'usbMedia.sha256' -cne $receiptSha) {
        throw 'usbMedia.sha256 does not match usb-media.json'
    }
    $evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding utf8 | ConvertFrom-Json
    if ([string] $evidence.schemaVersion -cne 'winmint.image.evidence/v1' `
        -or [string] $evidence.digests.'usbMedia.sha256' -cne $receiptSha) {
        throw 'Successful Apply evidence does not bind usb-media.json'
    }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ([string] $receipt.schemaVersion -cne 'winmint.usb-media/v1') {
        throw "Unsupported USB receipt schema: $($receipt.schemaVersion)"
    }
    if ([string] $receipt.layout.partitionStyle -cne 'GPT' `
        -or [string] $receipt.layout.boot.fileSystem -cne 'FAT32' `
        -or [string] $receipt.layout.payload.fileSystem -cne 'NTFS') {
        throw 'USB receipt layout must be GPT with FAT32 boot and NTFS payload'
    }
    return [pscustomobject]@{
        Path = $receiptPath
        Sha256 = $receiptSha
        Document = $receipt
    }
}

function Assert-WinMintUsbReceiptSource {
    param(
        [Parameter(Mandatory)] [string] $MediaDir,
        [Parameter(Mandatory)] $Receipt
    )
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($Receipt.Document.files)) {
        $path = [string] $entry.path
        if (-not $seen.Add($path)) { throw "USB receipt contains duplicate path: $path" }
        if ([string] $entry.destination -notin @('both', 'payload')) {
            throw "USB receipt has invalid destination for ${path}: $($entry.destination)"
        }
        $source = Resolve-WinMintUsbEntryPath -Root $MediaDir -RelativePath $path
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "USB source missing: $path" }
        $item = Get-Item -LiteralPath $source
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "USB source is a reparse point: $path"
        }
        if ([long] $item.Length -ne [long] $entry.length) { throw "USB source length changed: $path" }
        $sha = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($sha -cne [string] $entry.sha256) { throw "USB source digest changed: $path" }
    }
}

function Copy-WinMintUsbReceiptContent {
    param(
        [Parameter(Mandatory)] [string] $MediaDir,
        [Parameter(Mandatory)] [string] $BootRoot,
        [Parameter(Mandatory)] [string] $PayloadRoot,
        [Parameter(Mandatory)] $Receipt
    )
    foreach ($entry in @($Receipt.Document.files)) {
        $source = Resolve-WinMintUsbEntryPath -Root $MediaDir -RelativePath ([string] $entry.path)
        $targets = if ([string] $entry.destination -ceq 'both') { @($BootRoot, $PayloadRoot) } else { @($PayloadRoot) }
        foreach ($root in $targets) {
            $destination = Resolve-WinMintUsbEntryPath -Root $root -RelativePath ([string] $entry.path)
            $parent = Split-Path -Parent $destination
            [IO.Directory]::CreateDirectory($parent) | Out-Null
            [IO.File]::Copy($source, $destination, $true)
        }
    }
}

function Test-WinMintUsbReceiptContent {
    param(
        [Parameter(Mandatory)] [string] $BootRoot,
        [Parameter(Mandatory)] [string] $PayloadRoot,
        [Parameter(Mandatory)] $Receipt
    )
    foreach ($entry in @($Receipt.Document.files)) {
        $targets = if ([string] $entry.destination -ceq 'both') { @($BootRoot, $PayloadRoot) } else { @($PayloadRoot) }
        foreach ($root in $targets) {
            $path = Resolve-WinMintUsbEntryPath -Root $root -RelativePath ([string] $entry.path)
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "USB target file missing: $($entry.path)" }
            $item = Get-Item -LiteralPath $path
            if ([long] $item.Length -ne [long] $entry.length) { throw "USB target length mismatch: $($entry.path)" }
            $sha = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($sha -cne [string] $entry.sha256) { throw "USB target digest mismatch: $($entry.path)" }
        }
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
        Initialize-Disk -Number $DiskNumber -PartitionStyle GPT -ErrorAction Stop | Out-Null
        $bootPartition = New-Partition -DiskNumber $DiskNumber `
            -Size ([long] $receipt.Document.layout.boot.partitionBytes) `
            -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' -AssignDriveLetter -ErrorAction Stop
        $payloadPartition = New-Partition -DiskNumber $DiskNumber -UseMaximumSize `
            -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' -AssignDriveLetter -ErrorAction Stop
        $bootPartition | Format-Volume -FileSystem FAT32 -NewFileSystemLabel 'WINMINT_BOOT' `
            -Force -Confirm:$false -ErrorAction Stop | Out-Null
        $payloadPartition | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'WINMINT' `
            -Force -Confirm:$false -ErrorAction Stop | Out-Null

        $bootPartition = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $bootPartition.PartitionNumber
        $payloadPartition = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $payloadPartition.PartitionNumber
        $bootRoot = "$($bootPartition.DriveLetter):\"
        $payloadRoot = "$($payloadPartition.DriveLetter):\"
        Copy-WinMintUsbReceiptContent -MediaDir $mediaDir -BootRoot $bootRoot `
            -PayloadRoot $payloadRoot -Receipt $receipt
        Copy-Item -LiteralPath $receipt.Path -Destination (Join-Path $payloadRoot 'usb-media.json') -Force
        Test-WinMintUsbReceiptContent -BootRoot $bootRoot -PayloadRoot $payloadRoot -Receipt $receipt

        $bootVolume = $bootPartition | Get-Volume
        $payloadVolume = $payloadPartition | Get-Volume
        if ([string] $bootVolume.FileSystem -cne 'FAT32' -or [string] $payloadVolume.FileSystem -cne 'NTFS') {
            throw 'USB target filesystems do not match the receipt'
        }
        Remove-PartitionAccessPath -DiskNumber $DiskNumber `
            -PartitionNumber $bootPartition.PartitionNumber `
            -AccessPath $bootRoot -ErrorAction Stop
        Set-Partition -DiskNumber $DiskNumber -PartitionNumber $bootPartition.PartitionNumber `
            -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -ErrorAction Stop
        $bootPartition = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $bootPartition.PartitionNumber
        $diskAfter = Get-Disk -Number $DiskNumber
        if ([string] $diskAfter.PartitionStyle -cne 'GPT' `
            -or [guid] $bootPartition.GptType -ne [guid] 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b') {
            throw 'USB target is not GPT with an EFI System Partition after write'
        }

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
            if ($null -ne $partition -and -not [string]::IsNullOrWhiteSpace([string] $partition.DriveLetter)) {
                Remove-PartitionAccessPath -DiskNumber $DiskNumber `
                    -PartitionNumber $partition.PartitionNumber `
                    -AccessPath "$($partition.DriveLetter):\" -ErrorAction SilentlyContinue
            }
        }
    }
    exit 0
}
