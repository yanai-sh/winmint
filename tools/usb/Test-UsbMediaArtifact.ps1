#requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $WorkDirectory,
    [Parameter(Mandatory)] [string] $WimlibImagexPath,
    [string] $EvidencePath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) { throw 'USB media artifact validation requires Windows' }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repo 'servicing\Write-UsbMedia.ps1') -WorkDirectory unused -DiskNumber 0

$work = (Resolve-Path -LiteralPath $WorkDirectory).Path
$receipt = Read-WinMintUsbReceipt -WorkDirectory $work
$mediaDir = Join-Path $work 'media'
Assert-WinMintUsbReceiptSource -MediaDir $mediaDir -Receipt $receipt

$wimlib = (Get-Command $WimlibImagexPath -ErrorAction Stop).Source
$wimEvidence = @()
foreach ($relativePath in @('sources/boot.wim', 'sources/install.wim')) {
    $path = Resolve-WinMintUsbEntryPath -Root $mediaDir -RelativePath $relativePath
    & $wimlib verify $path
    if ($LASTEXITCODE -ne 0) {
        throw "wimlib verification failed for $relativePath with exit code $LASTEXITCODE"
    }
    $wimEvidence += [ordered]@{
        path = $relativePath
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$efiEvidence = @()
$efiEntries = @($receipt.Document.files | Where-Object {
        [string] $_.destination -ceq 'both' -and [string] $_.path -match '(?i)\.efi$'
    })
if ($efiEntries.Count -eq 0) { throw 'USB receipt contains no EFI binaries' }
$pca2023Required = @(
    'efi/boot/bootaa64.efi',
    'efi/microsoft/boot/bootmgfw.efi'
)
foreach ($entry in $efiEntries) {
    $path = Resolve-WinMintUsbEntryPath -Root $mediaDir -RelativePath ([string] $entry.path)
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    $subject = [string] $signature.SignerCertificate.Subject
    $issuer = [string] $signature.SignerCertificate.Issuer
    if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid) {
        throw "EFI signature is not valid: $($entry.path) ($($signature.Status))"
    }
    if ([string] $entry.path -in $pca2023Required -and "$subject`n$issuer" -notmatch 'Windows UEFI CA 2023') {
        throw "EFI binary is not signed through Windows UEFI CA 2023: $($entry.path)"
    }
    $efiEvidence += [ordered]@{
        path = [string] $entry.path
        signerSubject = $subject
        signerIssuer = $issuer
        sha256 = [string] $entry.sha256
    }
}
foreach ($requiredPath in $pca2023Required) {
    if ($requiredPath -notin @($efiEntries | ForEach-Object { [string] $_.path })) {
        throw "USB receipt is missing a boot-critical EFI binary: $requiredPath"
    }
}

$bcdPath = Join-Path $mediaDir 'efi\microsoft\boot\bcd'
if (-not (Test-Path -LiteralPath $bcdPath -PathType Leaf)) {
    throw 'USB media EFI BCD store is missing'
}
$bcdOutput = & "$env:SystemRoot\System32\bcdedit.exe" /store $bcdPath /enum all 2>&1
if ($LASTEXITCODE -ne 0) { throw "bcdedit failed to enumerate the USB BCD store: $bcdOutput" }
if (($bcdOutput -join "`n") -notmatch '(?i)winload\.efi') {
    throw 'USB BCD store does not contain a Windows EFI loader'
}

if ([string]::IsNullOrWhiteSpace($EvidencePath)) {
    $output = Join-Path $work 'logs\usb-static-verification.json'
}
else {
    $output = [IO.Path]::GetFullPath($EvidencePath)
}
[IO.Directory]::CreateDirectory((Split-Path -Parent $output)) | Out-Null
$evidence = [ordered]@{
    schemaVersion = 'winmint.usb-static-verification/v1'
    verified = $true
    receiptSha256 = $receipt.Sha256
    wimlibVersion = [string] (& $wimlib --version | Select-Object -First 1)
    wims = $wimEvidence
    efi = $efiEvidence
    bcdSha256 = (Get-FileHash -LiteralPath $bcdPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
$evidence | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $output -Encoding utf8
Write-Output "UsbMediaArtifact ok evidence=$output"
