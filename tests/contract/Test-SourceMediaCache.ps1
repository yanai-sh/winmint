#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'servicing/Initialize-SourceMediaCache.ps1')

$root = Join-Path ([IO.Path]::GetTempPath()) ('winmint-source-media-' + [guid]::NewGuid().ToString('N'))
$cacheRoot = Join-Path $root 'media-cache'
$isoTree = Join-Path $root 'iso-tree'
$isoPath = Join-Path $root 'source.iso'
$wimIndex = 3
$schema = 1

function Get-Sha256Lower([string] $Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function New-IsoTree {
    param([string] $TreeRoot, [string] $InstallContent = 'MULTI-INDEX-INSTALL-WIM', [string] $BootContent = 'BOOT-WIM')
    $sources = Join-Path $TreeRoot 'sources'
    New-Item -ItemType Directory -Force -Path $sources | Out-Null
    Set-Content -LiteralPath (Join-Path $sources 'install.wim') -Value $InstallContent -Encoding utf8 -NoNewline
    Set-Content -LiteralPath (Join-Path $sources 'boot.wim') -Value $BootContent -Encoding utf8 -NoNewline
    Set-Content -LiteralPath (Join-Path $TreeRoot 'setup.exe') -Value 'setup' -Encoding utf8 -NoNewline
}

function New-FakeSnapshot {
    param([string] $WimFile, [int] $Index)
    $raw = [string](Get-Content -LiteralPath $WimFile -Raw)
    $single = $raw.Contains('SINGLE')
    [ordered]@{
        IndexCount    = $(if ($single) { 1 } else { 3 })
        Index         = $(if ($single) { 1 } else { $Index })
        Name          = 'Windows 11 Pro'
        Architecture  = 'ARM64'
        Edition       = 'Professional'
        Installation  = 'Client'
        ProductType   = 'WinNT'
        ProductSuite  = 'Terminal Server'
        Languages     = 'en-US'
        Build         = '26100'
        Version       = '10.0.26100.1'
    }
}

function New-TestCommands {
    param([scriptblock] $CopyTree, [scriptblock] $ExportImage, [scriptblock] $GetWimSnapshot, [scriptblock] $MountIso)
    $cmds = @{
        MountIso        = $(if ($MountIso) { $MountIso } else { { param($IsoPath) if ($IsoPath -cne $isoPath) { throw "unexpected ISO $IsoPath" }; $isoTree } })
        DismountIso     = { param($IsoPath) $script:dismountCount++ }
        CopyTree        = $(if ($CopyTree) { $CopyTree } else {
                {
                    param($Source, $Destination)
                    if (Test-Path -LiteralPath (Join-Path $script:entryPath 'manifest.json')) {
                        throw 'final manifest published before extract finished'
                    }
                    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
                    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
                }
            })
        GetWimSnapshot  = $(if ($GetWimSnapshot) { $GetWimSnapshot } else { { param($WimFile, $Index) New-FakeSnapshot -WimFile $WimFile -Index $Index } })
        ExportImage     = $(if ($ExportImage) { $ExportImage } else {
                {
                    param($SourceWim, $SourceIndex, $DestWim)
                    $script:exportCount++
                    if (Test-Path -LiteralPath (Join-Path $script:entryPath 'manifest.json')) {
                        throw 'final manifest published before export finished'
                    }
                    if ($SourceIndex -ne $wimIndex) { throw "unexpected export index $SourceIndex" }
                    Set-Content -LiteralPath $DestWim -Value 'SINGLE-INDEX-INSTALL-WIM' -Encoding utf8 -NoNewline
                }
            })
    }
    $cmds
}

function New-ExpectedIdentity {
    [ordered]@{
        sourceIsoSha256 = $script:sha
        wimIndex        = $wimIndex
        imageName       = 'Windows 11 Pro'
        architecture    = 'ARM64'
        edition         = 'Professional'
        build           = '26100'
    }
}

function Publish-HandEntry {
    param(
        [string] $EntryPath,
        [string] $InstallContent = 'SINGLE-INDEX-INSTALL-WIM',
        [string] $BootContent = 'BOOT-WIM',
        [hashtable] $Manifest
    )
    $sources = Join-Path $EntryPath 'media\sources'
    New-Item -ItemType Directory -Force -Path $sources | Out-Null
    $install = Join-Path $sources 'install.wim'
    $boot = Join-Path $sources 'boot.wim'
    Set-Content -LiteralPath $install -Value $InstallContent -Encoding utf8 -NoNewline
    Set-Content -LiteralPath $boot -Value $BootContent -Encoding utf8 -NoNewline
    if (-not $Manifest) {
        $Manifest = @{
            schema            = $schema
            sourceIsoSha256   = $script:sha
            sourceIsoLength   = $script:isoLength
            sourceIndex       = $wimIndex
            preparedUtc       = '2026-08-12T00:00:00Z'
            installWimSha256  = Get-Sha256Lower $install
            installWimLength  = [long](Get-Item -LiteralPath $install).Length
            bootWimSha256     = Get-Sha256Lower $boot
            bootWimLength     = [long](Get-Item -LiteralPath $boot).Length
            image             = @{
                name         = 'Windows 11 Pro'
                architecture = 'ARM64'
                edition      = 'Professional'
                build        = '26100'
                indexCount   = 1
            }
        }
    }
    ($Manifest | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $EntryPath 'manifest.json') -Encoding utf8
}

function Assert-True([bool] $Value, [string] $Case) {
    if (-not $Value) { throw $Case }
}

function Assert-False([bool] $Value, [string] $Case) {
    if ($Value) { throw $Case }
}

try {
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    New-IsoTree -TreeRoot $isoTree
    Set-Content -LiteralPath $isoPath -Value 'fake-source-iso-bytes' -Encoding utf8 -NoNewline
    $script:sha = Get-Sha256Lower $isoPath
    $script:isoLength = [long](Get-Item -LiteralPath $isoPath).Length
    $script:entryPath = Get-WinMintMediaCacheEntry -CacheRoot $cacheRoot -SourceIsoSha256 $script:sha -WimIndex $wimIndex -Schema $schema
    $script:exportCount = 0
    $script:dismountCount = 0
    $expected = New-ExpectedIdentity
    $commands = New-TestCommands

    Assert-False (Test-Path -LiteralPath $script:entryPath) 'entry must not exist before prepare'

    $prepared = Initialize-WinMintPreparedMedia `
        -SourceIso $isoPath `
        -SourceIsoSha256 $script:sha `
        -SourceIsoLength $script:isoLength `
        -WimIndex $wimIndex `
        -Schema $schema `
        -CacheRoot $cacheRoot `
        -ExpectedIdentity $expected `
        -Commands $commands

    if ($prepared.Outcome -cne 'miss-prepared') { throw "expected miss-prepared, got $($prepared.Outcome)" }
    if ([int]$prepared.SourceHashMs -lt 0 -or [int]$prepared.CacheValidateMs -lt 0 -or [int]$prepared.CachePrepareMs -lt 0) {
        throw 'prepare timings were negative'
    }
    if ($prepared.EntryPath -cne $script:entryPath) { throw 'prepare returned a different entry path' }
    Assert-True (Test-Path -LiteralPath (Join-Path $script:entryPath 'manifest.json')) 'manifest missing after prepare'
    $prepareLeft = @(Get-ChildItem -LiteralPath (Split-Path $script:entryPath -Parent) -Force -Directory |
        Where-Object { $_.Name.StartsWith('.prepare-') })
    if ($prepareLeft.Count -ne 0) { throw 'staging directory survived publication' }
    if ($script:dismountCount -lt 1) { throw 'Source ISO was not dismounted' }

    $manifest = Get-Content -LiteralPath (Join-Path $script:entryPath 'manifest.json') -Raw | ConvertFrom-Json
    foreach ($name in @(
            'schema', 'sourceIsoSha256', 'sourceIsoLength', 'sourceIndex', 'preparedUtc',
            'installWimSha256', 'installWimLength', 'bootWimSha256', 'bootWimLength', 'image')) {
        if ($null -eq $manifest.$name) { throw "manifest missing $name" }
    }
    foreach ($name in @('name', 'architecture', 'edition', 'build', 'indexCount')) {
        if ($null -eq $manifest.image.$name) { throw "manifest.image missing $name" }
    }
    if ([int]$manifest.schema -ne 1) { throw 'manifest schema' }
    if ($manifest.sourceIsoSha256 -cne $script:sha) { throw 'manifest source hash' }
    if ([long]$manifest.sourceIsoLength -ne $script:isoLength) { throw 'manifest source length' }
    if ([int]$manifest.sourceIndex -ne $wimIndex) { throw 'manifest source index' }
    if ($manifest.sourceIsoSha256 -notmatch '^[0-9a-f]{64}$') { throw 'source hash not lowercase hex' }
    if ($manifest.installWimSha256 -notmatch '^[0-9a-f]{64}$') { throw 'install hash not lowercase hex' }
    if ($manifest.bootWimSha256 -notmatch '^[0-9a-f]{64}$') { throw 'boot hash not lowercase hex' }
    if ([int]$manifest.image.indexCount -ne 1) { throw 'manifest indexCount' }
    $installPath = Join-Path $script:entryPath 'media\sources\install.wim'
    $bootPath = Join-Path $script:entryPath 'media\sources\boot.wim'
    if ((Get-Sha256Lower $installPath) -cne $manifest.installWimSha256) { throw 'install hash mismatch' }
    if ((Get-Sha256Lower $bootPath) -cne $manifest.bootWimSha256) { throw 'boot hash mismatch' }
    Assert-True (
        (Test-WinMintMediaCacheEntry `
            -EntryPath $script:entryPath `
            -SourceIsoSha256 $script:sha `
            -SourceIsoLength $script:isoLength `
            -WimIndex $wimIndex `
            -Schema $schema `
            -ExpectedIdentity $expected `
            -CacheRoot $cacheRoot `
            -Commands $commands)
    ) 'published entry failed validation'

    $script:exportCount = 0
    $hit = Initialize-WinMintPreparedMedia `
        -SourceIso $isoPath `
        -SourceIsoSha256 $script:sha `
        -SourceIsoLength $script:isoLength `
        -WimIndex $wimIndex `
        -Schema $schema `
        -CacheRoot $cacheRoot `
        -ExpectedIdentity $expected `
        -Commands $commands
    if ($hit.Outcome -cne 'hit') { throw "expected hit, got $($hit.Outcome)" }
    if ([int]$hit.CachePrepareMs -ne 0) { throw 'hit recorded prepare time' }
    if ([int]$hit.SourceHashMs -lt 0 -or [int]$hit.CacheValidateMs -lt 0) { throw 'hit timings were negative' }
    if ($script:exportCount -ne 0) { throw 'valid winner invoked export/merge' }

    $failRoot = Join-Path $root 'fail-iso'
    New-IsoTree -TreeRoot $failRoot
    $failIso = Join-Path $root 'fail.iso'
    Set-Content -LiteralPath $failIso -Value 'other-iso' -Encoding utf8 -NoNewline
    $failSha = Get-Sha256Lower $failIso
    $failLen = [long](Get-Item -LiteralPath $failIso).Length
    $failEntry = Get-WinMintMediaCacheEntry -CacheRoot $cacheRoot -SourceIsoSha256 $failSha -WimIndex $wimIndex -Schema $schema
    $failCommands = New-TestCommands -ExportImage {
        param($SourceWim, $SourceIndex, $DestWim)
        throw 'injected export failure'
    } -CopyTree {
        param($Source, $Destination)
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
    } -MountIso { param($IsoPath) $failRoot }
    $threw = $false
    try {
        Initialize-WinMintPreparedMedia `
            -SourceIso $failIso `
            -SourceIsoSha256 $failSha `
            -SourceIsoLength $failLen `
            -WimIndex $wimIndex `
            -Schema $schema `
            -CacheRoot $cacheRoot `
            -ExpectedIdentity $expected `
            -Commands $failCommands | Out-Null
    }
    catch {
        $threw = $true
        if ([string]$_.Exception.Message -notmatch 'injected export failure') {
            throw "unexpected failure: $($_.Exception.Message)"
        }
    }
    Assert-True $threw 'export failure did not throw'
    Assert-False (Test-Path -LiteralPath $failEntry) 'failure left a final entry'
    $failParent = Split-Path $failEntry -Parent
    if (Test-Path -LiteralPath $failParent) {
        $stuck = @(Get-ChildItem -LiteralPath $failParent -Force -Directory | Where-Object { $_.Name.StartsWith('.prepare-') })
        if ($stuck.Count -ne 0) { throw 'failed prepare left staging' }
    }

    $partial = Join-Path $root 'partial-entry'
    New-Item -ItemType Directory -Force -Path (Join-Path $partial 'media\sources') | Out-Null
    Assert-False (
        (Test-WinMintMediaCacheEntry -EntryPath $partial -SourceIsoSha256 $script:sha -SourceIsoLength $script:isoLength -WimIndex $wimIndex -Schema $schema -ExpectedIdentity $expected -CacheRoot $cacheRoot -Commands $commands)
    ) 'partial entry accepted'

    $malformed = Join-Path $root 'malformed-entry'
    New-Item -ItemType Directory -Force -Path $malformed | Out-Null
    Set-Content -LiteralPath (Join-Path $malformed 'manifest.json') -Value '{' -Encoding utf8
    Assert-False (
        (Test-WinMintMediaCacheEntry -EntryPath $malformed -SourceIsoSha256 $script:sha -SourceIsoLength $script:isoLength -WimIndex $wimIndex -Schema $schema -ExpectedIdentity $expected -CacheRoot $cacheRoot -Commands $commands)
    ) 'malformed manifest accepted'

    $wrongKey = Join-Path $root 'wrong-key'
    Publish-HandEntry -EntryPath $wrongKey -Manifest @{
        schema            = $schema
        sourceIsoSha256   = ('b' * 64)
        sourceIsoLength   = $script:isoLength
        sourceIndex       = $wimIndex
        preparedUtc       = '2026-08-12T00:00:00Z'
        installWimSha256  = ('c' * 64)
        installWimLength  = 1
        bootWimSha256     = ('d' * 64)
        bootWimLength     = 1
        image             = @{ name = 'Windows 11 Pro'; architecture = 'ARM64'; edition = 'Professional'; build = '26100'; indexCount = 1 }
    }
    Assert-False (
        (Test-WinMintMediaCacheEntry -EntryPath $wrongKey -SourceIsoSha256 $script:sha -SourceIsoLength $script:isoLength -WimIndex $wimIndex -Schema $schema -ExpectedIdentity $expected -CacheRoot $cacheRoot -Commands $commands)
    ) 'wrong-key entry accepted'

    $wrongLen = Join-Path $root 'wrong-len'
    Publish-HandEntry -EntryPath $wrongLen
    $lenDoc = Get-Content -LiteralPath (Join-Path $wrongLen 'manifest.json') -Raw | ConvertFrom-Json
    $lenHash = @{
        schema            = [int]$lenDoc.schema
        sourceIsoSha256   = [string]$lenDoc.sourceIsoSha256
        sourceIsoLength   = [long]($script:isoLength + 1)
        sourceIndex       = [int]$lenDoc.sourceIndex
        preparedUtc       = [string]$lenDoc.preparedUtc
        installWimSha256  = [string]$lenDoc.installWimSha256
        installWimLength  = [long]$lenDoc.installWimLength
        bootWimSha256     = [string]$lenDoc.bootWimSha256
        bootWimLength     = [long]$lenDoc.bootWimLength
        image             = @{
            name         = [string]$lenDoc.image.name
            architecture = [string]$lenDoc.image.architecture
            edition      = [string]$lenDoc.image.edition
            build        = [string]$lenDoc.image.build
            indexCount   = [int]$lenDoc.image.indexCount
        }
    }
    ($lenHash | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $wrongLen 'manifest.json') -Encoding utf8
    Assert-False (
        (Test-WinMintMediaCacheEntry -EntryPath $wrongLen -SourceIsoSha256 $script:sha -SourceIsoLength $script:isoLength -WimIndex $wimIndex -Schema $schema -ExpectedIdentity $expected -CacheRoot $cacheRoot -Commands $commands)
    ) 'wrong-length entry accepted'

    $wrongHash = Join-Path $root 'wrong-hash'
    Publish-HandEntry -EntryPath $wrongHash
    $hashDoc = Get-Content -LiteralPath (Join-Path $wrongHash 'manifest.json') -Raw | ConvertFrom-Json
    $hashDoc.installWimSha256 = 'e' * 64
    ($hashDoc | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $wrongHash 'manifest.json') -Encoding utf8
    Assert-False (
        (Test-WinMintMediaCacheEntry -EntryPath $wrongHash -SourceIsoSha256 $script:sha -SourceIsoLength $script:isoLength -WimIndex $wimIndex -Schema $schema -ExpectedIdentity $expected -CacheRoot $cacheRoot -Commands $commands)
    ) 'wrong-hash entry accepted'

    $multi = Join-Path $root 'multi-index'
    Publish-HandEntry -EntryPath $multi -InstallContent 'MULTI-INDEX-INSTALL-WIM'
    Assert-False (
        (Test-WinMintMediaCacheEntry -EntryPath $multi -SourceIsoSha256 $script:sha -SourceIsoLength $script:isoLength -WimIndex $wimIndex -Schema $schema -ExpectedIdentity $expected -CacheRoot $cacheRoot -Commands $commands)
    ) 'multi-index entry accepted'

    $invalid = Join-Path $cacheRoot 'v1' $script:sha 'index-99'
    Publish-HandEntry -EntryPath $invalid -InstallContent 'MULTI-INDEX-INSTALL-WIM'
    $beforeHash = Get-Sha256Lower (Join-Path $invalid 'media\sources\install.wim')
    $moved = Move-WinMintInvalidMediaCacheEntry -EntryPath $invalid
    Assert-False (Test-Path -LiteralPath $invalid) 'invalid entry was edited in place instead of renamed'
    Assert-True (Test-Path -LiteralPath $moved) 'quarantine destination missing'
    if ((Split-Path -Leaf $moved) -notmatch '^index-99\.invalid-\d{8}T\d{6}Z-[0-9a-f]{32}$') {
        throw "quarantine name unexpected: $(Split-Path -Leaf $moved)"
    }
    if ((Get-Sha256Lower (Join-Path $moved 'media\sources\install.wim')) -cne $beforeHash) {
        throw 'quarantine mutated WIM bytes'
    }

    $rebuildIso = Join-Path $root 'rebuild.iso'
    $rebuildTree = Join-Path $root 'rebuild-tree'
    New-IsoTree -TreeRoot $rebuildTree
    Set-Content -LiteralPath $rebuildIso -Value 'rebuild-iso' -Encoding utf8 -NoNewline
    $rebuildSha = Get-Sha256Lower $rebuildIso
    $rebuildLen = [long](Get-Item -LiteralPath $rebuildIso).Length
    $rebuildEntry = Get-WinMintMediaCacheEntry -CacheRoot $cacheRoot -SourceIsoSha256 $rebuildSha -WimIndex $wimIndex -Schema $schema
    Publish-HandEntry -EntryPath $rebuildEntry -InstallContent 'MULTI-INDEX-INSTALL-WIM'
    $script:rebuildExports = 0
    $rebuildCommands = New-TestCommands -MountIso { param($IsoPath) $rebuildTree } -ExportImage {
        param($SourceWim, $SourceIndex, $DestWim)
        $script:rebuildExports++
        Set-Content -LiteralPath $DestWim -Value 'SINGLE-INDEX-INSTALL-WIM' -Encoding utf8 -NoNewline
    } -CopyTree {
        param($Source, $Destination)
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
    }
    $rebuilt = Initialize-WinMintPreparedMedia `
        -SourceIso $rebuildIso `
        -SourceIsoSha256 $rebuildSha `
        -SourceIsoLength $rebuildLen `
        -WimIndex $wimIndex `
        -Schema $schema `
        -CacheRoot $cacheRoot `
        -ExpectedIdentity $expected `
        -Commands $rebuildCommands
    if ($rebuilt.Outcome -cne 'miss-rebuilt') { throw "expected miss-rebuilt, got $($rebuilt.Outcome)" }
    if ($script:rebuildExports -ne 1) { throw "rebuild export count $($script:rebuildExports)" }
    $quarantined = @(Get-ChildItem -LiteralPath (Split-Path $rebuildEntry -Parent) -Force -Directory |
        Where-Object { $_.Name -like 'index-3.invalid-*' })
    if ($quarantined.Count -lt 1) { throw 'invalid entry was not quarantined before rebuild' }

    $script:rebuildExports = 0
    $stillBad = New-TestCommands -MountIso { param($IsoPath) $rebuildTree } -ExportImage {
        param($SourceWim, $SourceIndex, $DestWim)
        $script:rebuildExports++
        throw 'second prepare refused'
    } -CopyTree {
        param($Source, $Destination)
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
    }
    Remove-Item -LiteralPath (Join-Path $rebuildEntry 'media\sources\boot.wim') -Force
    $secondThrow = $false
    try {
        Initialize-WinMintPreparedMedia `
            -SourceIso $rebuildIso `
            -SourceIsoSha256 $rebuildSha `
            -SourceIsoLength $rebuildLen `
            -WimIndex $wimIndex `
            -Schema $schema `
            -CacheRoot $cacheRoot `
            -ExpectedIdentity $expected `
            -Commands $stillBad | Out-Null
    }
    catch { $secondThrow = $true }
    Assert-True $secondThrow 'still-invalid rebuilt entry did not fail'
    if ($script:rebuildExports -ne 1) { throw 'rebuild was attempted more than once' }

    $changed = Join-Path $root 'changed.iso'
    Copy-Item -LiteralPath $isoPath -Destination $changed
    [IO.File]::WriteAllBytes($changed, [byte[]](1..32))
    $sourceThrow = $false
    try {
        Initialize-WinMintPreparedMedia `
            -SourceIso $changed `
            -SourceIsoSha256 $script:sha `
            -SourceIsoLength $script:isoLength `
            -WimIndex $wimIndex `
            -Schema $schema `
            -CacheRoot $cacheRoot `
            -ExpectedIdentity $expected `
            -Commands $commands | Out-Null
    }
    catch { $sourceThrow = $true }
    Assert-True $sourceThrow 'changed Source ISO bytes were not rechecked'

    $esdTree = Join-Path $root 'esd-tree'
    New-Item -ItemType Directory -Force -Path (Join-Path $esdTree 'sources') | Out-Null
    Set-Content -LiteralPath (Join-Path $esdTree 'sources\install.esd') -Value 'ESD' -Encoding utf8 -NoNewline
    Set-Content -LiteralPath (Join-Path $esdTree 'sources\boot.wim') -Value 'BOOT-WIM' -Encoding utf8 -NoNewline
    $esdIso = Join-Path $root 'esd.iso'
    Set-Content -LiteralPath $esdIso -Value 'esd-iso' -Encoding utf8 -NoNewline
    $esdSha = Get-Sha256Lower $esdIso
    $esdLen = [long](Get-Item -LiteralPath $esdIso).Length
    $esdCommands = New-TestCommands -MountIso { param($IsoPath) $esdTree } -CopyTree {
        param($Source, $Destination)
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
    }
    $esdThrow = $false
    $esdMessage = ''
    try {
        Initialize-WinMintPreparedMedia `
            -SourceIso $esdIso `
            -SourceIsoSha256 $esdSha `
            -SourceIsoLength $esdLen `
            -WimIndex $wimIndex `
            -Schema $schema `
            -CacheRoot $cacheRoot `
            -ExpectedIdentity $expected `
            -Commands $esdCommands | Out-Null
    }
    catch {
        $esdThrow = $true
        $esdMessage = [string]$_.Exception.Message
    }
    Assert-True $esdThrow 'install.esd was accepted'
    if ($esdMessage -cne 'install.esd present; convert to WIM before Apply (not implemented)') {
        throw "install.esd message: $esdMessage"
    }

    $work = Join-Path $root 'work'
    $mediaDir = Join-Path $work 'media'
    $preparedMedia = Join-Path $script:entryPath 'media'
    $script:copyCount = 0
    $script:mountCount = 0
    $script:exportCount = 0
    $stageCommands = New-TestCommands -CopyTree {
        param($Source, $Destination)
        $script:copyCount++
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
    } -MountIso {
        param($IsoPath)
        $script:mountCount++
        $isoTree
    } -ExportImage {
        param($SourceWim, $SourceIndex, $DestWim)
        $script:exportCount++
        Set-Content -LiteralPath $DestWim -Value 'SINGLE-INDEX-INSTALL-WIM' -Encoding utf8 -NoNewline
    }

    $leftoverPrevious = Join-Path $work 'media.previous-old'
    New-Item -ItemType Directory -Force -Path (Join-Path $leftoverPrevious 'sources') | Out-Null
    Set-Content -LiteralPath (Join-Path $leftoverPrevious 'stale.txt') -Value 'old-previous' -Encoding utf8
    New-Item -ItemType Directory -Force -Path (Join-Path $mediaDir 'sources') | Out-Null
    Set-Content -LiteralPath (Join-Path $mediaDir 'canary.txt') -Value 'from-prior-apply' -Encoding utf8

    $hit = Initialize-WinMintPreparedMedia `
        -SourceIso $isoPath `
        -SourceIsoSha256 $script:sha `
        -SourceIsoLength $script:isoLength `
        -WimIndex $wimIndex `
        -Schema $schema `
        -CacheRoot $cacheRoot `
        -ExpectedIdentity $expected `
        -Commands $stageCommands
    if ($hit.Outcome -cne 'hit') { throw "expected hit before staged copy, got $($hit.Outcome)" }
    if ($script:mountCount -ne 0) { throw 'hit invoked Source ISO mount' }
    if ($script:exportCount -ne 0) { throw 'hit invoked WIM export' }
    $copiesBefore = $script:copyCount

    $copied = Copy-WinMintRunMedia `
        -PreparedMedia $preparedMedia `
        -MediaDir $mediaDir `
        -ExpectedIdentity $expected `
        -Commands $stageCommands
    if ($script:copyCount -ne ($copiesBefore + 1)) { throw 'hit did not copy fresh staged media' }
    if ($script:mountCount -ne 0 -or $script:exportCount -ne 0) { throw 'staged copy invoked prepare commands' }
    Assert-True (Test-Path -LiteralPath (Join-Path $mediaDir 'sources\install.wim')) 'staged install.wim missing'
    Assert-False (Test-Path -LiteralPath (Join-Path $mediaDir 'canary.txt')) 'prior staged media was reused in place'
    Assert-True (Test-Path -LiteralPath $copied.PreviousMedia) 'prior staged media was not moved aside'
    Assert-True (Test-Path -LiteralPath (Join-Path $copied.PreviousMedia 'canary.txt')) 'moved prior media lost canary'
    Assert-True (Test-Path -LiteralPath (Join-Path $leftoverPrevious 'stale.txt')) 'unrelated previous media was removed'

    $preparedWim = Join-Path $preparedMedia 'sources\install.wim'
    $stagedWim = Join-Path $mediaDir 'sources\install.wim'
    $preparedId = (& fsutil.exe file queryfileid $preparedWim) -join ' '
    $stagedId = (& fsutil.exe file queryfileid $stagedWim) -join ' '
    if ([string]::IsNullOrWhiteSpace($preparedId) -or $preparedId -eq $stagedId) {
        throw "staged WIM is not an independent file record: prepared=$preparedId staged=$stagedId"
    }
    $preparedHash = Get-Sha256Lower $preparedWim
    Set-Content -LiteralPath $stagedWim -Value 'MUTATED-STAGED-WIM' -Encoding utf8 -NoNewline
    if ((Get-Sha256Lower $preparedWim) -cne $preparedHash) {
        throw 'mutating staged WIM changed prepared hash'
    }

    $incomingFail = Join-Path $root 'incoming-fail'
    $failMedia = Join-Path $incomingFail 'media'
    New-Item -ItemType Directory -Force -Path $failMedia | Out-Null
    Set-Content -LiteralPath (Join-Path $failMedia 'keep.txt') -Value 'existing' -Encoding utf8
    $failThrow = $false
    try {
        Copy-WinMintRunMedia `
            -PreparedMedia $preparedMedia `
            -MediaDir $failMedia `
            -ExpectedIdentity $expected `
            -Commands (New-TestCommands -CopyTree { throw 'injected copy failure' }) | Out-Null
    }
    catch {
        $failThrow = $true
        if ([string]$_.Exception.Message -notmatch 'injected copy failure') {
            throw "unexpected copy failure: $($_.Exception.Message)"
        }
    }
    Assert-True $failThrow 'failed staged copy did not throw'
    Assert-False (Test-Path -LiteralPath $failMedia) 'failed incoming copy was renamed to media'
    $incomingLeft = @(Get-ChildItem -LiteralPath $incomingFail -Force -Directory | Where-Object { $_.Name -like 'media.incoming-*' })
    $previousLeft = @(Get-ChildItem -LiteralPath $incomingFail -Force -Directory | Where-Object { $_.Name -like 'media.previous-*' })
    if ($previousLeft.Count -ne 1) { throw 'failed copy did not preserve moved-aside staged media' }
    if ($incomingLeft.Count -gt 1) { throw 'failed copy left extra incoming directories' }

    $cacheWim = Join-Path $script:entryPath 'media\sources\install.wim'
    $mountThrow = $false
    try { Assert-WinMintMountImagePath -ImageFile $cacheWim -CacheRoot $cacheRoot }
    catch {
        $mountThrow = $true
        if ([string]$_.Exception.Message -notmatch 'prepared-media root') {
            throw "unexpected mount-path message: $($_.Exception.Message)"
        }
    }
    Assert-True $mountThrow 'prepared WIM path was allowed as a mount image'
    Assert-WinMintMountImagePath -ImageFile $stagedWim -CacheRoot $cacheRoot
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Source media cache contract tests passed.'
