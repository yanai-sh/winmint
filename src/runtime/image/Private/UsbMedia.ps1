#Requires -Version 7.3

$script:WinMintUefiNtfsVersion = 'rufus-master-2026-05-23'
$script:WinMintUefiNtfsImageUrl = 'https://raw.githubusercontent.com/pbatard/rufus/master/res/uefi/uefi-ntfs.img'
$script:WinMintUefiNtfsImageSha256 = 'D34DFA6117D1F572F115E0F85F87F6C26B65462347D011E4EB1FA03AE2B70A64'
$script:WinMintUefiNtfsImageSizeBytes = 1048576

function Get-WinMintUefiNtfsImagePath {
    $root = Join-Path (Get-Win11IsoDependencyCacheRoot) 'uefi-ntfs'
    $null = New-Item -ItemType Directory -Path $root -Force
    Join-Path $root 'uefi-ntfs.img'
}

function Get-WinMintUefiNtfsImage {
    [CmdletBinding()]
    param()

    $path = Get-WinMintUefiNtfsImagePath
    $needsDownload = $true
    if (Test-Path -LiteralPath $path) {
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $size = (Get-Item -LiteralPath $path).Length
        $needsDownload = -not ($hash -eq $script:WinMintUefiNtfsImageSha256 -and $size -eq $script:WinMintUefiNtfsImageSizeBytes)
    }
    if ($needsDownload) {
        Log "Downloading UEFI:NTFS helper image: $script:WinMintUefiNtfsImageUrl"
        Invoke-WebRequest -Uri $script:WinMintUefiNtfsImageUrl -OutFile $path -UseBasicParsing
    }

    $item = Get-Item -LiteralPath $path -ErrorAction Stop
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actualHash -ne $script:WinMintUefiNtfsImageSha256) {
        throw "UEFI:NTFS helper hash mismatch. Expected $script:WinMintUefiNtfsImageSha256, got $actualHash."
    }
    if ($item.Length -ne $script:WinMintUefiNtfsImageSizeBytes) {
        throw "UEFI:NTFS helper size mismatch. Expected $script:WinMintUefiNtfsImageSizeBytes bytes, got $($item.Length)."
    }

    if (Get-Command Add-WinMintManifestPayload -ErrorAction SilentlyContinue) {
        Add-WinMintManifestPayload `
            -Name 'UEFI:NTFS boot helper image' `
            -SourceUrl $script:WinMintUefiNtfsImageUrl `
            -Version $script:WinMintUefiNtfsVersion `
            -Sha256 $actualHash `
            -SizeBytes $item.Length
    }

    [pscustomobject]@{
        Path = $path
        Version = $script:WinMintUefiNtfsVersion
        SourceUrl = $script:WinMintUefiNtfsImageUrl
        Sha256 = $actualHash
        SizeBytes = [long]$item.Length
    }
}

function Get-WinMintUsbDiskCandidate {
    [CmdletBinding()]
    param()

    Get-Disk | Sort-Object Number | ForEach-Object {
        [pscustomobject]@{
            DiskNumber = [int]$_.Number
            FriendlyName = [string]$_.FriendlyName
            SerialNumber = [string]$_.SerialNumber
            BusType = [string]$_.BusType
            SizeBytes = [long]$_.Size
            SizeGB = [math]::Round(([double]$_.Size / 1GB), 1)
            PartitionStyle = [string]$_.PartitionStyle
            IsBoot = [bool]$_.IsBoot
            IsSystem = [bool]$_.IsSystem
            IsOffline = [bool]$_.IsOffline
            IsReadOnly = [bool]$_.IsReadOnly
            Location = [string]$_.Location
        }
    }
}

function Assert-WinMintUsbTargetDisk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$DiskNumber,
        [switch]$AllowFixedDisk
    )

    $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
    if ($disk.IsBoot) { throw "Refusing to write USB media to boot disk $DiskNumber." }
    if ($disk.IsSystem) { throw "Refusing to write USB media to system disk $DiskNumber." }
    if ($disk.IsReadOnly) { throw "Refusing to write USB media to read-only disk $DiskNumber." }
    if ($disk.IsOffline) { throw "Refusing to write USB media to offline disk $DiskNumber." }
    if ([long]$disk.Size -lt 16GB) { throw "USB target disk $DiskNumber is smaller than 16 GB." }
    if (-not $AllowFixedDisk -and [string]$disk.BusType -notin @('USB', 'SD', 'MMC')) {
        throw "Refusing to write to non-removable disk $DiskNumber (BusType=$($disk.BusType)). Use -AllowFixedUsbDisk only for deliberate external fixed-media targets."
    }

    $volumes = @(
        Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue |
            Get-Volume -ErrorAction SilentlyContinue |
            Where-Object { $_ }
    )
    foreach ($volume in $volumes) {
        if ($volume.DriveLetter) {
            if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
                $bitlocker = Get-BitLockerVolume -MountPoint "$($volume.DriveLetter):" -ErrorAction SilentlyContinue
                if ($bitlocker -and [string]$bitlocker.ProtectionStatus -eq 'On') {
                    throw "USB target disk $DiskNumber contains BitLocker-protected volume $($volume.DriveLetter):."
                }
            }
        }
    }

    return $disk
}

function Confirm-WinMintUsbDestructiveTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Disk,
        [int]$ConfirmUsbDiskNumber = -1,
        [switch]$SkipTypedDestructiveAck
    )

    if ($SkipTypedDestructiveAck) { return }
    if ($ConfirmUsbDiskNumber -eq [int]$Disk.Number) { return }
    throw "USB media creation erases disk $($Disk.Number) ($($Disk.FriendlyName), $([math]::Round(([double]$Disk.Size / 1GB), 1)) GB). Pass -ConfirmUsbDiskNumber $($Disk.Number) to continue."
}

function Mount-WinMintIsoReadOnlyRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$IsoPath)

    $resolved = (Resolve-Path -LiteralPath $IsoPath -ErrorAction Stop).Path
    $iso = Mount-DiskImage -ImagePath $resolved -Access ReadOnly -PassThru -ErrorAction Stop
    $volume = $iso | Get-Volume -ErrorAction Stop | Select-Object -First 1
    if (-not $volume) { throw 'Mounted ISO did not expose a readable volume.' }
    $root = if ($volume.DriveLetter) {
        "$($volume.DriveLetter):\"
    } elseif ($volume.Path) {
        $volume.Path
    } else {
        throw 'Mounted ISO did not expose a drive letter or volume path.'
    }
    [pscustomobject]@{ ImagePath = $resolved; Root = $root }
}

function Get-WinMintIsoUsbArchitecture {
    param(
        [Parameter(Mandatory)][string]$IsoRoot,
        [string]$Architecture = ''
    )

    if ($Architecture -in @('amd64', 'arm64')) { return $Architecture }
    if (Test-Path -LiteralPath (Join-Path $IsoRoot 'efi\boot\bootaa64.efi')) { return 'arm64' }
    if (Test-Path -LiteralPath (Join-Path $IsoRoot 'efi\boot\bootx64.efi')) { return 'amd64' }
    if (Test-Path -LiteralPath (Join-Path $IsoRoot 'efi\boot\bootia32.efi')) { return 'x86' }
    return ''
}

function Assert-WinMintIsoUsbReadiness {
    param(
        [Parameter(Mandatory)][string]$IsoRoot,
        [string]$Architecture = ''
    )

    $sources = Join-Path $IsoRoot 'sources'
    if (-not (Test-Path -LiteralPath $sources)) { throw "ISO is missing sources folder: $sources" }
    $hasInstallPayload = @('install.wim', 'install.esd', 'install.swm') | Where-Object {
        Test-Path -LiteralPath (Join-Path $sources $_)
    }
    if (@($hasInstallPayload).Count -eq 0) { throw 'ISO is missing sources\install.wim, sources\install.esd, or sources\install.swm.' }
    $arch = Get-WinMintIsoUsbArchitecture -IsoRoot $IsoRoot -Architecture $Architecture
    if ($arch -eq 'amd64' -and -not (Test-Path -LiteralPath (Join-Path $IsoRoot 'efi\boot\bootx64.efi'))) {
        throw 'amd64 USB media requires efi\boot\bootx64.efi in the ISO.'
    }
    if ($arch -eq 'arm64' -and -not (Test-Path -LiteralPath (Join-Path $IsoRoot 'efi\boot\bootaa64.efi'))) {
        throw 'arm64 USB media requires efi\boot\bootaa64.efi in the ISO.'
    }
    if ([string]::IsNullOrWhiteSpace($arch)) {
        throw 'Could not determine ISO UEFI architecture from efi\boot fallback loader.'
    }
    return $arch
}

function New-WinMintUsbPartitionLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$DiskNumber)

    $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
    if ($disk.IsReadOnly) { Set-Disk -Number $DiskNumber -IsReadOnly $false -ErrorAction Stop }
    if ($disk.IsOffline) { Set-Disk -Number $DiskNumber -IsOffline $false -ErrorAction Stop }

    Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
    Initialize-Disk -Number $DiskNumber -PartitionStyle GPT -ErrorAction Stop

    $helperPartition = New-Partition `
        -DiskNumber $DiskNumber `
        -Size 1MB `
        -GptType '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}' `
        -ErrorAction Stop
    $ntfsPartition = New-Partition -DiskNumber $DiskNumber -UseMaximumSize -AssignDriveLetter -ErrorAction Stop

    $ntfsVolume = Format-Volume -Partition $ntfsPartition -FileSystem NTFS -NewFileSystemLabel 'WINMINT' -Confirm:$false -Force -ErrorAction Stop
    if (-not $ntfsVolume.DriveLetter) {
        $ntfsPartition = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $ntfsPartition.PartitionNumber
        if (-not $ntfsPartition.DriveLetter) {
            $ntfsPartition | Add-PartitionAccessPath -AssignDriveLetter -ErrorAction Stop
            $ntfsPartition = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $ntfsPartition.PartitionNumber
        }
    }

    [pscustomobject]@{
        InstallPartitionNumber = [int]$ntfsPartition.PartitionNumber
        InstallDriveLetter = [string](Get-Partition -DiskNumber $DiskNumber -PartitionNumber $ntfsPartition.PartitionNumber).DriveLetter
        HelperPartitionNumber = [int]$helperPartition.PartitionNumber
        HelperOffset = [long]$helperPartition.Offset
        HelperSize = [long]$helperPartition.Size
    }
}

function Write-WinMintRawPartitionImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$DiskNumber,
        [Parameter(Mandatory)][long]$Offset,
        [Parameter(Mandatory)][string]$ImagePath
    )

    $bytes = [System.IO.File]::ReadAllBytes($ImagePath)
    $devicePath = "\\.\PhysicalDrive$DiskNumber"
    $stream = [System.IO.FileStream]::new($devicePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
    try {
        $stream.Seek($Offset, [System.IO.SeekOrigin]::Begin) | Out-Null
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    }
    finally {
        $stream.Dispose()
    }
}

function Test-WinMintUsbInstallMedia {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [Parameter(Mandatory)][string]$Architecture
    )

    $required = @(
        'sources',
        'efi\boot',
        'efi\microsoft\boot'
    )
    foreach ($relative in $required) {
        $path = Join-Path $InstallRoot $relative
        if (-not (Test-Path -LiteralPath $path)) { throw "USB verification failed; missing $relative." }
    }
    $loader = switch ($Architecture) {
        'arm64' { 'efi\boot\bootaa64.efi' }
        'amd64' { 'efi\boot\bootx64.efi' }
        default { 'efi\boot\bootia32.efi' }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $InstallRoot $loader))) {
        throw "USB verification failed; missing $loader."
    }
    $sources = Join-Path $InstallRoot 'sources'
    $installPayloads = @('install.wim', 'install.esd', 'install.swm' | Where-Object {
        Test-Path -LiteralPath (Join-Path $sources $_)
    })
    if ($installPayloads.Count -eq 0) {
        throw 'USB verification failed; missing install payload under sources.'
    }
}

function Set-WinMintManifestUsbMedia {
    param([Parameter(Mandatory)]$Result)

    Set-WinMintManifestUsbMediaFact -Result $Result
}

function Invoke-FlashWindowsInstallMediaToUsb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$IsoPath,
        [Parameter(Mandatory)][int]$UsbDiskNumber,
        [int]$ConfirmUsbDiskNumber = -1,
        [string]$Architecture = '',
        [switch]$AllowFixedUsbDisk,
        [switch]$SkipTypedDestructiveAck
    )

    if (-not (Test-WinMintAdministrator)) { throw 'USB media creation requires Administrator.' }
    if (-not (Test-Path -LiteralPath $IsoPath)) { throw "ISO not found: $IsoPath" }

    Write-SectionHeader 'USB installer'
    $disk = Assert-WinMintUsbTargetDisk -DiskNumber $UsbDiskNumber -AllowFixedDisk:$AllowFixedUsbDisk
    Confirm-WinMintUsbDestructiveTarget -Disk $disk -ConfirmUsbDiskNumber $ConfirmUsbDiskNumber -SkipTypedDestructiveAck:$SkipTypedDestructiveAck
    $helper = Get-WinMintUefiNtfsImage

    $mounted = $null
    try {
        $mounted = Mount-WinMintIsoReadOnlyRoot -IsoPath $IsoPath
        $resolvedArch = Assert-WinMintIsoUsbReadiness -IsoRoot $mounted.Root -Architecture $Architecture

        Log "Preparing disk $UsbDiskNumber as GPT UEFI install media (NTFS + UEFI:NTFS helper)."
        $layout = New-WinMintUsbPartitionLayout -DiskNumber $UsbDiskNumber
        if ([string]::IsNullOrWhiteSpace([string]$layout.InstallDriveLetter)) {
            throw 'USB install partition did not receive a drive letter.'
        }
        $installRoot = "$($layout.InstallDriveLetter):\"

        Invoke-RobocopyChecked -Source $mounted.Root -Dest $installRoot -UserFacingMessage 'Copying ISO contents to USB install partition...'
        Write-WinMintRawPartitionImage -DiskNumber $UsbDiskNumber -Offset ([long]$layout.HelperOffset) -ImagePath ([string]$helper.Path)
        Test-WinMintUsbInstallMedia -InstallRoot $installRoot -Architecture $resolvedArch

        $result = [pscustomobject]@{
            Status = 'ok'
            WrittenAt = [DateTimeOffset]::Now.ToString('o')
            DiskNumber = [int]$UsbDiskNumber
            DiskModel = [string]$disk.FriendlyName
            DiskSizeBytes = [long]$disk.Size
            InstallDrive = $installRoot
            HelperVersion = [string]$helper.Version
            HelperSourceUrl = [string]$helper.SourceUrl
            HelperSha256 = [string]$helper.Sha256
            Architecture = [string]$resolvedArch
        }
        Set-WinMintManifestUsbMedia -Result $result
        LogOK "USB installer written to disk $UsbDiskNumber ($($disk.FriendlyName))."
        return $result
    }
    catch {
        Set-WinMintManifestUsbMediaFailureFact -DiskNumber $UsbDiskNumber -ErrorMessage $_.Exception.Message
        throw
    }
    finally {
        if ($mounted) {
            Dismount-Win11IsoDiskImageLiteral -LiteralImagePath ([string]$mounted.ImagePath)
        }
    }
}
