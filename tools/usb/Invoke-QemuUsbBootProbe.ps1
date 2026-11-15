#requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ImagePath,
    [Parameter(Mandatory)] [string] $FirmwareCodePath,
    [Parameter(Mandatory)] [string] $SecureBootVarsTemplatePath,
    [string] $QemuPath = 'qemu-system-aarch64',
    [string] $EvidenceDirectory = '',
    [ValidateRange(30, 1800)] [int] $TimeoutSeconds = 1500
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) { throw 'The QEMU USB boot probe currently requires a Windows host' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'QEMU USB boot probe evidence extraction requires an elevated PowerShell 7.6 process'
}
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repo 'servicing\UsbMediaLayout.ps1')
$image = (Resolve-Path -LiteralPath $ImagePath).Path
$firmwareCode = (Resolve-Path -LiteralPath $FirmwareCodePath).Path
$varsTemplate = (Resolve-Path -LiteralPath $SecureBootVarsTemplatePath).Path
if ([IO.Path]::GetExtension($image) -cne '.vhdx') {
    throw 'QEMU probe evidence extraction requires a .vhdx test image'
}
foreach ($path in @($image, $firmwareCode, $varsTemplate)) {
    if ($path.Contains(',')) { throw "QEMU drive paths cannot contain commas: $path" }
}

$manifestPath = "$image.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "USB test-image manifest missing: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
if ([string] $manifest.schemaVersion -cne 'winmint.usb-test-image/v1' -or -not [bool] $manifest.bootProbe) {
    throw 'Image is not a WinMint USB boot-probe image'
}
$challenge = [string] $manifest.bootProbeChallenge
if ($challenge -cnotmatch '^[0-9a-f]{32}$') { throw 'USB test-image manifest has an invalid boot-probe challenge' }
$imageSha = (Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash.ToLowerInvariant()
if ($imageSha -cne [string] $manifest.vhdx.sha256) {
    throw 'VHDX does not match its pristine manifest; rebuild it before another QEMU probe'
}

if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $evidenceDir = Join-Path (Split-Path -Parent $image) 'qemu-usb-probe'
}
else {
    $evidenceDir = [IO.Path]::GetFullPath($EvidenceDirectory)
}
[IO.Directory]::CreateDirectory($evidenceDir) | Out-Null
$varsPath = Join-Path $evidenceDir 'AAVMF_VARS.fd'
Copy-Item -LiteralPath $varsTemplate -Destination $varsPath -Force

$qemuVersionLines = & $QemuPath --version
if ($LASTEXITCODE -ne 0) { throw "Unable to execute QEMU: $QemuPath" }
$qemuVersion = @($qemuVersionLines) | Select-Object -First 1

$arguments = @(
    # virt defaults to GICv2. Windows ARM64 resets on that, and the guest log is
    # gic_dist_writeb. EL2 stays off: cpu max advertises LPA2, and this AAVMF
    # build hangs at "Start boot option" once virtualization is enabled.
    '-machine', 'virt,gic-version=3',
    '-accel', 'tcg',
    '-cpu', 'max',
    '-smp', '4',
    # boot.wim's boot image stays resident as a ramdisk of about 2.6 GiB.
    '-m', '8192',
    '-drive', "if=pflash,format=raw,unit=0,readonly=on,file=$firmwareCode",
    '-drive', "if=pflash,format=raw,unit=1,file=$varsPath",
    '-device', 'qemu-xhci,id=xhci',
    '-drive', "if=none,id=winmint,format=vhdx,file=$image",
    '-device', 'usb-storage,bus=xhci.0,drive=winmint,bootindex=1,removable=true',
    # virt has no display device. Windows Boot Manager resets when UEFI GOP is
    # absent, and -no-reboot turns that into a clean exit. Windows GOP needs a
    # linear framebuffer, so the probe uses ramfb.
    '-device', 'ramfb',
    '-display', 'none',
    '-chardev', ('file,id=winmint-serial,path=' + ((Join-Path $evidenceDir 'serial.log') -replace '\\', '/')),
    '-serial', 'chardev:winmint-serial',
    '-no-reboot',
    '-D', (Join-Path $evidenceDir 'qemu.log'),
    '-d', 'guest_errors'
)
. (Join-Path $PSScriptRoot 'Assert-QemuLaunch.ps1')
Assert-WinMintQemuLaunch -Argument $arguments

