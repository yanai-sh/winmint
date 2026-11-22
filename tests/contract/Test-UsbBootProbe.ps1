#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
function Read-RepoText([string] $RelativePath) {
    return Get-Content -LiteralPath (Join-Path $repo $RelativePath) -Raw -Encoding utf8
}

$launch = Read-RepoText 'payload/winpe/LaunchApply.cmd'
$probeCheck = $launch.IndexOf('if exist "%INSTALL%:\winmint-boot-probe.txt"', [StringComparison]::Ordinal)
$diskDiscovery = $launch.IndexOf('call :winmint_find_install', [StringComparison]::Ordinal)
$probeLabel = $launch.IndexOf(':winmint_boot_probe', $probeCheck + 1, [StringComparison]::Ordinal)
if ($probeCheck -lt 0 -or $diskDiscovery -le $probeCheck -or $probeLabel -lt 0) {
    throw 'WinPE boot probe must branch before target-disk discovery'
}
$armCheck = $launch.IndexOf('if not exist "%INSTALL%:\winmint-install.txt"', [StringComparison]::Ordinal)
$diskpartAt = $launch.IndexOf('diskpart /s', [StringComparison]::Ordinal)
if ($armCheck -lt 0 -or $armCheck -ge $diskDiscovery -or $armCheck -ge $diskpartAt) {
    throw 'WinPE must read winmint-install.txt before it resolves the boot disk'
}
$unarmedAt = $launch.IndexOf('install file is not present', [StringComparison]::Ordinal)
$initPeAt = $launch.IndexOf('call :winmint_init_pe', [StringComparison]::Ordinal)
$seenLoopAt = $launch.IndexOf('for /L %%i in (1,1,10) do if not defined SEEN call :winmint_see_payload', [StringComparison]::Ordinal)
if ($unarmedAt -lt 0 -or $initPeAt -le $unarmedAt -or $seenLoopAt -le $initPeAt) {
    throw 'unarmed shutdown must run before call :winmint_init_pe, and that call must run before the payload search'
}
$confirmAt = $launch.IndexOf('for /L %%i in (1,1,10) do if not defined PAYLOADDISK if not defined WINMINT_BOOT_TAG call :winmint_find_install', [StringComparison]::Ordinal)
$reinstallDel = $launch.IndexOf('del /f /q "%INSTALL%:\winmint-reinstall.txt"', [StringComparison]::Ordinal)
$bootMiss = $launch.IndexOf('install.wim not found on the boot disk', [StringComparison]::Ordinal)
$bootexAt = $launch.IndexOf('/offline /bootex', [StringComparison]::Ordinal)
if ($confirmAt -lt 0 -or $reinstallDel -lt 0 -or $bootMiss -lt 0 -or $bootexAt -lt 0 -or $confirmAt -ge $bootMiss -or $bootexAt -ge $reinstallDel) {
    throw 'WinPE must confirm the payload letter and write boot files before it consumes winmint-reinstall.txt'
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
if ($image -match 'winmint-install\.txt' -or $layout -match 'winmint-install\.txt' -or $writer -match 'winmint-install\.txt') {
    throw 'USB publish, test-image builder, and layout must not plant winmint-install.txt'
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

$early = $launch.IndexOf('if not exist "%SEEN%:\winmint-install.txt"')
$init = $launch.IndexOf('call :winmint_init_pe')
$long = $launch.IndexOf('for /L %%i in (1,1,10) do if not defined SEEN call :winmint_see_payload')
if ($early -lt 0 -or $init -le $early -or $long -le $init) {
    throw 'a missing install file must shut down before wpeinit, and wpeinit before the long payload search'
}
if ($launch -match '(?m)^call wpeinit\s*$') { throw 'LaunchApply must not call bare wpeinit' }
$wpeXml = Join-Path $repo 'payload/winpe/wpeinit.xml'
if ((Get-Content -LiteralPath $wpeXml -Raw -Encoding utf8) -notmatch '<EnableNetwork>\s*false\s*</EnableNetwork>') {
    throw 'wpeinit.xml must set EnableNetwork false'
}

$launchLines = @($launch -split '\r?\n')
$gateStart = [array]::IndexOf($launchLines, 'for /L %%i in (1,1,10) do if not defined SEEN call :winmint_see_payload')
$gateStop = [array]::IndexOf($launchLines, 'set WORK=%TEMP%\winmint')
$seeStart = [array]::IndexOf($launchLines, ':winmint_see_payload')
$seeStop = [array]::IndexOf($launchLines, ':winmint_find_install')
if ($gateStart -lt 0 -or $gateStop -le $gateStart -or $seeStart -lt 0 -or $seeStop -le $seeStart) {
    throw 'LaunchApply install-file gate layout changed — update this test'
}
$gate = foreach ($line in $launchLines[$gateStart..$gateStop]) {
        if ($line -eq 'for /L %%i in (1,1,10) do if not defined PAYLOADDISK if not defined WINMINT_BOOT_TAG call :winmint_find_install') {
        'set PAYLOADDISK=9'
    }
    elseif ($line -eq 'set WORK=%TEMP%\winmint') {
        'echo ARMED'
        'exit /b 0'
    }
    elseif ($line -match 'wpeutil') { 'echo SHUTDOWN' }
    else { $line }
}
$harness = @('@echo off', 'setlocal EnableExtensions') + @($gate) + @(
    ':winmint_boot_probe',
    'echo PROBE',
    'exit /b 0',
    ':winmint_finished',
    'echo FINISHED',
    'exit /b 0'
) + @($launchLines[$seeStart..($seeStop - 1)])
foreach ($line in $harness) {
    if ($line.Trim() -match '^(rem\b|::)') { continue }
    foreach ($danger in @('diskpart', 'clean', 'Apply-Image', 'bcdboot', 'wpeutil', 'wpeinit', 'format')) {
        if ($line -match $danger) { throw "refusing to run the install-file gate: '$danger' leaked into the harness" }
    }
}
$cmdPath = Join-Path $env:TEMP ('winmint-arm-gate-' + [guid]::NewGuid().ToString('N') + '.cmd')
$usb = Join-Path $env:TEMP ('winmint-arm-usb-' + [guid]::NewGuid().ToString('N'))
Set-Content -LiteralPath $cmdPath -Value ($harness -join "`r`n") -Encoding ascii
foreach ($letter in @('C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'Y', 'Z')) {
    if ((Test-Path -LiteralPath "${letter}:\usb-media.json") -and (Test-Path -LiteralPath "${letter}:\sources\install.wim")) {
        throw "arm gate harness needs no real payload volume; ${letter}: already has usb-media.json and sources\install.wim"
    }
}
New-Item -ItemType Directory -Force -Path (Join-Path $usb 'sources') | Out-Null
$earlier = Join-Path $env:TEMP ('winmint-arm-earlier-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $earlier 'sources') | Out-Null
& subst Y: /D 2>&1 | Out-Null
& subst Z: /D 2>&1 | Out-Null
& subst Y: $earlier
if ($LASTEXITCODE -ne 0) { throw 'cannot map Y: for the install-file gate' }
& subst Z: $usb
if ($LASTEXITCODE -ne 0) { throw 'cannot map Z: for the arm gate' }
[IO.File]::WriteAllText('Z:\usb-media.json', '{}')
[IO.File]::WriteAllText('Z:\sources\install.wim', 'wim')
function Assert-InstallGate {
    param([string] $Name, [string] $Token, [scriptblock] $Arrange)
    Get-ChildItem -LiteralPath 'Z:\' -Force | Where-Object { $_.Name -like 'winmint-*' } | Remove-Item -Force
    & $Arrange
    $got = @(& cmd /c "`"$cmdPath`"" 2>&1 | ForEach-Object { "$_" })
    if ($got -cnotcontains $Token) {
        throw "$Name expected $Token`n$($got -join "`n")"
    }
    foreach ($other in @('PROBE', 'SHUTDOWN', 'ARMED', 'FINISHED') | Where-Object { $_ -cne $Token }) {
        if ($got -ccontains $other) { throw "$Name also printed $other`n$($got -join "`n")" }
    }
}
try {
    [IO.File]::WriteAllText('Y:\usb-media.json', '{}')
    [IO.File]::WriteAllText('Y:\sources\install.wim', 'wim')
    [IO.File]::WriteAllText('Y:\winmint-install.txt', 'install')
    Assert-InstallGate 'a later probe file still wins' 'PROBE' {
        [IO.File]::WriteAllText('Z:\winmint-boot-probe.txt', 'probe')
    }
    & subst Y: /D 2>&1 | Out-Null
    Assert-InstallGate 'probe file shuts the probe branch' 'PROBE' {
        [IO.File]::WriteAllText('Z:\winmint-boot-probe.txt', 'probe')
        [IO.File]::WriteAllText('Z:\winmint-install.txt', 'install')
    }
    Assert-InstallGate 'missing install file shuts down' 'SHUTDOWN' { }
    if ((@(& cmd /c "`"$cmdPath`"" 2>&1 | ForEach-Object { "$_" }) -join "`n") -notmatch 'install file is not present') {
        throw 'a stick without the install file must say the install file is not present'
    }
    Assert-InstallGate 'reinstall without the install file shuts down' 'SHUTDOWN' {
        [IO.File]::WriteAllText('Z:\winmint-reinstall.txt', 'again')
    }
    if (-not (Test-Path -LiteralPath 'Z:\winmint-reinstall.txt')) {
        throw 'reinstall request must stay until the install file is present'
    }
    Assert-InstallGate 'install file reaches install' 'ARMED' { [IO.File]::WriteAllText('Z:\winmint-install.txt', 'install') }
    Assert-InstallGate 'empty install file reaches install' 'ARMED' { [IO.File]::WriteAllText('Z:\winmint-install.txt', '') }
    Assert-InstallGate 'reinstall with the install file reaches install' 'ARMED' {
        [IO.File]::WriteAllText('Z:\winmint-install.txt', 'install')
        [IO.File]::WriteAllText('Z:\winmint-reinstall.txt', 'again')
    }
    if (-not (Test-Path -LiteralPath 'Z:\winmint-reinstall.txt')) {
        throw 'reinstall request must stay until boot files are written'
    }
    Assert-InstallGate 'reinstall after a finished apply reaches install' 'ARMED' {
        [IO.File]::WriteAllText('Z:\winmint-install.txt', 'install')
        [IO.File]::WriteAllText('Z:\winmint-applied.txt', 'done')
        [IO.File]::WriteAllText('Z:\winmint-reinstall.txt', 'again')
    }
    Assert-InstallGate 'applied marker finishes' 'FINISHED' { [IO.File]::WriteAllText('Z:\winmint-applied.txt', 'done') }
}
finally {
    & subst Y: /D 2>&1 | Out-Null
    & subst Z: /D 2>&1 | Out-Null
    Remove-Item -LiteralPath $earlier -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $usb -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $cmdPath -Force -ErrorAction SilentlyContinue
}

Write-Output 'Test-UsbBootProbe ok'
exit 0
