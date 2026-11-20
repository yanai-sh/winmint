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
if ($kernel -match '@\(\s*Get-WinPeApplyDefect') {
    throw 'kernel must assign Get-WinPeApplyDefect directly; @() wraps the returned string[] and -join prints System.String[]'
}
$staticText = Get-Content -LiteralPath (Join-Path $repo 'tools\usb\Test-UsbMediaArtifact.ps1') -Raw
foreach ($caller in @(
        @{ Name = 'publish kernel'; Text = $kernel },
        @{ Name = 'USB static verifier'; Text = $staticText })) {
    if ($caller.Text -notmatch 'Get-WinPeWimIndex\b') {
        throw "$($caller.Name) must call Get-WinPeWimIndex"
    }
    if ($caller.Text -notmatch 'boot\.wim has no indexes') {
        throw "$($caller.Name) must throw when the parser returns no indexes"
    }
}

function Assert-WimIndex {
    param($Actual, [int[]] $Expected, [string] $Label)
    if ($Actual -isnot [System.Array]) { throw "$Label did not return a list" }
    if ($Actual.Count -ne $Expected.Count) {
        throw "$Label count $($Actual.Count) expected $($Expected.Count)"
    }
    for ($i = 0; $i -lt $Expected.Count; $i++) {
        if ([int] $Actual[$i] -ne $Expected[$i]) {
            throw "$Label[$i] is $($Actual[$i]), expected $($Expected[$i])"
        }
    }
}

$dism = @'
Deployment Image Servicing and Management tool
Version: 10.0.26100.1

Index : 1
Name : Windows 11 Home
Architecture : ARM64
Edition : Core
ServicePack Build : 26100

Index : 3
Name : Windows 11 Pro
Architecture : ARM64
Edition : Professional
Installation : Client
ProductType : WinNT
ProductSuite : Terminal Server
ServicePack Build : 26100

The operation completed successfully.
'@
$dismIndexes = Get-WinPeWimIndex -Text $dism
Assert-WimIndex -Actual $dismIndexes -Expected ([int[]](1, 3)) -Label 'DISM'

# libwim-15.dll prints "Index:                  %d" (18 spaces). The exe header is
# "Image Count:    %d" and "Boot Index:     %d". Those header fields are not images.
$wimlib = @(
    'WIM Information:'
    'Image Count:' + (' ' * 4) + '2'
    'Boot Index:' + (' ' * 5) + '3'
    'Available Images:'
    'Index:' + (' ' * 18) + '1'
    'Name:                   Microsoft Windows Setup (arm64)'
    'Description:            Microsoft Windows Setup (arm64)'
    'Index:' + (' ' * 18) + '3'
    'Name:                   Microsoft Windows PE (arm64)'
    'Description:            Microsoft Windows PE (arm64)'
) -join "`n"
$wimlibIndexes = Get-WinPeWimIndex -Text $wimlib
Assert-WimIndex -Actual $wimlibIndexes -Expected ([int[]](1, 3)) -Label 'wimlib'

$noIndex = @(
    'WIM Information:'
    'Image Count:' + (' ' * 4) + '2'
    'Boot Index:' + (' ' * 5) + '1'
    'Available Images:'
) -join "`n"
$emptyIndexes = Get-WinPeWimIndex -Text $noIndex
Assert-WimIndex -Actual $emptyIndexes -Expected ([int[]]@()) -Label 'no index lines'

$mount = Join-Path ([IO.Path]::GetTempPath()) ('winmint-apply-defect-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $mount | Out-Null
try {
    $defects = Get-WinPeApplyDefect -MountDir $mount -WorkDirectory $mount
    if ($defects -notcontains 'LaunchApply.cmd missing inside boot.wim') {
        throw "missing LaunchApply.cmd must be reported: $($defects -join '; ')"
    }
}
finally {
    Remove-Item -LiteralPath $mount -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Test-PublishUsbMedia ok'
exit 0
