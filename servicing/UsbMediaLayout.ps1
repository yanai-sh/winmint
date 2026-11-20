#requires -Version 7.6
# Dot-sourced layout helpers. No param block: dot-sourcing copies parameters into
# the caller, so Write-UsbMedia.ps1 stays the elevated kernel. No top-level work.

function Assert-WinMintUsbLayoutDisk {
    param(
        [Parameter(Mandatory)] $Identity,
        [Parameter(Mandatory)] [long] $RequiredDiskBytes
    )
    if ([bool] $Identity.IsBoot -or [bool] $Identity.IsSystem) {
        throw "Disk $($Identity.Number) is a boot/system disk"
    }
    if ([bool] $Identity.IsOffline) { throw "Disk $($Identity.Number) is offline" }
    if ([bool] $Identity.IsReadOnly) { throw "Disk $($Identity.Number) is read-only" }
    if ([long] $Identity.Size -lt $RequiredDiskBytes) {
        throw "Disk $($Identity.Number) is too small: $($Identity.Size) bytes (need $RequiredDiskBytes)"
    }
}

function Invoke-WinMintUsbDiskpart {
    param([Parameter(Mandatory)] [string[]] $Lines)
    $scriptPath = Join-Path ([IO.Path]::GetTempPath()) ('winmint-usb-diskpart-' + [guid]::NewGuid().ToString('N') + '.txt')
    [IO.File]::WriteAllLines($scriptPath, $Lines, [Text.Encoding]::ASCII)
    try {
        $output = & "$env:SystemRoot\System32\diskpart.exe" /s $scriptPath
        $exit = $LASTEXITCODE
    }
    finally {
        Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
    }
    $text = $output -join "`n"
    if ($exit -ne 0 -or $text -match 'DiskPart has encountered an error') {
        throw "diskpart failed (${exit}): $text"
    }
}

