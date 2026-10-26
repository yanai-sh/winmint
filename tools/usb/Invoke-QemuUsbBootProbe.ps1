#requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ImagePath,
    [Parameter(Mandatory)] [string] $FirmwareCodePath,
    [Parameter(Mandatory)] [string] $SecureBootVarsTemplatePath,
    [string] $QemuPath = 'qemu-system-aarch64',
    [string] $EvidenceDirectory = '',
    [ValidateRange(30, 1800)] [int] $TimeoutSeconds = 600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) { throw 'The QEMU USB boot probe currently requires a Windows host' }
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

$qemuVersion = (& $QemuPath --version | Select-Object -First 1)
if ($LASTEXITCODE -ne 0) { throw "Unable to execute QEMU: $QemuPath" }

$arguments = @(
    '-machine', 'virt',
    '-cpu', 'max',
    '-smp', '4',
    '-m', '4096',
    '-drive', "if=pflash,format=raw,unit=0,readonly=on,file=$firmwareCode",
    '-drive', "if=pflash,format=raw,unit=1,file=$varsPath",
    '-device', 'qemu-xhci,id=xhci',
    '-drive', "if=none,id=winmint,format=vhdx,file=$image",
    '-device', 'usb-storage,bus=xhci.0,drive=winmint,bootindex=1,removable=true',
    '-display', 'none',
    '-no-reboot',
    '-D', (Join-Path $evidenceDir 'qemu.log'),
    '-d', 'guest_errors'
)
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

$mounted = $null
$assigned = $null
$probe = $null
try {
    $mounted = Mount-VHD -Path $image -Passthru -ErrorAction Stop
    $diskNumber = [int] $mounted.DiskNumber
    $payload = Get-Partition -DiskNumber $diskNumber | Where-Object {
        $volume = $_ | Get-Volume -ErrorAction SilentlyContinue
        $null -ne $volume -and [string] $volume.FileSystem -ceq 'NTFS'
    } | Select-Object -First 1
    if ($null -eq $payload) { throw 'QEMU probe image has no NTFS payload partition' }
    if ([string]::IsNullOrWhiteSpace([string] $payload.DriveLetter)) {
        $payload | Add-PartitionAccessPath -AssignDriveLetter -ErrorAction Stop
        $assigned = Get-Partition -DiskNumber $diskNumber -PartitionNumber $payload.PartitionNumber
        $payloadRoot = "$($assigned.DriveLetter):\"
    }
    else {
        $payloadRoot = "$($payload.DriveLetter):\"
    }
    $probePath = Join-Path $payloadRoot 'winmint-boot-probe.json'
    if (Test-Path -LiteralPath $probePath -PathType Leaf) {
        $probe = Get-Content -LiteralPath $probePath -Raw -Encoding ascii | ConvertFrom-Json
    }
}
finally {
    if ($null -ne $assigned) {
        Remove-PartitionAccessPath -DiskNumber $diskNumber `
            -PartitionNumber $assigned.PartitionNumber -AccessPath $payloadRoot -ErrorAction SilentlyContinue
    }
    if ($null -ne $mounted) { Dismount-VHD -Path $image -ErrorAction SilentlyContinue }
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
