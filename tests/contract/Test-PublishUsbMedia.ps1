#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'servicing\WinPeApplyContract.ps1')
. (Join-Path $repo 'servicing\Publish-UsbMedia.ps1') `
    -MediaDir 'unused' -WorkDirectory 'unused' -UsbMediaReceiptPath 'unused' `
    -SourceIsoSha256 ('0' * 64) -WimIndex 1

function Assert-Throws {
    param([scriptblock] $Action, [string] $Pattern)
    try {
        & $Action
        throw "Expected failure matching '$Pattern'"
    }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
    }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('winmint-usb-publish-' + [guid]::NewGuid().ToString('N'))
$media = Join-Path $tmp 'media'
try {
    foreach ($dir in @('efi\boot', 'efi\microsoft\boot', 'boot', 'sources')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $media $dir) | Out-Null
    }
    Set-Content -LiteralPath (Join-Path $media 'efi\boot\bootaa64.efi') -Value 'arm64' -Encoding utf8 -NoNewline
    Set-Content -LiteralPath (Join-Path $media 'efi\microsoft\boot\bootmgfw.efi') -Value 'mgfw' -Encoding utf8 -NoNewline
    Set-Content -LiteralPath (Join-Path $media 'efi\microsoft\boot\boot.stl') -Value 'stl' -Encoding utf8 -NoNewline
    Set-Content -LiteralPath (Join-Path $media 'boot\bcd') -Value 'bcd' -Encoding utf8 -NoNewline
    Set-Content -LiteralPath (Join-Path $media 'sources\boot.wim') -Value 'boot-wim' -Encoding utf8 -NoNewline
    Set-Content -LiteralPath (Join-Path $media 'sources\install.wim') -Value 'install-wim' -Encoding utf8 -NoNewline
    Set-Content -LiteralPath (Join-Path $media 'sources\.winmint-boot-apply') `
        -Value (Get-WinPeApplyMarkerText) -Encoding utf8 -NoNewline

    $one = ConvertTo-WinMintUsbMediaReceipt -MediaDir $media -SourceIsoSha256 ('a' * 64) -WimIndex 3
    $two = ConvertTo-WinMintUsbMediaReceipt -MediaDir $media -SourceIsoSha256 ('a' * 64) -WimIndex 3
    $jsonOne = $one | ConvertTo-Json -Depth 8
    $jsonTwo = $two | ConvertTo-Json -Depth 8
    if ($jsonOne -cne $jsonTwo) { throw 'receipt must be deterministic' }
    if ($one.schemaVersion -cne 'winmint.usb-media/v1') { throw 'receipt schema' }
    if ($one.layout.partitionStyle -cne 'GPT') { throw 'partition style' }
    if ($one.layout.boot.fileSystem -cne 'FAT32' -or $one.layout.payload.fileSystem -cne 'NTFS') {
        throw 'partition filesystems'
    }
    $paths = @($one.files | ForEach-Object { [string] $_.path })
    $sorted = [string[]] $paths.Clone()
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    if ([string]::Join('|', $paths) -cne [string]::Join('|', $sorted)) { throw 'receipt paths not ordinal sorted' }
    $boot = @($one.files | Where-Object { $_.path -eq 'sources/boot.wim' })
    if ($boot.Count -ne 1 -or $boot[0].destination -cne 'both') { throw 'boot.wim must target both partitions' }
    $install = @($one.files | Where-Object { $_.path -eq 'sources/install.wim' })
    if ($install.Count -ne 1 -or $install[0].destination -cne 'payload') { throw 'install.wim must target payload only' }

    Remove-Item -LiteralPath (Join-Path $media 'efi\boot\bootaa64.efi') -Force
    Assert-Throws {
        ConvertTo-WinMintUsbMediaReceipt -MediaDir $media -SourceIsoSha256 ('a' * 64) -WimIndex 3
    } 'required file missing'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Test-PublishUsbMedia ok'
exit 0
