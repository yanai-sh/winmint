#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'servicing\Inject-SurfaceDrivers.ps1') -MountDir 'x' -WorkDirectory 'x' -MediaDir 'x' -DeviceId 'x' -DetailsUrl 'x' -ExpectedFileNameRegex 'x' -Lane Test

if (-not (Test-MicrosoftDownloadUri -Uri 'https://download.microsoft.com/download/x.msi')) {
    throw 'download.microsoft.com must be allowed'
}
if (-not (Test-MicrosoftDownloadUri -Uri 'https://www.microsoft.com/en-us/download')) {
    throw 'www.microsoft.com must be allowed'
}
if (Test-MicrosoftDownloadUri -Uri 'http://download.microsoft.com/x.msi') {
    throw 'http must be refused'
}
if (Test-MicrosoftDownloadUri -Uri 'https://evil.example/payload.msi') {
    throw 'non-Microsoft host must be refused'
}

$bootClasses = Get-WinMintBootSetupCriticalClass
foreach ($acpi in @('system', 'extension')) {
    if ($bootClasses -contains $acpi) {
        throw "WinPE boot subset must not include Class=$acpi (Hyper-V ACPI 0xA5)"
    }
}
foreach ($need in @('hdc', 'scsiadapter', 'usb')) {
    if ($bootClasses -notcontains $need) {
        throw "WinPE boot subset missing storage/USB class $need"
    }
}

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "winmint-surface-drivers-test-$([Guid]::NewGuid().ToString('n'))"
try {
    $usbDir = Join-Path $fixtureRoot 'usb'
    $systemDir = Join-Path $fixtureRoot 'system'
    $extensionDir = Join-Path $fixtureRoot 'extension'
    $null = New-Item -ItemType Directory -Path $usbDir, $systemDir, $extensionDir -Force
    @(
        @{ Dir = $usbDir; Name = 'fixture-usb.inf'; Class = 'USB' }
        @{ Dir = $systemDir; Name = 'fixture-system.inf'; Class = 'System' }
        @{ Dir = $extensionDir; Name = 'fixture-extension.inf'; Class = 'Extension' }
    ) | ForEach-Object {
        Set-Content -LiteralPath (Join-Path $_.Dir $_.Name) -Value "[Version]`nClass=$($_.Class)"
    }

    $dest = Join-Path $fixtureRoot 'out'
    $copied = Copy-SetupCriticalDriverSubset -DriverSource $fixtureRoot -Destination $dest
    if ($copied -ne 1) {
        throw "Copy-SetupCriticalDriverSubset expected 1 copied INF, got $copied"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $dest 'usb\fixture-usb.inf'))) {
        throw 'Copy-SetupCriticalDriverSubset must copy usb fixture INF'
    }
    foreach ($skip in @('system', 'extension')) {
        $skipped = Get-ChildItem -LiteralPath $dest -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -match [regex]::Escape([IO.Path]::DirectorySeparatorChar + $skip + [IO.Path]::DirectorySeparatorChar) }
        if (@($skipped).Count -gt 0) {
            throw "Copy-SetupCriticalDriverSubset must skip Class=$skip fixture INF"
        }
    }
}
finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$kernel = Get-Content -LiteralPath (Join-Path $repo 'servicing\Inject-SurfaceDrivers.ps1') -Raw -Encoding utf8
if ($kernel -notmatch '\$Lane -eq ''Test''' -or $kernel -notmatch 'surface_test_install_drivers') {
    throw 'Test lane must inject the boot class subset into install.wim'
}
if ($kernel -notmatch "ValidateSet\('Test', 'Release'\)") {
    throw 'Inject-SurfaceDrivers must take a Test/Release Lane'
}
if ($kernel -notmatch 'function Invoke-WinMintSurfaceMsiBitsDownload') {
    throw 'Surface MSI must BITS-download (IWR ResponseEnded on long pulls)'
}
if ($kernel -match 'Invoke-WebRequest -Uri \$asset\.DownloadUrl -OutFile') {
    throw 'Surface MSI must not use Invoke-WebRequest -OutFile for the package body'
}
if ($kernel -notmatch 'surface-cache hit') {
    throw 'Surface MSI download must reuse a Microsoft-signed cache hit'
}
if (-not (Get-Command Invoke-WinMintSurfaceMsiBitsDownload -ErrorAction SilentlyContinue)) {
    throw 'Invoke-WinMintSurfaceMsiBitsDownload must be dot-sourceable'
}

Write-Output 'Test-SurfaceDrivers ok'
exit 0
