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
. (Join-Path $repo 'servicing\UsbMediaLayout.ps1')
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

$oneMb = 1MB
$requiredBytes = [long] $receipt.Document.layout.requiredDiskBytes
$imageBytes = [long] ([Math]::Ceiling($requiredBytes / [double] $oneMb) * $oneMb)
$imageMb = [int] ($imageBytes / $oneMb)
$attached = $false
$layoutFailed = $false
try {
    Invoke-WinMintUsbDiskpart @(
        "create vdisk file=`"$image`" maximum=$imageMb type=expandable",
        "select vdisk file=`"$image`"",
        'attach vdisk'
    )
    $attached = $true
    $diskNumber = Resolve-WinMintUsbAttachedDiskNumber -ImagePath $image
    $probeDisk = Get-Disk -Number $diskNumber -ErrorAction Stop
    if ($probeDisk.IsBoot -or $probeDisk.IsSystem) {
        throw "Refusing to initialize boot/system disk $diskNumber"
    }
    $location = [string] $probeDisk.Location
    if ([string]::IsNullOrWhiteSpace($location)) {
        throw "Refusing to initialize disk $diskNumber; location is not the probe VHD"
    }
    if ($location.StartsWith('\\?\')) { $location = $location.Substring(4) }
    $locationFull = [IO.Path]::GetFullPath($location)
    if (-not $locationFull.Equals($image, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to initialize disk $diskNumber; location '$locationFull' is not the probe VHD"
    }
    Set-Disk -Number $diskNumber -IsOffline $false -ErrorAction Stop
    Set-Disk -Number $diskNumber -IsReadOnly $false -ErrorAction Stop
    $ready = Get-Disk -Number $diskNumber -ErrorAction Stop
    Assert-WinMintUsbLayoutDisk -Identity $ready -RequiredDiskBytes $requiredBytes
    Write-WinMintUsbPartitionContent -DiskNumber $diskNumber -MediaDir $mediaDir -Receipt $receipt -BeforeVerify {
        param($PayloadRoot)
        Set-Content -LiteralPath (Join-Path $PayloadRoot 'winmint-boot-probe.txt') `
            -Value $probeChallenge -Encoding ascii -NoNewline
    }
}
catch {
    $layoutFailed = $true
    throw
}
finally {
    if ($attached) {
        try {
            Invoke-WinMintUsbDiskpart @(
                "select vdisk file=`"$image`"",
                'detach vdisk'
            )
        }
        catch {
            if ($layoutFailed) { Write-Warning $_.Exception.Message }
            else { throw }
        }
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
