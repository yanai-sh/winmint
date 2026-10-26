#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'servicing\Write-UsbMedia.ps1') -WorkDirectory 'unused' -DiskNumber 1

function New-TestIdentity {
    param(
        [string] $BusType = 'USB',
        [bool] $IsBoot = $false,
        [bool] $IsSystem = $false,
        [bool] $IsOffline = $false,
        [bool] $IsReadOnly = $false,
        [long] $Size = 16GB,
        [string] $UniqueId = 'usb-unique',
        [string] $SerialNumber = 'usb-serial'
    )
    return [pscustomobject]@{
        Number = 7
        UniqueId = $UniqueId
        SerialNumber = $SerialNumber
        Model = 'Fixture USB'
        Size = $Size
        BusType = $BusType
        IsBoot = $IsBoot
        IsSystem = $IsSystem
        IsOffline = $IsOffline
        IsReadOnly = $IsReadOnly
        PartitionStyle = 'RAW'
        Disk = $null
    }
}

function Assert-Throws {
    param([scriptblock] $Action, [string] $Pattern)
    try {
        & $Action
        throw "Expected failure matching '$Pattern'"
    }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
    }
}

Assert-WinMintUsbDiskSafe -Identity (New-TestIdentity) -RequiredDiskBytes 8GB
Assert-Throws { Assert-WinMintUsbDiskSafe -Identity (New-TestIdentity -BusType NVMe) -RequiredDiskBytes 1 } 'not USB'
Assert-Throws { Assert-WinMintUsbDiskSafe -Identity (New-TestIdentity -IsBoot $true) -RequiredDiskBytes 1 } 'boot/system'
Assert-Throws { Assert-WinMintUsbDiskSafe -Identity (New-TestIdentity -IsSystem $true) -RequiredDiskBytes 1 } 'boot/system'
Assert-Throws { Assert-WinMintUsbDiskSafe -Identity (New-TestIdentity -IsOffline $true) -RequiredDiskBytes 1 } 'offline'
Assert-Throws { Assert-WinMintUsbDiskSafe -Identity (New-TestIdentity -IsReadOnly $true) -RequiredDiskBytes 1 } 'read-only'
Assert-Throws {
    Assert-WinMintUsbDiskSafe -Identity (New-TestIdentity -UniqueId '' -SerialNumber '') -RequiredDiskBytes 1
} 'no stable'
Assert-Throws { Assert-WinMintUsbDiskSafe -Identity (New-TestIdentity -Size 1GB) -RequiredDiskBytes 2GB } 'too small'

