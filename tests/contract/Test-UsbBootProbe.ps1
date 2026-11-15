#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
function Read-RepoText([string] $RelativePath) {
    return Get-Content -LiteralPath (Join-Path $repo $RelativePath) -Raw -Encoding utf8
}

$launch = Read-RepoText 'payload/winpe/LaunchApply.cmd'
$probeCheck = $launch.IndexOf('if exist "%INSTALL%:\winmint-boot-probe.txt"', [StringComparison]::Ordinal)
$diskDiscovery = $launch.IndexOf('set WORK=%TEMP%\winmint', [StringComparison]::Ordinal)
$probeLabel = $launch.IndexOf(':winmint_boot_probe', $probeCheck + 1, [StringComparison]::Ordinal)
if ($probeCheck -lt 0 -or $diskDiscovery -le $probeCheck -or $probeLabel -lt 0) {
    throw 'WinPE boot probe must branch before target-disk discovery'
}
if ($launch.Substring($probeLabel) -notmatch 'WINMINT USB BOOT PROBE PASSED' `
    -or $launch.Substring($probeLabel) -notmatch 'winmint\.usb-boot-probe/v1' `
    -or $launch.Substring($probeLabel) -notmatch 'UEFISecureBootEnabled') {
    throw 'WinPE boot probe must emit machine and screen evidence'
}

$image = Read-RepoText 'tools/usb/New-UsbMediaTestImage.ps1'
$layout = Read-RepoText 'servicing/UsbMediaLayout.ps1'
$writer = Read-RepoText 'servicing/Write-UsbMedia.ps1'
foreach ($required in @(
        "winmint-boot-probe.txt",
        "bootProbeChallenge",
        "Write-WinMintUsbPartitionContent",
        "`$QemuImgPath convert -f vhdx -O raw")) {
    if ($image -notmatch [regex]::Escape($required)) {
        throw "USB test-image builder is missing: $required"
    }
}
foreach ($forbidden in @('New-Partition', 'Format-Volume', 'Initialize-Disk', 'Set-Partition')) {
    if ($image -match [regex]::Escape($forbidden)) {
        throw "USB test-image builder must use Write-WinMintUsbPartitionContent, not its own $forbidden"
    }
}
$beforeVerify = $layout.IndexOf('& $BeforeVerify $payloadRoot', [StringComparison]::Ordinal)
$verifyInRecipe = $layout.IndexOf('Test-WinMintUsbReceiptContent', $beforeVerify, [StringComparison]::Ordinal)
if ($beforeVerify -lt 0 -or $verifyInRecipe -le $beforeVerify) {
    throw 'partition recipe must write the probe file before it verifies the receipt'
}
$partitionAt = $layout.IndexOf('function Write-WinMintUsbPartitionContent', [StringComparison]::Ordinal)
foreach ($owned in @('New-Partition', 'Format-Volume')) {
    $ownedAt = $layout.IndexOf($owned, [StringComparison]::Ordinal)
    if ($partitionAt -lt 0 -or $ownedAt -lt $partitionAt) {
        throw "USB layout must call $owned only from Write-WinMintUsbPartitionContent"
    }
    if ($writer.IndexOf($owned, [StringComparison]::Ordinal) -ge 0) {
        throw "physical USB entry must partition through Write-WinMintUsbPartitionContent, not its own $owned"
    }
}

$qemu = Read-RepoText 'tools/usb/Invoke-QemuUsbBootProbe.ps1'
foreach ($required in @('qemu-system-aarch64', 'qemu-xhci', 'usb-storage', 'if=pflash', 'SecureBootVarsTemplatePath', 'virt,gic-version=3')) {
    if ($qemu -notmatch [regex]::Escape($required)) { throw "QEMU USB probe is missing: $required" }
}
if ($qemu -match "'-machine', 'virt'") {
    throw 'QEMU USB probe must select GICv3; virt defaults to GICv2 and Windows ARM64 resets before WinPE'
}
if ($qemu -notmatch "'-m', '8192'") {
    throw 'QEMU USB probe must give the guest 8192 MiB so winload can ramdisk boot.wim'
}
if ($qemu -match 'virtio-(blk|scsi|gpu)') {
    throw 'QEMU USB probe must not bypass USB mass storage with VirtIO or replace Windows GOP with virtio-gpu'
}
if ($qemu -notmatch '(?m)^[^\S\r\n]*''-device'', ''ramfb'',') {
    throw 'QEMU USB probe must provide ramfb; virt has no GOP and Windows boot resets without a linear framebuffer'
}
if ($qemu -notmatch 'winmint-boot-probe\.json') {
    throw 'QEMU USB probe must require evidence written by WinPE'
}
if ($qemu -notmatch 'pristine manifest' -or $qemu -notmatch 'probe\.challenge -ceq \$challenge') {
    throw 'QEMU USB probe must reject reused images and require challenge-bound evidence'
}

