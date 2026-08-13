#requires -Version 7.6
Set-StrictMode -Version Latest

$script:WinMintImageServicingMutexName = 'Global\WinMint.ImageServicing.v1'

function Get-WinMintServicingRoot {
    param([string] $ServicingRoot)
    if (-not [string]::IsNullOrWhiteSpace($ServicingRoot)) {
        return [IO.Path]::GetFullPath($ServicingRoot)
    }
    return [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'WinMint\Servicing'))
}

function Get-WinMintMountDirectory {
    param(
        [Parameter(Mandatory)] [ValidateSet('install', 'boot')] [string] $Kind,
        [string] $ServicingRoot
    )
    $root = Get-WinMintServicingRoot -ServicingRoot $ServicingRoot
    if ($Kind -eq 'boot') { return Join-Path $root 'boot-mount' }
    return Join-Path $root 'mount'
}

function Get-WinMintMountOwnerPath {
    param(
        [Parameter(Mandatory)] [ValidateSet('install', 'boot')] [string] $Kind,
        [string] $ServicingRoot
    )
    $leaf = if ($Kind -eq 'boot') { 'boot.json' } else { 'install.json' }
    return Join-Path (Get-WinMintServicingRoot -ServicingRoot $ServicingRoot) "mount-owners\$leaf"
}

function Get-WinMintMountCommand {
    param($Commands, [string] $Name)
    if ($null -eq $Commands) { return $null }
    return $Commands[$Name]
}

function Enter-WinMintImageServicingLock {
    $mutex = [System.Threading.Mutex]::new($false, $script:WinMintImageServicingMutexName)
    $acquired = $false
    try {
        $acquired = $mutex.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        $acquired = $true
    }
    if (-not $acquired) {
        $mutex.Dispose()
        throw 'servicing already active'
    }
    return $mutex
}

function Exit-WinMintImageServicingLock {
    param($Mutex)
    if ($null -eq $Mutex) { return }
    try { [void]$Mutex.ReleaseMutex() } catch {
        Write-Debug "ReleaseMutex: $_"
    }
    $Mutex.Dispose()
}

function Get-WinMintMountedImages {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    param($Commands)
    $injected = Get-WinMintMountCommand -Commands $Commands -Name 'GetMountedImages'
    if ($injected) {
        return @(& $injected)
    }

    $raw = & dism.exe /English /Get-MountedWimInfo 2>&1 | Out-String
    $images = [System.Collections.Generic.List[object]]::new()
    foreach ($match in [regex]::Matches($raw, '(?m)^Mount Dir : (.+)\r?\nImage File : (.+)\r?\nImage Index : (\d+)\r?\nMounted Read/Write : (.+)\r?\nStatus : (.+)\s*$')) {
        $images.Add([pscustomobject]@{
                MountDir  = $match.Groups[1].Value.Trim()
                ImageFile = $match.Groups[2].Value.Trim()
                Status    = $match.Groups[5].Value.Trim()
            })
    }
    return @($images)
}