function Resolve-WinMintUsbAttachedDiskNumber {
    param([Parameter(Mandatory)] [string] $ImagePath)
    $imageFull = [IO.Path]::GetFullPath($ImagePath)
    $deadline = [Diagnostics.Stopwatch]::StartNew()
    do {
        foreach ($disk in @(Get-Disk -ErrorAction Stop)) {
            $location = [string] $disk.Location
            if ([string]::IsNullOrWhiteSpace($location)) { continue }
            if ($location.StartsWith('\\?\')) { $location = $location.Substring(4) }
            try {
                $locationFull = [IO.Path]::GetFullPath($location)
            }
            catch {
                continue
            }
            if ($locationFull.Equals($imageFull, [StringComparison]::OrdinalIgnoreCase)) {
                return [int] $disk.Number
            }
        }
        Start-Sleep -Milliseconds 250
    } while ($deadline.Elapsed.TotalSeconds -lt 15)
    throw 'Mounted VHD has no disk number'
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
    $relative = $parts -join [IO.Path]::DirectorySeparatorChar
    # Volume paths stay literal. GetFullPath rewrites \\?\ and the escape check then rejects a real child.
    if ($Root -match '^(?<prefix>\\\\\?\\Volume\{[0-9a-fA-F-]+\})\\?$') {
        return $Matches.prefix + [IO.Path]::DirectorySeparatorChar + $relative
    }
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $full = [IO.Path]::GetFullPath((Join-Path $rootFull $relative))
    if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "USB receipt path escapes root: $RelativePath"
    }
    return $full
}

function Get-WinMintUsbVolumeRoot {
    param(
        [Parameter(Mandatory)] [int] $DiskNumber,
        [Parameter(Mandatory)] [int] $PartitionNumber
    )
    $current = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $PartitionNumber -ErrorAction Stop
    foreach ($path in @($current.AccessPaths)) {
        if ([string] $path -match '^(?<prefix>\\\\\?\\Volume\{[0-9a-fA-F-]+\})\\?$') {
            return $Matches.prefix + '\'
        }
    }
    throw "USB partition $PartitionNumber has no volume path"
}

function Remove-WinMintUsbDriveLetter {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [int] $DiskNumber,
        $Partition
    )
    if ($null -eq $Partition) { return }
    $number = [int] $Partition.PartitionNumber
    $current = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $number -ErrorAction SilentlyContinue
    if ($null -eq $current) { return }
    foreach ($path in @($current.AccessPaths)) {
        if ([string] $path -notmatch '^[A-Za-z]:') { continue }
        if (-not $PSCmdlet.ShouldProcess([string] $path, 'Remove USB drive letter')) { continue }
        Remove-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber $number `
            -AccessPath ([string] $path) -ErrorAction SilentlyContinue
    }
}

function Read-WinMintUsbReceipt {
    param([Parameter(Mandatory)] [string] $WorkDirectory)

    $receiptPath = Join-Path $WorkDirectory 'usb-media.json'
    $digestPath = Join-Path $WorkDirectory 'logs\digests.json'
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { throw "USB receipt missing: $receiptPath" }
    if (-not (Test-Path -LiteralPath $digestPath -PathType Leaf)) { throw "Digest map missing: $digestPath" }

    $receiptSha = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $digests = Get-Content -LiteralPath $digestPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ([string] $digests.'usbMedia.sha256' -cne $receiptSha) {
        throw 'usbMedia.sha256 does not match usb-media.json'
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

function Write-WinMintUsbPartitionContent {
    param(
        [Parameter(Mandatory)] [int] $DiskNumber,
        [Parameter(Mandatory)] [string] $MediaDir,
        [Parameter(Mandatory)] $Receipt,
        [scriptblock] $BeforeVerify
    )

    $bootPartition = $null
    $payloadPartition = $null
    try {
        Initialize-Disk -Number $DiskNumber -PartitionStyle GPT -ErrorAction Stop | Out-Null
        $bootPartition = New-Partition -DiskNumber $DiskNumber `
            -Size ([long] $Receipt.Document.layout.boot.partitionBytes) `
            -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' -ErrorAction Stop
        $payloadPartition = New-Partition -DiskNumber $DiskNumber -UseMaximumSize `
            -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' -ErrorAction Stop
        foreach ($partition in @($bootPartition, $payloadPartition)) {
            Set-Partition -DiskNumber $DiskNumber -PartitionNumber $partition.PartitionNumber `
                -NoDefaultDriveLetter $true -ErrorAction Stop
        }
        $bootPartition | Format-Volume -FileSystem FAT32 -NewFileSystemLabel 'WINMINT_BOOT' `
            -Force -Confirm:$false -ErrorAction Stop | Out-Null
        $payloadPartition | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'WINMINT' `
            -Force -Confirm:$false -ErrorAction Stop | Out-Null
        foreach ($partition in @($bootPartition, $payloadPartition)) {
            $current = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $partition.PartitionNumber
            $letterPath = @($current.AccessPaths) | Where-Object { [string] $_ -match '^[A-Za-z]:' } | Select-Object -First 1
            if ($null -ne $letterPath) {
                throw "USB partition $($partition.PartitionNumber) has drive letter $letterPath"
            }
        }

        $bootRoot = Get-WinMintUsbVolumeRoot -DiskNumber $DiskNumber -PartitionNumber $bootPartition.PartitionNumber
        $payloadRoot = Get-WinMintUsbVolumeRoot -DiskNumber $DiskNumber -PartitionNumber $payloadPartition.PartitionNumber
        Copy-WinMintUsbReceiptContent -MediaDir $MediaDir -BootRoot $bootRoot `
            -PayloadRoot $payloadRoot -Receipt $Receipt
        Copy-Item -LiteralPath $Receipt.Path -Destination (Join-Path $payloadRoot 'usb-media.json') -Force
        if ($null -ne $BeforeVerify) {
            & $BeforeVerify $payloadRoot
        }
        Test-WinMintUsbReceiptContent -BootRoot $bootRoot -PayloadRoot $payloadRoot -Receipt $Receipt

        $bootVolume = $bootPartition | Get-Volume
        $payloadVolume = $payloadPartition | Get-Volume
        if ([string] $bootVolume.FileSystem -cne 'FAT32' -or [string] $payloadVolume.FileSystem -cne 'NTFS') {
            throw 'USB target filesystems do not match the receipt'
        }
        Set-Partition -DiskNumber $DiskNumber -PartitionNumber $bootPartition.PartitionNumber `
            -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -ErrorAction Stop
        $bootPartition = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $bootPartition.PartitionNumber
        $diskAfter = Get-Disk -Number $DiskNumber
        if ([string] $diskAfter.PartitionStyle -cne 'GPT' `
            -or [guid] $bootPartition.GptType -ne [guid] 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b') {
            throw 'USB target is not GPT with an EFI System Partition after write'
        }

        return [pscustomobject]@{
            BootPartition = $bootPartition
            PayloadPartition = $payloadPartition
        }
    }
    finally {
        foreach ($partition in @($bootPartition, $payloadPartition)) {
            Remove-WinMintUsbDriveLetter -DiskNumber $DiskNumber -Partition $partition
        }
    }
}