$pikvm = Read-RepoText 'tools/usb/Invoke-PiKvmUsbBootProbe.ps1'
foreach ($required in @(
        '/api/msd/write',
        '/api/msd/set_params?image=$name&cdrom=0&rw=0',
        '/api/atx/power?action=on&wait=1',
        'ManualPower',
        'refusing stale evidence',
        'WINMINT\s+USB\s+BOOT\s+PROBE\s+PASSED')) {
    if ($pikvm -notmatch [regex]::Escape($required)) { throw "PiKVM USB probe is missing: $required" }
}

$static = Read-RepoText 'tools/usb/Test-UsbMediaArtifact.ps1'
foreach ($required in @(
        'wimlib',
        'Get-WinPeApplyDefect',
        '--preserve-dir-structure',
        'Get-AuthenticodeSignature',
        'Windows UEFI CA 2023',
        'Test-WinMintBootManagerCa2023',
        '[IO.File]::ReadAllBytes($bcdPath)',
        'winload.efi',
        'bootaa64.efi and bootmgfw.efi must be the same SHA-256',
        'efi/microsoft/boot/boot.stl',
        'boot.stl is empty',
        'bootStl')) {
    if ($static -notmatch [regex]::Escape($required)) { throw "USB static verifier is missing: $required" }
}
if ($static -match '@\(\s*Get-WinPeApplyDefect') {
    throw 'USB static verifier must assign Get-WinPeApplyDefect directly; @() wraps the returned string[] and -join prints System.String[]'
}
if ($static -match 'bcdedit') {
    throw 'USB static verifier must not open the BCD store with bcdedit'
}
$guardAt = $image.IndexOf('Resolve-WinMintUsbAttachedDiskNumber', [StringComparison]::Ordinal)
$layoutAt = $image.IndexOf('Write-WinMintUsbPartitionContent', [StringComparison]::Ordinal)
if ($guardAt -lt 0 -or $layoutAt -lt 0 -or $guardAt -gt $layoutAt) {
    throw 'USB test-image builder must resolve the attached disk before the partition recipe'
}
if ($layout -notmatch 'function Invoke-WinMintUsbDiskpart' -or $layout -notmatch 'Elapsed\.TotalSeconds -lt 15') {
    throw 'USB layout must own the diskpart runner and the 15 second attached-disk poll'
}
if ($image -match 'function Invoke-ProbeDiskpart' -or $qemu -match 'function Invoke-ProbeDiskpart') {
    throw 'USB probe tools must not keep a private diskpart runner'
}
foreach ($required in @('IsBoot', 'IsSystem', 'is not the probe VHD')) {
    if ($image.Substring(0, $layoutAt) -notmatch [regex]::Escape($required)) {
        throw "USB test-image disk guard is missing before the partition recipe: $required"
    }
}
if ($image.IndexOf('Test-WinMintUsbReceiptContent', [StringComparison]::Ordinal) -ge 0) {
    throw 'USB test-image builder must verify through Write-WinMintUsbPartitionContent'
}
foreach ($forbidden in @(
        'Install-WinMintProbeLauncher',
        'replace LaunchApply.cmd',
        'replacing LaunchApply.cmd',
        'LaunchApply.cmd inside boot.wim')) {
    if ($image -match [regex]::Escape($forbidden)) {
        throw 'USB test-image builder must not install LaunchProbe.cmd over LaunchApply.cmd'
    }
}
foreach ($source in @($static, $image)) {
    if ($source -match 'Write-UsbMedia\.ps1') {
        throw 'USB tools must dot-source UsbMediaLayout.ps1, not Write-UsbMedia.ps1'
    }
    if ($source -notmatch 'UsbMediaLayout\.ps1') {
        throw 'USB tools must dot-source UsbMediaLayout.ps1'
    }
}

Write-Output 'Test-UsbBootProbe ok'
exit 0
