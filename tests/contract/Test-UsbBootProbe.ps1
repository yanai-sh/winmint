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
$beforeVerify = $writer.IndexOf('& $BeforeVerify $payloadRoot', [StringComparison]::Ordinal)
$verifyInRecipe = $writer.IndexOf('Test-WinMintUsbReceiptContent', $beforeVerify, [StringComparison]::Ordinal)
if ($beforeVerify -lt 0 -or $verifyInRecipe -le $beforeVerify) {
    throw 'partition recipe must write the probe file before it verifies the receipt'
}

$qemu = Read-RepoText 'tools/usb/Invoke-QemuUsbBootProbe.ps1'
foreach ($required in @('qemu-system-aarch64', 'qemu-xhci', 'usb-storage', 'if=pflash', 'SecureBootVarsTemplatePath')) {
    if ($qemu -notmatch [regex]::Escape($required)) { throw "QEMU USB probe is missing: $required" }
}
if ($qemu -match 'virtio-(blk|scsi)') { throw 'QEMU USB probe must not bypass USB mass storage with VirtIO' }
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
        'bcdedit.exe',
        'bootaa64.efi and bootmgfw.efi must be the same SHA-256',
        'efi/microsoft/boot/boot.stl',
        'boot.stl is empty',
        'bootStl')) {
    if ($static -notmatch [regex]::Escape($required)) { throw "USB static verifier is missing: $required" }
}
if ($static -match '@\(\s*Get-WinPeApplyDefect') {
    throw 'USB static verifier must assign Get-WinPeApplyDefect directly; @() wraps the returned string[] and -join prints System.String[]'
}
$guardAt = $image.IndexOf('Mounted probe VHD has no disk number', [StringComparison]::Ordinal)
$layoutAt = $image.IndexOf('Write-WinMintUsbPartitionContent', [StringComparison]::Ordinal)
if ($guardAt -lt 0 -or $layoutAt -lt 0 -or $guardAt -gt $layoutAt) {
    throw 'USB test-image builder must refuse a missing disk number before the partition recipe'
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
    $resolveAt = $source.IndexOf('Resolve-Path -LiteralPath $WorkDirectory', [StringComparison]::Ordinal)
    $dotAt = $source.IndexOf('Write-UsbMedia.ps1', [StringComparison]::Ordinal)
    if ($resolveAt -lt 0 -or $dotAt -lt 0 -or $resolveAt -gt $dotAt) {
        throw 'USB tools must resolve WorkDirectory before dot-sourcing Write-UsbMedia.ps1'
    }
    if ($source -match "Write-UsbMedia\.ps1'\) -WorkDirectory unused") {
        throw 'USB tools must not let Write-UsbMedia.ps1 overwrite WorkDirectory with unused'
    }
}

Write-Output 'Test-UsbBootProbe ok'
exit 0
