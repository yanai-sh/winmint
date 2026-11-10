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
# Dot-sourcing binds its parameters in this scope. Resolve first and pass that
# path through; -WorkDirectory unused would replace the caller's WorkDirectory.
$work = (Resolve-Path -LiteralPath $WorkDirectory).Path
. (Join-Path $repo 'servicing\Write-UsbMedia.ps1') -WorkDirectory $work -DiskNumber 0
. (Join-Path $repo 'servicing\WinPeApplyContract.ps1')
. (Join-Path $repo 'servicing\Patch-BootWimApply.ps1') -MediaDir $work -MountDir $work -WorkDirectory $work -QualityPackageDir $work

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

# Same defects publish refuses, without a second DISM mount. wimlib extract is the
# stand-in for a read-only mount of the four files Get-WinPeApplyDefect reads.
$bootWim = Resolve-WinMintUsbEntryPath -Root $mediaDir -RelativePath 'sources/boot.wim'
$bootInfo = & $wimlib info $bootWim 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "wimlib info failed for sources/boot.wim with exit code $LASTEXITCODE"
}
$imageCountMatch = [regex]::Match($bootInfo, '(?m)^Image Count:\s*(\d+)\s*$')
if (-not $imageCountMatch.Success) { throw 'boot.wim has no indexes' }
$imageCount = [int] $imageCountMatch.Groups[1].Value
if ($imageCount -le 0) { throw 'boot.wim has no indexes' }
$applyPaths = @(
    'Windows/System32/LaunchApply.cmd',
    'Windows/System32/winpeshl.ini',
    'Windows/System32/WinMintApply.exe',
    'Windows/System32/winpe.jpg'
)
$extractRoot = Join-Path ([IO.Path]::GetTempPath()) ('winmint-usb-static-boot-' + [guid]::NewGuid().ToString('N'))
try {
    foreach ($index in 1..$imageCount) {
        $mountDir = Join-Path $extractRoot ([string] $index)
        New-Item -ItemType Directory -Force -Path $mountDir | Out-Null
        $extractExit = 0
        foreach ($applyPath in $applyPaths) {
            & $wimlib extract $bootWim ([string] $index) $applyPath "--dest-dir=$mountDir" --preserve-dir-structure --no-acls 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0 -and $extractExit -eq 0) { $extractExit = $LASTEXITCODE }
        }
        $defects = Get-WinPeApplyDefect -MountDir $mountDir -WorkDirectory $work
        if ($defects.Count -gt 0) {
            throw "USB media boot.wim index ${index} is not WinPE apply media: $($defects -join '; ')"
        }
        if ($extractExit -ne 0) {
            throw "wimlib extract failed for sources/boot.wim index ${index} with exit code $extractExit"
        }
    }
}
finally {
    Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
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
    if ([string] $entry.path -in $pca2023Required -and -not (Test-WinMintBootManagerCa2023 -Signature $signature)) {
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
$aa64Hash = [string] @($efiEvidence | Where-Object { $_.path -ceq 'efi/boot/bootaa64.efi' })[0].sha256
$mgfwHash = [string] @($efiEvidence | Where-Object { $_.path -ceq 'efi/microsoft/boot/bootmgfw.efi' })[0].sha256
if ($aa64Hash -cne $mgfwHash) {
    throw 'bootaa64.efi and bootmgfw.efi must be the same SHA-256'
}

$bootStlPath = 'efi/microsoft/boot/boot.stl'
$stlEntries = @($receipt.Document.files | Where-Object { [string] $_.path -ceq $bootStlPath })
if ($stlEntries.Count -ne 1) { throw "USB receipt is missing ${bootStlPath}" }
$stlFile = Resolve-WinMintUsbEntryPath -Root $mediaDir -RelativePath $bootStlPath
$stlItem = Get-Item -LiteralPath $stlFile
if ($stlItem.Length -le 0) { throw 'boot.stl is empty' }
$stlHash = (Get-FileHash -LiteralPath $stlFile -Algorithm SHA256).Hash.ToLowerInvariant()
if ($stlHash -cne [string] $stlEntries[0].sha256) { throw "USB target digest mismatch: $bootStlPath" }
$bootStlEvidence = [ordered]@{
    path = $bootStlPath
    sha256 = $stlHash
    length = [long] $stlItem.Length
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
    bootStl = $bootStlEvidence
    bcdSha256 = (Get-FileHash -LiteralPath $bcdPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
$evidence | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $output -Encoding utf8
Write-Output "UsbMediaArtifact ok evidence=$output"
