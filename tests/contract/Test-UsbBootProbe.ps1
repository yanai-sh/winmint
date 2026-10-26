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
foreach ($required in @(
        "GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'",
        "Format-Volume -FileSystem FAT32",
        "Format-Volume -FileSystem NTFS",
        "winmint-boot-probe.txt",
        "bootProbeChallenge",
        "`$QemuImgPath convert -f vhdx -O raw")) {
    if ($image -notmatch [regex]::Escape($required)) {
        throw "USB test-image builder is missing: $required"
    }
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
foreach ($required in @('wimlib', 'Get-AuthenticodeSignature', 'Windows UEFI CA 2023', 'bcdedit.exe')) {
    if ($static -notmatch [regex]::Escape($required)) { throw "USB static verifier is missing: $required" }
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
