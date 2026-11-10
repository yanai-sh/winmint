#requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [uri] $BaseUri,
    [Parameter(Mandatory)] [pscredential] $Credential,
    [Parameter(Mandatory)] [string] $RawImagePath,
    [Parameter(Mandatory)] [string] $ImageManifestPath,
    [string] $EvidenceDirectory = '',
    [ValidateRange(60, 1800)] [int] $TimeoutSeconds = 300,
    [switch] $SkipCertificateCheck,
    [switch] $ManualPower,
    [switch] $RemoveRemoteImage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($BaseUri.Scheme -cne 'https') { throw 'PiKVM BaseUri must use HTTPS' }
$raw = (Resolve-Path -LiteralPath $RawImagePath).Path
$manifestPath = (Resolve-Path -LiteralPath $ImageManifestPath).Path
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
if ([string] $manifest.schemaVersion -cne 'winmint.usb-test-image/v1' `
    -or $null -eq $manifest.raw `
    -or -not [bool] $manifest.bootProbe) {
    throw 'Manifest does not describe a raw WinMint USB boot-probe image'
}
$challenge = [string] $manifest.bootProbeChallenge
if ($challenge -cnotmatch '^[0-9a-f]{32}$') { throw 'USB test-image manifest has an invalid boot-probe challenge' }
$expectedBanner = "WINMINT USB BOOT PROBE PASSED $challenge"
$expectedBannerPattern = 'WINMINT\s+USB\s+BOOT\s+PROBE\s+PASSED\s+' + [regex]::Escape($challenge)
$rawSha = (Get-FileHash -LiteralPath $raw -Algorithm SHA256).Hash.ToLowerInvariant()
if ($rawSha -cne [string] $manifest.raw.sha256) {
    throw 'Raw image digest does not match the USB test-image manifest'
}

if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $evidenceDir = Join-Path (Split-Path -Parent $raw) 'pikvm-usb-probe'
}
else {
    $evidenceDir = [IO.Path]::GetFullPath($EvidenceDirectory)
}
[IO.Directory]::CreateDirectory($evidenceDir) | Out-Null

$networkCredential = $Credential.GetNetworkCredential()
$basic = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes("$($networkCredential.UserName):$($networkCredential.Password)"))
$headers = @{ Authorization = "Basic $basic" }
$requestCommon = @{
    Headers = $headers
    SkipCertificateCheck = [bool] $SkipCertificateCheck
}

function Get-PiKvmUri {
    param([Parameter(Mandatory)] [string] $PathAndQuery)
    return [uri]::new($BaseUri, $PathAndQuery)
}

function Invoke-PiKvmJson {
    param(
        [Parameter(Mandatory)] [ValidateSet('Get', 'Post')] [string] $Method,
        [Parameter(Mandatory)] [string] $PathAndQuery
    )
    return Invoke-RestMethod -Method $Method -Uri (Get-PiKvmUri $PathAndQuery) @requestCommon
}

if (-not $ManualPower) {
    $atx = Invoke-PiKvmJson -Method Get -PathAndQuery '/api/atx'
    if ([bool] $atx.result.leds.power) {
        throw 'PiKVM target must be powered off before the non-destructive boot probe'
    }
}
$msd = Invoke-PiKvmJson -Method Get -PathAndQuery '/api/msd'
if ([bool] $msd.result.drive.connected) {
    throw 'PiKVM mass-storage drive is already connected; refusing to replace active media'
}
try {
    $preflightOcr = Invoke-WebRequest -Method Get `
        -Uri (Get-PiKvmUri '/api/streamer/snapshot?ocr=1&ocr_langs=eng') @requestCommon
    if ([string] $preflightOcr.Content -match $expectedBannerPattern) {
        throw "PiKVM already displays this probe's challenge; refusing stale evidence: $expectedBanner"
    }
}
catch {
    $response = $_.Exception.Response
    $statusCode = if ($null -eq $response) { 0 } else { [int] $response.StatusCode }
    if ($statusCode -notin @(503, 504)) { throw }
}

$remoteName = "winmint-usb-probe-$($rawSha.Substring(0, 16)).img"
$remoteProperty = $msd.result.storage.images.PSObject.Properties[$remoteName]
if ($null -eq $remoteProperty) {
    $uploadUri = Get-PiKvmUri "/api/msd/write?image=$([uri]::EscapeDataString($remoteName))"
    Invoke-WebRequest -Method Post -Uri $uploadUri -InFile $raw -ContentType 'application/octet-stream' `
        @requestCommon | Out-Null
}

