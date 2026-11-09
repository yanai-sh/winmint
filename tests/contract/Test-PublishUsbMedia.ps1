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

$publishPath = Join-Path $repo 'servicing\Publish-UsbMedia.ps1'
$publishText = Get-Content -LiteralPath $publishPath -Raw
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $publishPath,
    [ref] $tokens,
    [ref] $parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Publish-UsbMedia parser errors: $($parseErrors -join '; ')"
}
$receiptFn = $ast.Find(
    {
        param($Node)
        $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $Node.Name -eq 'ConvertTo-WinMintUsbMediaReceipt'
    },
    $true)
if ($null -eq $receiptFn) { throw 'ConvertTo-WinMintUsbMediaReceipt missing' }
$receiptBody = $receiptFn.Body.Extent.Text
if ($receiptBody -match 'Get-WinPeApplyDefect|Invoke-WinMintDism') {
    throw 'receipt function must not call Get-WinPeApplyDefect or Invoke-WinMintDism'
}

$kernelAt = $publishText.IndexOf("if (`$MyInvocation.InvocationName -ne '.')", [StringComparison]::Ordinal)
if ($kernelAt -lt 0) { throw 'kernel entry missing' }
$kernel = $publishText.Substring($kernelAt)
$helperAt = $publishText.IndexOf('Invoke-WinMintDism.ps1', [StringComparison]::Ordinal)
if ($helperAt -lt $kernelAt) { throw 'Invoke-WinMintDism.ps1 must be dot-sourced from the kernel entry only' }
$buildAt = $kernel.IndexOf('ConvertTo-WinMintUsbMediaReceipt', [StringComparison]::Ordinal)
$defectAt = $kernel.IndexOf('Get-WinPeApplyDefect', [StringComparison]::Ordinal)
$receiptPathAt = $kernel.IndexOf('UsbMediaReceiptPath', [StringComparison]::Ordinal)
$setContentAt = $kernel.IndexOf('Set-Content', [StringComparison]::Ordinal)
$digestAt = $kernel.IndexOf('Save-WinMintDigestMap -WorkDirectory', [StringComparison]::Ordinal)
if ($buildAt -lt 0 -or $defectAt -lt 0 -or $receiptPathAt -lt 0 -or $setContentAt -lt 0 -or $digestAt -lt 0) {
    throw 'kernel must build the receipt, check boot.wim, then write usb-media.json'
}
if ($buildAt -ge $defectAt -or $defectAt -ge $receiptPathAt -or $defectAt -ge $setContentAt -or $setContentAt -ge $digestAt) {
    throw 'Get-WinPeApplyDefect must run after the receipt is built and before usb-media.json is written'
}
if ($kernel -notmatch 'foreach\s*\(\s*\$index\s+in\s+\$indexes\s*\)') {
    throw 'kernel must check every boot.wim index'
}
if ($kernel -notmatch 'boot\.wim has no indexes') {
    throw 'kernel must throw when Get-WimInfo reports no indexes'
}
if ($kernel -match '@\(\s*Get-WinPeApplyDefect') {
    throw 'kernel must assign Get-WinPeApplyDefect directly; @() wraps the returned string[] and -join prints System.String[]'
}

Write-Output 'Test-PublishUsbMedia ok'
exit 0
