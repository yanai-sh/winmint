#requires -Version 7.6
param(
    [Parameter(Mandatory)] [string] $MediaDir,
    [Parameter(Mandatory)] [string] $WorkDirectory,
    [Parameter(Mandatory)] [string] $UsbMediaReceiptPath,
    [Parameter(Mandatory)] [string] $SourceIsoSha256,
    [Parameter(Mandatory)] [int] $WimIndex
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WinMintUsbMediaFile {
    param([Parameter(Mandatory)] [string] $Root)

    $rootItem = Get-Item -LiteralPath $Root -ErrorAction Stop
    if (-not $rootItem.PSIsContainer) { throw "USB media root is not a directory: $Root" }
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "USB media root must not be a reparse point: $Root"
    }

    $rootFull = [IO.Path]::GetFullPath($rootItem.FullName)
    $pending = [Collections.Generic.Queue[IO.DirectoryInfo]]::new()
    $pending.Enqueue([IO.DirectoryInfo] $rootItem)
    $byPath = [Collections.Generic.Dictionary[string, IO.FileInfo]]::new(
        [StringComparer]::OrdinalIgnoreCase)

    while ($pending.Count -gt 0) {
        $directory = $pending.Dequeue()
        foreach ($item in $directory.GetFileSystemInfos()) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "USB media tree contains a reparse point: $($item.FullName)"
            }
            if (($item.Attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                $pending.Enqueue([IO.DirectoryInfo] $item)
                continue
            }

            $relative = [IO.Path]::GetRelativePath($rootFull, $item.FullName).Replace('\', '/')
            if ([IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or $relative.StartsWith('../', [StringComparison]::Ordinal)) {
                throw "USB media path escapes root: $relative"
            }
            if (-not $byPath.TryAdd($relative, [IO.FileInfo] $item)) {
                throw "USB media contains duplicate normalized path: $relative"
            }
        }
    }

    $paths = [string[]] $byPath.Keys
    [Array]::Sort($paths, [StringComparer]::Ordinal)
    foreach ($path in $paths) {
        [pscustomobject]@{ RelativePath = $path; File = $byPath[$path] }
    }
}

function Get-WinMintUsbPartitionSize {
    param(
        [Parameter(Mandatory)] [long] $ContentBytes,
        [Parameter(Mandatory)] [long] $MinimumBytes,
        [Parameter(Mandatory)] [long] $HeadroomBytes
    )
    $alignment = 64MB
    if ($ContentBytes -gt [long]::MaxValue - $HeadroomBytes) { throw 'USB media size overflow' }
    $wanted = [Math]::Max($MinimumBytes, $ContentBytes + $HeadroomBytes)
    $units = [long] [Math]::Ceiling($wanted / [double] $alignment)
    if ($units -gt [long]::MaxValue / $alignment) { throw 'USB partition size overflow' }
    return $units * $alignment
}

function ConvertTo-WinMintUsbMediaReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $MediaDir,
        [Parameter(Mandatory)] [string] $SourceIsoSha256,
        [Parameter(Mandatory)] [int] $WimIndex
    )

    if ($SourceIsoSha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'SourceIsoSha256 must be canonical lowercase SHA-256'
    }
    if ($WimIndex -lt 1) { throw 'WimIndex must be positive' }

    $required = @(
        'efi/boot/bootaa64.efi',
        'efi/microsoft/boot/bootmgfw.efi',
        'efi/microsoft/boot/boot.stl',
        'sources/boot.wim',
        'sources/install.wim',
        'sources/.winmint-boot-apply'
    )
    $files = @(Get-WinMintUsbMediaFile -Root $MediaDir)
    $lookup = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $files) { $lookup.Add([string] $file.RelativePath, $file) }
    foreach ($path in $required) {
        if (-not $lookup.ContainsKey($path)) { throw "USB media required file missing: $path" }
    }

    $marker = (Get-Content -LiteralPath $lookup['sources/.winmint-boot-apply'].File.FullName -Raw -Encoding utf8).Trim()
    if ($marker -cne (Get-WinPeApplyMarkerText)) {
        throw "USB media boot apply marker '$marker' does not match the current WinPE apply contract"
    }

    $fatMaxFile = [long] [uint32]::MaxValue
    [long] $bootBytes = 0
    [long] $payloadBytes = 0
    $entries = [Collections.Generic.List[object]]::new()
    foreach ($item in $files) {
        $path = [string] $item.RelativePath
        $length = [long] $item.File.Length
        $isBoot = $path.StartsWith('efi/', [StringComparison]::OrdinalIgnoreCase) `
            -or $path.StartsWith('boot/', [StringComparison]::OrdinalIgnoreCase) `
            -or $path.Equals('sources/boot.wim', [StringComparison]::OrdinalIgnoreCase)
        if ($isBoot -and $length -gt $fatMaxFile) {
            throw "USB boot file exceeds FAT32 maximum file size: $path ($length bytes)"
        }
        if ($isBoot) {
            if ($bootBytes -gt [long]::MaxValue - $length) { throw 'USB boot content size overflow' }
            $bootBytes += $length
        }
        if ($payloadBytes -gt [long]::MaxValue - $length) { throw 'USB payload content size overflow' }
        $payloadBytes += $length
        $sha = (Get-FileHash -LiteralPath $item.File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $entries.Add([ordered]@{
                path = $path
                destination = if ($isBoot) { 'both' } else { 'payload' }
                length = $length
                sha256 = $sha
            })
    }

    $bootPartitionBytes = Get-WinMintUsbPartitionSize `
        -ContentBytes $bootBytes -MinimumBytes 2GB -HeadroomBytes 256MB
    if ($bootPartitionBytes -gt 32GB) {
        throw "USB boot partition exceeds the supported FAT32 formatting ceiling: $bootPartitionBytes bytes"
    }
    $payloadPartitionBytes = Get-WinMintUsbPartitionSize `
        -ContentBytes $payloadBytes -MinimumBytes 1GB -HeadroomBytes 512MB
    $reserveBytes = 16MB
    if ($bootPartitionBytes -gt [long]::MaxValue - $payloadPartitionBytes - $reserveBytes) {
        throw 'USB required disk size overflow'
    }
    $requiredDiskBytes = $bootPartitionBytes + $payloadPartitionBytes + $reserveBytes

    return [ordered]@{
        schemaVersion = 'winmint.usb-media/v1'
        source = [ordered]@{
            isoSha256 = $SourceIsoSha256
            index = $WimIndex
        }
        layout = [ordered]@{
            partitionStyle = 'GPT'
            boot = [ordered]@{
                order = 1
                fileSystem = 'FAT32'
                contentBytes = $bootBytes
                partitionBytes = $bootPartitionBytes
            }
            payload = [ordered]@{
                order = 2
                fileSystem = 'NTFS'
                contentBytes = $payloadBytes
                partitionBytes = $payloadPartitionBytes
            }
            reserveBytes = $reserveBytes
            requiredDiskBytes = $requiredDiskBytes
        }
        files = $entries
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    . (Join-Path $PSScriptRoot 'WinPeApplyContract.ps1')
    . (Join-Path $PSScriptRoot 'Save-WinMintDigestMap.ps1')

    if (-not (Test-Path -LiteralPath $MediaDir -PathType Container)) {
        throw "MediaDir missing: $MediaDir"
    }
    $receipt = ConvertTo-WinMintUsbMediaReceipt `
        -MediaDir $MediaDir -SourceIsoSha256 $SourceIsoSha256 -WimIndex $WimIndex
    $parent = Split-Path -Parent $UsbMediaReceiptPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $temp = "$UsbMediaReceiptPath.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding utf8
        Move-Item -LiteralPath $temp -Destination $UsbMediaReceiptPath -Force
    }
    finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
    $sha = (Get-FileHash -LiteralPath $UsbMediaReceiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Save-WinMintDigestMap -WorkDirectory $WorkDirectory -Digests @{ 'usbMedia.sha256' = $sha }
    Write-Output "PublishUsbMedia ok receipt=$UsbMediaReceiptPath sha256=$sha"
    exit 0
}