$connected = $false
$passed = $false
$poweredOffAfterPass = $false
$ocrText = ''
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$snapshotPath = Join-Path $evidenceDir 'passed.jpg'
try {
    $name = [uri]::EscapeDataString($remoteName)
    Invoke-PiKvmJson -Method Post -PathAndQuery "/api/msd/set_params?image=$name&cdrom=0&rw=0" | Out-Null
    Invoke-PiKvmJson -Method Post -PathAndQuery '/api/msd/set_connected?connected=1' | Out-Null
    $connected = $true
    if ($ManualPower) {
        Write-Host 'PiKVM media connected. Power on the target and select USB boot now.'
    }
    else {
        Invoke-PiKvmJson -Method Post -PathAndQuery '/api/atx/power?action=on&wait=1' | Out-Null
    }

    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Start-Sleep -Seconds 2
        try {
            $ocrResponse = Invoke-WebRequest -Method Get `
                -Uri (Get-PiKvmUri '/api/streamer/snapshot?ocr=1&ocr_langs=eng') @requestCommon
            $ocrText = [string] $ocrResponse.Content
            if ($ocrText -match $expectedBannerPattern) {
                $passed = $true
                Invoke-WebRequest -Method Get `
                    -Uri (Get-PiKvmUri '/api/streamer/snapshot?preview_quality=95') `
                    -OutFile $snapshotPath @requestCommon
                break
            }
        }
        catch {
            $response = $_.Exception.Response
            $statusCode = if ($null -eq $response) { 0 } else { [int] $response.StatusCode }
            if ($statusCode -notin @(503, 504)) { throw }
        }
    }
    if ($passed -and -not $ManualPower) {
        $shutdownWait = [Diagnostics.Stopwatch]::StartNew()
        while ($shutdownWait.Elapsed.TotalSeconds -lt 90) {
            Start-Sleep -Seconds 2
            $atx = Invoke-PiKvmJson -Method Get -PathAndQuery '/api/atx'
            if (-not [bool] $atx.result.leds.power) {
                $poweredOffAfterPass = $true
                break
            }
        }
    }
}
finally {
    $stopwatch.Stop()
    if ($connected) {
        Invoke-PiKvmJson -Method Post -PathAndQuery '/api/msd/set_connected?connected=0' | Out-Null
    }
    if ($RemoveRemoteImage) {
        $name = [uri]::EscapeDataString($remoteName)
        Invoke-PiKvmJson -Method Post -PathAndQuery "/api/msd/remove?image=$name" | Out-Null
    }
}

$evidence = [ordered]@{
    schemaVersion = 'winmint.pikvm-usb-boot-evidence/v1'
    passed = $passed
    poweredOffAfterPass = $poweredOffAfterPass
    receiptSha256 = [string] $manifest.receiptSha256
    challenge = $challenge
    rawImageSha256 = $rawSha
    remoteImage = $remoteName
    powerControl = if ($ManualPower) { 'manual' } else { 'atx' }
    elapsedMilliseconds = [long] $stopwatch.ElapsedMilliseconds
    ocr = $ocrText
    snapshot = if (Test-Path -LiteralPath $snapshotPath) { $snapshotPath } else { $null }
}
$evidencePath = Join-Path $evidenceDir 'evidence.json'
$evidence | ConvertTo-Json | Set-Content -LiteralPath $evidencePath -Encoding utf8
if (-not $passed) {
    throw "PiKVM did not observe the WinMint USB boot-probe banner (evidence=$evidencePath)"
}
Write-Output "PiKvmUsbBootProbe ok evidence=$evidencePath"