$identity = New-TestIdentity
$changed = New-TestIdentity -SerialNumber 'other'
Assert-WinMintUsbIdentityUnchanged -Expected $identity -Actual (New-TestIdentity)
Assert-Throws { Assert-WinMintUsbIdentityUnchanged -Expected $identity -Actual $changed } 'identity changed'
if ((Get-WinMintUsbDestructiveToken $identity) -cne (Get-WinMintUsbDestructiveToken (New-TestIdentity))) {
    throw 'destructive token must be stable for unchanged identity'
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('winmint-usb-write-' + [guid]::NewGuid().ToString('N'))
try {
    $work = Join-Path $tmp 'work'
    New-Item -ItemType Directory -Force -Path (Join-Path $work 'logs') | Out-Null
    $receiptPath = Join-Path $work 'usb-media.json'
    Set-Content -LiteralPath $receiptPath -Encoding utf8 -Value '{"schemaVersion":"winmint.usb-media/v1","layout":{"partitionStyle":"GPT","boot":{"fileSystem":"FAT32"},"payload":{"fileSystem":"NTFS"}},"files":[]}'
    $receiptSha = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath (Join-Path $work 'logs\digests.json') -Encoding utf8 `
        -Value (@{ 'usbMedia.sha256' = $receiptSha } | ConvertTo-Json)
    Set-Content -LiteralPath (Join-Path $work 'evidence.json') -Encoding utf8 `
        -Value (@{ schemaVersion = 'winmint.image.evidence/v1'; digests = @{ 'usbMedia.sha256' = $receiptSha } } | ConvertTo-Json)
    $read = Read-WinMintUsbReceipt -WorkDirectory $work
    if ($read.Sha256 -cne $receiptSha) { throw 'receipt evidence binding' }
    Remove-Item -LiteralPath (Join-Path $work 'evidence.json') -Force
    Assert-Throws { Read-WinMintUsbReceipt -WorkDirectory $work } 'Successful Apply evidence missing'

    $source = Join-Path $tmp 'source'
    $boot = Join-Path $tmp 'boot'
    $payload = Join-Path $tmp 'payload'
    New-Item -ItemType Directory -Force -Path (Join-Path $source 'efi\boot'), $boot, $payload | Out-Null
    $sourceFile = Join-Path $source 'efi\boot\bootaa64.efi'
    Set-Content -LiteralPath $sourceFile -Value 'fixture' -Encoding utf8 -NoNewline
    $sha = (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash.ToLowerInvariant()
    $receipt = [pscustomobject]@{
        Document = [pscustomobject]@{
            files = @([pscustomobject]@{
                    path = 'efi/boot/bootaa64.efi'
                    destination = 'both'
                    length = (Get-Item $sourceFile).Length
                    sha256 = $sha
                })
        }
    }
    Assert-WinMintUsbReceiptSource -MediaDir $source -Receipt $receipt
    Copy-WinMintUsbReceiptContent -MediaDir $source -BootRoot $boot -PayloadRoot $payload -Receipt $receipt
    Test-WinMintUsbReceiptContent -BootRoot $boot -PayloadRoot $payload -Receipt $receipt
    Set-Content -LiteralPath (Join-Path $payload 'efi\boot\bootaa64.efi') -Value 'changed' -Encoding utf8
    Assert-Throws {
        Test-WinMintUsbReceiptContent -BootRoot $boot -PayloadRoot $payload -Receipt $receipt
    } 'target (length|digest) mismatch'

    Assert-Throws {
        Resolve-WinMintUsbEntryPath -Root $payload -RelativePath '../escape'
    } '(normalized|escapes)'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$writer = Get-Content -LiteralPath (Join-Path $repo 'servicing\Write-UsbMedia.ps1') -Raw -Encoding utf8
if ($writer -match 'PhysicalDrive|WriteAllBytes') { throw 'writer must not raw-write a physical drive' }
$espStart = $writer.IndexOf('$bootPartition = New-Partition', [StringComparison]::Ordinal)
$payloadStart = $writer.IndexOf('$payloadPartition = New-Partition', $espStart + 1, [StringComparison]::Ordinal)
$bootCreate = if ($espStart -ge 0 -and $payloadStart -gt $espStart) {
    $writer.Substring($espStart, $payloadStart - $espStart)
} else { '' }
if ($bootCreate -notmatch 'ebd0a0a2-b9e5-4433-87c0-68b6b72699c7' `
    -or $bootCreate -notmatch 'AssignDriveLetter') {
    throw 'boot partition must be mounted as FAT32 basic data for copy'
}
$verifyAt = $writer.LastIndexOf('Test-WinMintUsbReceiptContent', [StringComparison]::Ordinal)
$removeBootAt = $writer.IndexOf(
    'Remove-PartitionAccessPath -DiskNumber $DiskNumber',
    $verifyAt,
    [StringComparison]::Ordinal)
$setEspAt = $writer.IndexOf("Set-Partition -DiskNumber `$DiskNumber", $removeBootAt, [StringComparison]::Ordinal)
if ($verifyAt -lt 0 -or $removeBootAt -le $verifyAt -or $setEspAt -le $removeBootAt `
    -or $writer.Substring($setEspAt, 300) -notmatch 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b') {
    throw 'writer must verify, unmount, then convert the boot partition to ESP'
}
$recheckAt = $writer.IndexOf('Assert-WinMintUsbIdentityUnchanged', [StringComparison]::Ordinal)
$clearAt = $writer.LastIndexOf('Clear-Disk', [StringComparison]::Ordinal)
if ($recheckAt -lt 0 -or $clearAt -lt 0 -or $recheckAt -ge $clearAt) {
    throw 'writer must recheck identity before Clear-Disk'
}

Write-Output 'Test-WriteUsbMedia ok'
exit 0