$startInfo = [Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $QemuPath
$startInfo.UseShellExecute = $false
foreach ($argument in $arguments) { $startInfo.ArgumentList.Add($argument) }

$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$process = [Diagnostics.Process]::new()
$process.StartInfo = $startInfo
if (-not $process.Start()) { throw 'QEMU did not start' }
if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    $process.Kill($true)
    $process.WaitForExit()
    throw "QEMU USB boot probe timed out after $TimeoutSeconds seconds"
}
$stopwatch.Stop()

$attached = $false
$probe = $null
try {
    Invoke-WinMintUsbDiskpart @(
        "select vdisk file=`"$image`"",
        'attach vdisk readonly'
    )
    $attached = $true
    $diskNumber = Resolve-WinMintUsbAttachedDiskNumber -ImagePath $image
    $probeDisk = Get-Disk -Number $diskNumber -ErrorAction Stop
    if ($probeDisk.IsBoot -or $probeDisk.IsSystem) {
        throw "Refusing to read boot/system disk $diskNumber"
    }
    Set-Disk -Number $diskNumber -IsOffline $false -ErrorAction Stop
    $payload = Get-Partition -DiskNumber $diskNumber | Where-Object {
        $volume = $_ | Get-Volume -ErrorAction SilentlyContinue
        $null -ne $volume -and [string] $volume.FileSystem -ceq 'NTFS'
    } | Select-Object -First 1
    if ($null -eq $payload) { throw 'QEMU probe image has no NTFS payload partition' }
    $payloadRoot = Get-WinMintUsbVolumeRoot -DiskNumber $diskNumber -PartitionNumber $payload.PartitionNumber
    Remove-WinMintUsbDriveLetter -DiskNumber $diskNumber -Partition $payload
    $probePath = $payloadRoot + 'winmint-boot-probe.json'
    if ([IO.File]::Exists($probePath)) {
        $probe = Get-Content -LiteralPath $probePath -Raw -Encoding ascii | ConvertFrom-Json
    }
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
            Write-Warning $_.Exception.Message
        }
    }
}

$passed = $null -ne $probe `
    -and [string] $probe.schemaVersion -ceq 'winmint.usb-boot-probe/v1' `
    -and [string] $probe.result -ceq 'passed' `
    -and [bool] $probe.secureBoot `
    -and [string] $probe.challenge -ceq $challenge
$evidence = [ordered]@{
    schemaVersion = 'winmint.qemu-usb-boot-evidence/v1'
    passed = $passed
    receiptSha256 = [string] $manifest.receiptSha256
    challenge = $challenge
    imagePath = $image
    qemuVersion = [string] $qemuVersion
    firmwareCodeSha256 = (Get-FileHash -LiteralPath $firmwareCode -Algorithm SHA256).Hash.ToLowerInvariant()
    secureBootVarsTemplateSha256 = (Get-FileHash -LiteralPath $varsTemplate -Algorithm SHA256).Hash.ToLowerInvariant()
    elapsedMilliseconds = [long] $stopwatch.ElapsedMilliseconds
    qemuExitCode = [int] $process.ExitCode
}
$evidencePath = Join-Path $evidenceDir 'evidence.json'
$evidence | ConvertTo-Json | Set-Content -LiteralPath $evidencePath -Encoding utf8
if (-not $passed) {
    throw "QEMU exited without WinPE USB boot-probe evidence (exit=$($process.ExitCode), evidence=$evidencePath)"
}
Write-Output "QemuUsbBootProbe ok evidence=$evidencePath"