function Test-WinMintProcessAlive {
    param(
        [Parameter(Mandatory)] [int] $ProcessId,
        $Commands
    )
    $injected = Get-WinMintMountCommand -Commands $Commands -Name 'TestProcessAlive'
    if ($injected) {
        return [bool](& $injected $ProcessId)
    }
    return $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Read-WinMintMountOwner {
    param(
        [Parameter(Mandatory)] [ValidateSet('install', 'boot')] [string] $Kind,
        [string] $ServicingRoot
    )
    $path = Get-WinMintMountOwnerPath -Kind $Kind -ServicingRoot $ServicingRoot
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Write-WinMintMountOwner {
    param(
        [Parameter(Mandatory)] [ValidateSet('install', 'boot')] [string] $Kind,
        [Parameter(Mandatory)] [string] $WorkDirectory,
        [Parameter(Mandatory)] [string] $MountDirectory,
        [Parameter(Mandatory)] [string] $ImageFile,
        [string] $ServicingRoot,
        [string] $SourceIsoSha256 = '',
        [int] $SourceIndex = 0,
        [string] $RunId = $env:WINMINT_SERVICING_RUN_ID
    )
    $path = Get-WinMintMountOwnerPath -Kind $Kind -ServicingRoot $ServicingRoot
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        $RunId = [guid]::NewGuid().ToString('N')
    }
    $doc = [ordered]@{
        schema          = 'winmint.mount-owner/v1'
        runId           = $RunId
        processId       = $PID
        mountKind       = $Kind
        workDirectory   = $WorkDirectory
        mountDirectory  = $MountDirectory
        imageFile       = $ImageFile
        startedUtc      = [datetime]::UtcNow.ToString('o')
        sourceIsoSha256 = $SourceIsoSha256
        sourceIndex     = $SourceIndex
    }
    $temporaryPath = "$path.tmp"
    try {
        ($doc | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $temporaryPath -Encoding utf8
        Move-Item -LiteralPath $temporaryPath -Destination $path -Force
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
    return $path
}

function Remove-WinMintMountOwner {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)] [ValidateSet('install', 'boot')] [string] $Kind,
        [string] $ServicingRoot
    )
    $path = Get-WinMintMountOwnerPath -Kind $Kind -ServicingRoot $ServicingRoot
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

function Invoke-WinMintUnmountDiscard {
    param(
        [Parameter(Mandatory)] [string] $MountDir,
        $Commands
    )
    $injected = Get-WinMintMountCommand -Commands $Commands -Name 'UnmountDiscard'
    if ($injected) {
        & $injected $MountDir
        return
    }
    & dism.exe /English /Unmount-Image /MountDir:$MountDir /Discard
    if ($LASTEXITCODE -ne 0) {
        throw "DISM Unmount-Image /Discard failed: $LASTEXITCODE"
    }
}

function Invoke-WinMintCleanupWim {
    param($Commands)
    $injected = Get-WinMintMountCommand -Commands $Commands -Name 'CleanupWim'
    if ($injected) {
        & $injected
        return
    }
    & dism.exe /English /Cleanup-Wim
    if ($LASTEXITCODE -ne 0) {
        throw "DISM Cleanup-Wim failed: $LASTEXITCODE"
    }
}

function Test-WinMintOwnedMountDir {
    param(
        [Parameter(Mandatory)] [string] $MountDir,
        [Parameter(Mandatory)] [string] $InstallMount,
        [Parameter(Mandatory)] [string] $BootMount
    )
    $full = [IO.Path]::GetFullPath($MountDir)
    return $full.Equals([IO.Path]::GetFullPath($InstallMount), [StringComparison]::OrdinalIgnoreCase) -or
        $full.Equals([IO.Path]::GetFullPath($BootMount), [StringComparison]::OrdinalIgnoreCase)
}

function Test-WinMintPreparedMediaPath {
    param(
        [Parameter(Mandatory)] [string] $ImageFile,
        [Parameter(Mandatory)] [string] $CacheRoot
    )
    if ([string]::IsNullOrWhiteSpace($ImageFile) -or [string]::IsNullOrWhiteSpace($CacheRoot)) {
        return $false
    }
    if (-not (Test-Path -LiteralPath $CacheRoot)) { return $false }
    $prefix = [IO.Path]::GetFullPath($CacheRoot).TrimEnd([char]'\') + '\'
    return [IO.Path]::GetFullPath($ImageFile).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Resolve-WinMintOwnedKind {
    param(
        [Parameter(Mandatory)] [string] $MountDir,
        [Parameter(Mandatory)] [string] $InstallMount,
        [Parameter(Mandatory)] [string] $BootMount
    )
    if ([IO.Path]::GetFullPath($MountDir).Equals([IO.Path]::GetFullPath($InstallMount), [StringComparison]::OrdinalIgnoreCase)) {
        return 'install'
    }
    if ([IO.Path]::GetFullPath($MountDir).Equals([IO.Path]::GetFullPath($BootMount), [StringComparison]::OrdinalIgnoreCase)) {
        return 'boot'
    }
    throw "unowned mount directory: $MountDir"
}

function Resolve-WinMintStaleMount {
    param(
        [string] $ServicingRoot,
        [string] $CacheRoot,
        $Commands
    )

    $root = Get-WinMintServicingRoot -ServicingRoot $ServicingRoot
    $installMount = Join-Path $root 'mount'
    $bootMount = Join-Path $root 'boot-mount'
    if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
        $CacheRoot = Join-Path $root 'media-cache'
    }

    $recoveryAction = 'none'
    $images = @(Get-WinMintMountedImages -Commands $Commands)

    foreach ($image in $images) {
        $imageFile = [string]$image.ImageFile
        $mountDir = [string]$image.MountDir
        if (Test-WinMintPreparedMediaPath -ImageFile $imageFile -CacheRoot $CacheRoot) {
            throw "Prepared media WIM is mounted and must not be discarded: $imageFile"
        }
        if (-not (Test-WinMintOwnedMountDir -MountDir $mountDir -InstallMount $installMount -BootMount $bootMount)) {
            continue
        }

        $kind = Resolve-WinMintOwnedKind -MountDir $mountDir -InstallMount $installMount -BootMount $bootMount
        $owner = Read-WinMintMountOwner -Kind $kind -ServicingRoot $root
        if ($null -ne $owner -and (Test-WinMintProcessAlive -ProcessId ([int]$owner.processId) -Commands $Commands)) {
            throw 'servicing already active'
        }

        try {
            Invoke-WinMintUnmountDiscard -MountDir $mountDir -Commands $Commands
        }
        catch {
            $message = [string]$_.Exception.Message
            if ($message -notmatch 'stale|corrupt') {
                throw
            }
            Invoke-WinMintCleanupWim -Commands $Commands
            $afterCleanup = @(Get-WinMintMountedImages -Commands $Commands)
            $still = @($afterCleanup | Where-Object {
                    Test-WinMintOwnedMountDir -MountDir ([string]$_.MountDir) -InstallMount $installMount -BootMount $bootMount
                })
            if ($still.Count -gt 0) {
                throw "stale mount recovery failed after Cleanup-Wim: $mountDir"
            }
            Remove-WinMintMountOwner -Kind $kind -ServicingRoot $root
            return [pscustomobject]@{ recoveryAction = 'cleanup-wim'; mountDirectory = $mountDir }
        }

        $after = @(Get-WinMintMountedImages -Commands $Commands)
        $stillMounted = @($after | Where-Object {
                [IO.Path]::GetFullPath([string]$_.MountDir).Equals([IO.Path]::GetFullPath($mountDir), [StringComparison]::OrdinalIgnoreCase)
            })
        if ($stillMounted.Count -gt 0) {
            throw "discard did not unmount $mountDir"
        }
        Remove-WinMintMountOwner -Kind $kind -ServicingRoot $root
        $recoveryAction = 'discard'
    }

    foreach ($kind in @('install', 'boot')) {
        $ownerPath = Get-WinMintMountOwnerPath -Kind $kind -ServicingRoot $root
        if (-not (Test-Path -LiteralPath $ownerPath)) { continue }
        $kindMount = Get-WinMintMountDirectory -Kind $kind -ServicingRoot $root
        $still = @((Get-WinMintMountedImages -Commands $Commands) | Where-Object {
                [IO.Path]::GetFullPath([string]$_.MountDir).Equals([IO.Path]::GetFullPath($kindMount), [StringComparison]::OrdinalIgnoreCase)
            })
        if ($still.Count -gt 0) { continue }
        Remove-WinMintMountOwner -Kind $kind -ServicingRoot $root
        if ($recoveryAction -eq 'none') { $recoveryAction = 'owner-cleanup' }
    }

    return [pscustomobject]@{ recoveryAction = $recoveryAction }
}

function Clear-WinMintOwnedMount {
    param(
        [string] $ServicingRoot,
        $Commands
    )
    $root = Get-WinMintServicingRoot -ServicingRoot $ServicingRoot
    foreach ($kind in @('install', 'boot')) {
        $mountDir = Get-WinMintMountDirectory -Kind $kind -ServicingRoot $root
        try {
            Invoke-WinMintUnmountDiscard -MountDir $mountDir -Commands $Commands
        }
        catch {
            Write-Debug "discard $mountDir : $_"
        }
        Remove-WinMintMountOwner -Kind $kind -ServicingRoot $root
    }
}

function Merge-WinMintPreparedMediaEvidence {
    param(
        [Parameter(Mandatory)] [hashtable] $Evidence,
        [Parameter(Mandatory)] [string] $WorkDirectory,
        [hashtable] $PhaseTimings,
        [string] $RecoveryAction = 'none'
    )
    $path = Join-Path $WorkDirectory 'prepared-media.json'
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $doc = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        foreach ($p in $doc.PSObject.Properties) {
            if ([string]$p.Name -eq 'mediaCache.previousMedia') { continue }
            $Evidence[[string]$p.Name] = $p.Value
        }
    }
    if ($PhaseTimings) {
        foreach ($key in $PhaseTimings.Keys) {
            $Evidence["timings.$key"] = [int]$PhaseTimings[$key]
        }
    }
    if (-not $Evidence.ContainsKey('mediaCache.recoveryAction')) {
        $Evidence['mediaCache.recoveryAction'] = $RecoveryAction
    }
    foreach ($name in @(
            'timings.sourceHashMs', 'timings.cacheValidateMs', 'timings.cachePrepareMs',
            'timings.runMediaCopyMs', 'timings.mountMs', 'timings.exportMs', 'timings.buildIsoMs')) {
        if ($Evidence.ContainsKey($name)) {
            $value = [int]$Evidence[$name]
            if ($value -lt 0) { throw "timing $name is negative" }
        }
    }
    return $Evidence
}
