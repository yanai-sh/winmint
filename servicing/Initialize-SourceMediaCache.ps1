#requires -Version 7.6
Set-StrictMode -Version Latest

if (-not (Get-Command -Name Get-WimMetadataSnapshot -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-WimMetadata.ps1')
}

function Test-WinMintSelectedImage {
    param(
        [Parameter(Mandatory)] $Snapshot,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $ExpectedIdentity
    )

    if ([int]$Snapshot.IndexCount -ne 1) { return $false }
    if ([string]$Snapshot.Name -cne [string]$ExpectedIdentity.imageName) { return $false }
    if ([string]$Snapshot.Architecture -ine [string]$ExpectedIdentity.architecture) { return $false }
    if ([string]$Snapshot.Edition -ine [string]$ExpectedIdentity.edition) { return $false }
    if ([string]$Snapshot.Build -cne [string]$ExpectedIdentity.build) { return $false }
    return $true
}

function Get-WinMintSha256Lower([string] $Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-WinMintMediaCacheCommand {
    param($Commands, [string] $Name)
    if ($null -eq $Commands) { return $null }
    return $Commands[$Name]
}

function Initialize-WinMintMediaCacheRoot {
    param([Parameter(Mandatory)] [string] $CacheRoot)
    $created = -not (Test-Path -LiteralPath $CacheRoot)
    New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null
    if (-not $created) { return }
    # ponytail: ACL only the host ProgramData root; temp contract trees stay writable by the test user.
    $programData = [Environment]::GetFolderPath('CommonApplicationData')
    $prefix = $programData.TrimEnd([char]'\') + '\'
    $full = [IO.Path]::GetFullPath($CacheRoot)
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return }
    $acl = Get-Acl -LiteralPath $CacheRoot
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($id in @('BUILTIN\Administrators', 'NT AUTHORITY\SYSTEM')) {
        $acl.AddAccessRule(
            [System.Security.AccessControl.FileSystemAccessRule]::new(
                $id, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    }
    Set-Acl -LiteralPath $CacheRoot -AclObject $acl
}

function Assert-WinMintNoReparseBetween {
    param([Parameter(Mandatory)] [string] $Root, [Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Root)) { return }
    $rootFull = [IO.Path]::GetFullPath($Root)
    $pathFull = [IO.Path]::GetFullPath($Path)
    $prefix = $rootFull.TrimEnd([char]'\') + '\'
    if (-not ($pathFull.Equals($rootFull, [StringComparison]::OrdinalIgnoreCase) -or
            $pathFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))) {
        throw "Prepared media path escapes cache root: $Path"
    }
    $current = $rootFull
    $item = Get-Item -LiteralPath $current -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "reparse point rejected: $current"
    }
    $rel = $pathFull.Substring($rootFull.TrimEnd([char]'\').Length).TrimStart('\', '/')
    if ([string]::IsNullOrWhiteSpace($rel)) { return }
    foreach ($part in $rel.Split([char[]]@('\', '/'))) {
        if ($part -eq '') { continue }
        $current = Join-Path $current $part
        if (-not (Test-Path -LiteralPath $current)) { return }
        $item = Get-Item -LiteralPath $current -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "reparse point rejected: $current"
        }
    }
}

function Assert-WinMintSourceIsoIdentity {
    param(
        [Parameter(Mandatory)] [string] $SourceIso,
        [Parameter(Mandatory)] [string] $SourceIsoSha256,
        [Parameter(Mandatory)] [long] $SourceIsoLength
    )
    if ([string]::IsNullOrWhiteSpace($SourceIso) -or -not (Test-Path -LiteralPath $SourceIso -PathType Leaf)) {
        throw "Source ISO not found: $SourceIso"
    }
    if ($SourceIsoSha256 -notmatch '^[0-9a-f]{64}$') {
        throw 'Source ISO SHA-256 must be lowercase 64-character hex.'
    }
    $len = [long](Get-Item -LiteralPath $SourceIso).Length
    if ($len -ne $SourceIsoLength) {
        throw "Source ISO length mismatch: expected $SourceIsoLength, got $len"
    }
    $actual = Get-WinMintSha256Lower $SourceIso
    if ($actual -cne $SourceIsoSha256) {
        throw 'Source ISO hash mismatch between host identity and file bytes.'
    }
}

function Clear-WinMintTreeReadOnly([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Get-ChildItem -LiteralPath $Path -Recurse -Force -File | ForEach-Object {
        if ($_.IsReadOnly) { $_.IsReadOnly = $false }
    }
}

function Copy-WinMintMediaTree {
    param([string] $Source, [string] $Destination, $Commands)
    $custom = Get-WinMintMediaCacheCommand -Commands $Commands -Name 'CopyTree'
    if ($custom) {
        & $custom $Source $Destination
        return
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    & robocopy.exe $Source $Destination /E /COPY:DAT /R:2 /W:2 /NFL /NDL /NJH /NJS /NP | Out-Host
    $rc = $LASTEXITCODE
    if ($rc -ge 8) { throw "robocopy failed with exit $rc" }
}

function Get-WinMintCachedWimSnapshot {
    param([string] $WimFile, [int] $Index, $Commands)
    $custom = Get-WinMintMediaCacheCommand -Commands $Commands -Name 'GetWimSnapshot'
    if ($custom) { return & $custom $WimFile $Index }
    Get-WimMetadataSnapshot -WimFile $WimFile -Index $Index
}

function Invoke-WinMintExportImage {
    param([string] $SourceWim, [int] $SourceIndex, [string] $DestWim, $Commands)
    $custom = Get-WinMintMediaCacheCommand -Commands $Commands -Name 'ExportImage'
    if ($custom) {
        & $custom $SourceWim $SourceIndex $DestWim
        return
    }
    Clear-WimReadOnly -WimFile $SourceWim
    if (Test-Path -LiteralPath $DestWim) { Remove-Item -LiteralPath $DestWim -Force }
    & dism.exe /English /Export-Image /SourceImageFile:$SourceWim /SourceIndex:$SourceIndex /DestinationImageFile:$DestWim /Compress:fast
    if ($LASTEXITCODE -ne 0) { throw "Export-Image (single-index) failed: $LASTEXITCODE" }
}

function Get-WinMintMediaCacheEntry {
    param(
        [Parameter(Mandatory)] [string] $CacheRoot,
        [Parameter(Mandatory)] [string] $SourceIsoSha256,
        [Parameter(Mandatory)] [int] $WimIndex,
        [int] $Schema = 1
    )
    if ($SourceIsoSha256 -notmatch '^[0-9a-f]{64}$') {
        throw 'Source ISO SHA-256 must be lowercase 64-character hex.'
    }
    if ($WimIndex -le 0) { throw 'WIM index must be a positive integer.' }
    if ($Schema -le 0) { throw 'Prepared media schema must be a positive integer.' }
    $indexName = 'index-' + $WimIndex.ToString([cultureinfo]::InvariantCulture)
    Join-Path $CacheRoot ('v' + $Schema.ToString([cultureinfo]::InvariantCulture)) $SourceIsoSha256 $indexName
}

function Test-WinMintMediaCacheEntry {
    param(
        [Parameter(Mandatory)] [string] $EntryPath,
        [Parameter(Mandatory)] [string] $SourceIsoSha256,
        [Parameter(Mandatory)] [long] $SourceIsoLength,
        [Parameter(Mandatory)] [int] $WimIndex,
        [int] $Schema = 1,
        [System.Collections.IDictionary] $ExpectedIdentity,
        [string] $CacheRoot,
        $Commands
    )
    try {
        if ($CacheRoot) { Assert-WinMintNoReparseBetween -Root $CacheRoot -Path $EntryPath }
        $manifestPath = Join-Path $EntryPath 'manifest.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $false }
        $m = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
        if ([int]$m.schema -ne $Schema) { return $false }
        if ([string]$m.sourceIsoSha256 -cne $SourceIsoSha256) { return $false }
        if ([long]$m.sourceIsoLength -ne $SourceIsoLength) { return $false }
        if ([int]$m.sourceIndex -ne $WimIndex) { return $false }
        $install = Join-Path $EntryPath 'media\sources\install.wim'
        $boot = Join-Path $EntryPath 'media\sources\boot.wim'
        if (-not (Test-Path -LiteralPath $install -PathType Leaf)) { return $false }
        if (-not (Test-Path -LiteralPath $boot -PathType Leaf)) { return $false }
        if ([long](Get-Item -LiteralPath $install).Length -ne [long]$m.installWimLength) { return $false }
        if ([long](Get-Item -LiteralPath $boot).Length -ne [long]$m.bootWimLength) { return $false }
        if ((Get-WinMintSha256Lower $install) -cne [string]$m.installWimSha256) { return $false }
        if ((Get-WinMintSha256Lower $boot) -cne [string]$m.bootWimSha256) { return $false }
        $snap = Get-WinMintCachedWimSnapshot -WimFile $install -Index 1 -Commands $Commands
        if ([int]$snap.IndexCount -ne 1) { return $false }
        if ([string]$snap.Name -cne [string]$m.image.name) { return $false }
        if ([string]$snap.Architecture -ine [string]$m.image.architecture) { return $false }
        if ([string]$snap.Edition -ine [string]$m.image.edition) { return $false }
        if ([string]$snap.Build -cne [string]$m.image.build) { return $false }
        if ([int]$m.image.indexCount -ne 1) { return $false }
        if ($ExpectedIdentity -and -not (Test-WinMintSelectedImage -Snapshot $snap -ExpectedIdentity $ExpectedIdentity)) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

function Move-WinMintInvalidMediaCacheEntry {
    param([Parameter(Mandatory)] [string] $EntryPath)
    if (-not (Test-Path -LiteralPath $EntryPath -PathType Container)) {
        throw "Prepared media entry missing: $EntryPath"
    }
    $stamp = [datetime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $name = (Split-Path -Leaf $EntryPath) + '.invalid-' + $stamp + '-' + [guid]::NewGuid().ToString('N')
    Rename-Item -LiteralPath $EntryPath -NewName $name
    Join-Path (Split-Path -Parent $EntryPath) $name
}

function New-WinMintMediaCacheEntry {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)] [string] $SourceIso,
        [Parameter(Mandatory)] [string] $SourceIsoSha256,
        [Parameter(Mandatory)] [long] $SourceIsoLength,
        [Parameter(Mandatory)] [int] $WimIndex,
        [int] $Schema = 1,
        [Parameter(Mandatory)] [string] $CacheRoot,
        [System.Collections.IDictionary] $ExpectedIdentity,
        $Commands
    )
    Initialize-WinMintMediaCacheRoot -CacheRoot $CacheRoot
    $entry = Get-WinMintMediaCacheEntry -CacheRoot $CacheRoot -SourceIsoSha256 $SourceIsoSha256 -WimIndex $WimIndex -Schema $Schema
    $parent = Split-Path -Parent $entry
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Assert-WinMintNoReparseBetween -Root $CacheRoot -Path $parent

    if (Test-WinMintMediaCacheEntry -EntryPath $entry -SourceIsoSha256 $SourceIsoSha256 -SourceIsoLength $SourceIsoLength -WimIndex $WimIndex -Schema $Schema -ExpectedIdentity $ExpectedIdentity -CacheRoot $CacheRoot -Commands $Commands) {
        return $entry
    }

    $guid = [guid]::NewGuid().ToString('N')
    $staging = Join-Path $parent ('.prepare-' + $SourceIsoSha256 + '-index-' + $WimIndex.ToString([cultureinfo]::InvariantCulture) + '-' + $guid)
    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    $media = Join-Path $staging 'media'
    $mounted = $false
    try {
        $mountIso = Get-WinMintMediaCacheCommand -Commands $Commands -Name 'MountIso'
        if ($mountIso) {
            $isoRoot = & $mountIso $SourceIso
        }
        else {
            $disk = Mount-DiskImage -ImagePath $SourceIso -PassThru -ErrorAction Stop
            Start-Sleep -Seconds 2
            $letter = ($disk | Get-Volume | Select-Object -First 1).DriveLetter
            if ([string]::IsNullOrWhiteSpace($letter)) { throw 'ISO mounted but no drive letter' }
            $isoRoot = "${letter}:"
        }
        $mounted = $true
        Copy-WinMintMediaTree -Source $isoRoot -Destination $media -Commands $Commands
        Clear-WinMintTreeReadOnly $media

        $install = Join-Path $media 'sources\install.wim'
        $boot = Join-Path $media 'sources\boot.wim'
        if (-not (Test-Path -LiteralPath $install -PathType Leaf)) {
            $esd = Join-Path $media 'sources\install.esd'
            if (Test-Path -LiteralPath $esd -PathType Leaf) {
                throw 'install.esd present; convert to WIM before Apply (not implemented)'
            }
            throw "install.wim missing under $media\sources"
        }
        if (-not (Test-Path -LiteralPath $boot -PathType Leaf)) {
            throw 'boot.wim is required on Source ISO media'
        }

        $before = Get-WinMintCachedWimSnapshot -WimFile $install -Index $WimIndex -Commands $Commands
        Assert-WimMetadataPresent -Snapshot $before -Context 'Prepared media selected index'
        $tmp = Join-Path $media 'sources\install.single.wim'
        Invoke-WinMintExportImage -SourceWim $install -SourceIndex $WimIndex -DestWim $tmp -Commands $Commands
        Remove-Item -LiteralPath $install -Force
        Move-Item -LiteralPath $tmp -Destination $install -Force
        Clear-WimReadOnly -WimFile $install
        $after = Get-WinMintCachedWimSnapshot -WimFile $install -Index 1 -Commands $Commands
        if ([int]$after.IndexCount -ne 1) {
            throw "After single-index export, install.wim has $($after.IndexCount) indexes (need 1)"
        }
        Assert-WimMetadataStable -Before $before -After $after -Context 'Prepared media single-index export'
        if ($ExpectedIdentity -and -not (Test-WinMintSelectedImage -Snapshot $after -ExpectedIdentity $ExpectedIdentity)) {
            throw 'Prepared install.wim does not match the approved selected-image metadata.'
        }
        Write-WinMintEditionConfig -MediaDir $media -Snapshot $after

        $manifest = [ordered]@{
            schema           = $Schema
            sourceIsoSha256  = $SourceIsoSha256
            sourceIsoLength  = $SourceIsoLength
            sourceIndex      = $WimIndex
            preparedUtc      = [datetime]::UtcNow.ToUniversalTime().ToString('o')
            installWimSha256 = Get-WinMintSha256Lower $install
            installWimLength = [long](Get-Item -LiteralPath $install).Length
            bootWimSha256    = Get-WinMintSha256Lower $boot
            bootWimLength    = [long](Get-Item -LiteralPath $boot).Length
            image            = [ordered]@{
                name         = [string]$after.Name
                architecture = [string]$after.Architecture
                edition      = [string]$after.Edition
                build        = [string]$after.Build
                indexCount   = 1
            }
        }
        $manifestPath = Join-Path $staging 'manifest.json'
        ($manifest | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $manifestPath -Encoding utf8
        $parsed = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ([int]$parsed.schema -ne $Schema -or
            [string]$parsed.sourceIsoSha256 -cne $SourceIsoSha256 -or
            [long]$parsed.sourceIsoLength -ne $SourceIsoLength -or
            [int]$parsed.sourceIndex -ne $WimIndex) {
            throw 'Prepared media manifest parse-back failed'
        }

        if (Test-Path -LiteralPath $entry) {
            if (Test-WinMintMediaCacheEntry -EntryPath $entry -SourceIsoSha256 $SourceIsoSha256 -SourceIsoLength $SourceIsoLength -WimIndex $WimIndex -Schema $Schema -ExpectedIdentity $ExpectedIdentity -CacheRoot $CacheRoot -Commands $Commands) {
                Remove-Item -LiteralPath $staging -Recurse -Force
                return $entry
            }
            throw 'Prepared media final entry exists but is invalid; not merging'
        }
        Rename-Item -LiteralPath $staging -NewName (Split-Path -Leaf $entry)
        return $entry
    }
    catch {
        if ($staging -and (Test-Path -LiteralPath $staging)) {
            # ponytail: skip DISM mounted-WIM probe until mount recovery exists; staging names are unique per prepare.
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    finally {
        if ($mounted) {
            $dismount = Get-WinMintMediaCacheCommand -Commands $Commands -Name 'DismountIso'
            if ($dismount) {
                & $dismount $SourceIso
            }
            else {
                Dismount-DiskImage -ImagePath $SourceIso -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }
}

function Initialize-WinMintPreparedMedia {
    param(
        [Parameter(Mandatory)] [string] $SourceIso,
        [Parameter(Mandatory)] [string] $SourceIsoSha256,
        [Parameter(Mandatory)] [long] $SourceIsoLength,
        [Parameter(Mandatory)] [int] $WimIndex,
        [int] $Schema = 1,
        [Parameter(Mandatory)] [string] $CacheRoot,
        [System.Collections.IDictionary] $ExpectedIdentity,
        $Commands
    )
    $hashClock = [System.Diagnostics.Stopwatch]::StartNew()
    Assert-WinMintSourceIsoIdentity -SourceIso $SourceIso -SourceIsoSha256 $SourceIsoSha256 -SourceIsoLength $SourceIsoLength
    $hashClock.Stop()

    $entry = Get-WinMintMediaCacheEntry -CacheRoot $CacheRoot -SourceIsoSha256 $SourceIsoSha256 -WimIndex $WimIndex -Schema $Schema
    $testArgs = @{
        EntryPath         = $entry
        SourceIsoSha256   = $SourceIsoSha256
        SourceIsoLength   = $SourceIsoLength
        WimIndex          = $WimIndex
        Schema            = $Schema
        ExpectedIdentity  = $ExpectedIdentity
        CacheRoot         = $CacheRoot
        Commands          = $Commands
    }
    $validateClock = [System.Diagnostics.Stopwatch]::StartNew()
    $hit = Test-WinMintMediaCacheEntry @testArgs
    $validateClock.Stop()
    if ($hit) {
        return [pscustomobject]@{
            Outcome          = 'hit'
            EntryPath        = $entry
            SourceHashMs     = [int]$hashClock.ElapsedMilliseconds
            CacheValidateMs  = [int]$validateClock.ElapsedMilliseconds
            CachePrepareMs   = 0
        }
    }

    $quarantined = $false
    if (Test-Path -LiteralPath $entry) {
        Move-WinMintInvalidMediaCacheEntry -EntryPath $entry | Out-Null
        $quarantined = $true
    }

    $prepareClock = [System.Diagnostics.Stopwatch]::StartNew()
    New-WinMintMediaCacheEntry `
        -SourceIso $SourceIso `
        -SourceIsoSha256 $SourceIsoSha256 `
        -SourceIsoLength $SourceIsoLength `
        -WimIndex $WimIndex `
        -Schema $Schema `
        -CacheRoot $CacheRoot `
        -ExpectedIdentity $ExpectedIdentity `
        -Commands $Commands | Out-Null
    $prepareClock.Stop()

    if (Test-WinMintMediaCacheEntry @testArgs) {
        $outcome = if ($quarantined) { 'miss-rebuilt' } else { 'miss-prepared' }
        return [pscustomobject]@{
            Outcome          = $outcome
            EntryPath        = $entry
            SourceHashMs     = [int]$hashClock.ElapsedMilliseconds
            CacheValidateMs  = [int]$validateClock.ElapsedMilliseconds
            CachePrepareMs   = [int]$prepareClock.ElapsedMilliseconds
        }
    }
    throw 'Prepared media failed validation after prepare'
}

function Copy-WinMintRunMedia {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)] [string] $PreparedMedia,
        [Parameter(Mandatory)] [string] $MediaDir,
        [System.Collections.IDictionary] $ExpectedIdentity,
        $Commands
    )
    if (-not (Test-Path -LiteralPath $PreparedMedia -PathType Container)) {
        throw "Prepared media missing: $PreparedMedia"
    }

    $parent = Split-Path -Parent $MediaDir
    $leaf = Split-Path -Leaf $MediaDir
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $previous = $null
    if (Test-Path -LiteralPath $MediaDir) {
        $stamp = [datetime]::UtcNow.ToString('yyyyMMddHHmmss')
        $previousName = $leaf + '.previous-' + $stamp + '-' + [guid]::NewGuid().ToString('N')
        Rename-Item -LiteralPath $MediaDir -NewName $previousName
        $previous = Join-Path $parent $previousName
        if (-not (Test-Path -LiteralPath $previous)) {
            throw "Could not move existing staged media aside: $MediaDir"
        }
    }

    $incoming = Join-Path $parent ($leaf + '.incoming-' + [guid]::NewGuid().ToString('N'))
    $copyClock = [System.Diagnostics.Stopwatch]::StartNew()
    Copy-WinMintMediaTree -Source $PreparedMedia -Destination $incoming -Commands $Commands
    $copyClock.Stop()
    Clear-WinMintTreeReadOnly $incoming
    $wim = Join-Path $incoming 'sources\install.wim'
    if (-not (Test-Path -LiteralPath $wim -PathType Leaf)) {
        throw 'install.wim missing under staged incoming media'
    }
    $snap = Get-WinMintCachedWimSnapshot -WimFile $wim -Index 1 -Commands $Commands
    if ([int]$snap.IndexCount -ne 1) {
        throw "Staged install.wim has $($snap.IndexCount) indexes (need 1)"
    }
    Assert-WimMetadataPresent -Snapshot $snap -Context 'Staged media'
    if ($ExpectedIdentity -and -not (Test-WinMintSelectedImage -Snapshot $snap -ExpectedIdentity $ExpectedIdentity)) {
        throw 'Staged install.wim does not match the approved selected-image metadata.'
    }
    Rename-Item -LiteralPath $incoming -NewName $leaf

    [pscustomobject]@{
        MediaDir      = $MediaDir
        PreviousMedia = $previous
        CopyMs        = [int]$copyClock.ElapsedMilliseconds
        CopyMode      = 'copy'
    }
}

function Assert-WinMintMountImagePath {
    param(
        [Parameter(Mandatory)] [string] $ImageFile,
        [Parameter(Mandatory)] [string] $CacheRoot
    )
    $img = [IO.Path]::GetFullPath($ImageFile)
    $root = [IO.Path]::GetFullPath($CacheRoot).TrimEnd([char]'\') + '\'
    if ($img.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to mount a WIM under prepared-media root: $ImageFile"
    }
}

function Write-WinMintPreparedMediaResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Document
    )
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $temporaryPath = "$Path.tmp"
    try {
        ($Document | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $temporaryPath -Encoding utf8
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}
