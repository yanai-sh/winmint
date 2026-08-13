#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'servicing/Resolve-WinMintMount.ps1')

$root = Join-Path ([IO.Path]::GetTempPath()) ('winmint-mount-recovery-' + [guid]::NewGuid().ToString('N'))
$servicingRoot = Join-Path $root 'servicing'
$installMount = Join-Path $servicingRoot 'mount'
$bootMount = Join-Path $servicingRoot 'boot-mount'
$ownerRoot = Join-Path $servicingRoot 'mount-owners'
$cacheRoot = Join-Path $servicingRoot 'media-cache'
$workDirectory = Join-Path $root 'work'
$unrelatedMount = Join-Path $root 'other-mount'
$cacheWim = Join-Path $cacheRoot 'v1\abc\index-3\media\sources\install.wim'

function Assert-True($Value, [string] $Message) {
    if (-not $Value) { throw $Message }
}
function Assert-False($Value, [string] $Message) {
    if ($Value) { throw $Message }
}

function New-MountedImage {
    param([string] $MountDir, [string] $ImageFile, [string] $Status = 'Ok')
    [pscustomobject]@{
        MountDir  = $MountDir
        ImageFile = $ImageFile
        Status    = $Status
    }
}

function New-OwnerRecord {
    param(
        [string] $Kind,
        [int] $ProcessId = $PID,
        [string] $MountDirectory,
        [string] $ImageFile = (Join-Path $workDirectory 'media\sources\install.wim')
    )
    New-Item -ItemType Directory -Force -Path $ownerRoot | Out-Null
    $doc = @{
        schema          = 'winmint.mount-owner/v1'
        runId           = 'test-run'
        processId       = $ProcessId
        mountKind       = $Kind
        workDirectory   = $workDirectory
        mountDirectory  = $MountDirectory
        imageFile       = $ImageFile
        startedUtc      = '2026-08-13T00:00:00Z'
        sourceIsoSha256 = ('a' * 64)
        sourceIndex     = 3
    }
    $path = Join-Path $ownerRoot $(if ($Kind -eq 'boot') { 'boot.json' } else { 'install.json' })
    ($doc | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $path -Encoding utf8
    $path
}

try {
    New-Item -ItemType Directory -Force -Path $installMount, $bootMount, $ownerRoot, (Split-Path $cacheWim), $workDirectory, $unrelatedMount | Out-Null
    Set-Content -LiteralPath $cacheWim -Value 'CACHE-WIM' -Encoding utf8 -NoNewline

    $script:mounted = @()
    $script:discardCalls = [System.Collections.Generic.List[string]]::new()
    $script:cleanupCount = 0
    $script:queryCount = 0
    $script:discardFail = $null

    $commands = @{
        GetMountedImages = {
            $script:queryCount++
            @($script:mounted)
        }
        UnmountDiscard   = {
            param($MountDir)
            $script:discardCalls.Add([string]$MountDir)
            if ($script:discardFail -eq $MountDir) {
                $script:discardFail = $null
                throw 'stale/corrupt mount state'
            }
            $script:mounted = @($script:mounted | Where-Object { [string]$_.MountDir -cne [string]$MountDir })
        }
        CleanupWim       = {
            $script:cleanupCount++
        }
        TestProcessAlive = {
            param([int] $ProcessId)
            $ProcessId -eq $PID
        }
    }

    $ctx = @{
        ServicingRoot = $servicingRoot
        CacheRoot     = $cacheRoot
        Commands      = $commands
    }

    # second lock acquisition reports active servicing (named mutex is per-thread reentrant)
    $held = Enter-WinMintImageServicingLock
    try {
        $env:WINMINT_MOUNT_HELPER = Join-Path $repo 'servicing/Resolve-WinMintMount.ps1'
        $child = & pwsh -NoProfile -Command {
            . $env:WINMINT_MOUNT_HELPER
            try {
                Enter-WinMintImageServicingLock | Out-Null
                'acquired'
            }
            catch {
                if ($_.Exception.Message -match 'servicing already active') { 'blocked' } else { throw }
            }
        }
        Assert-True ($child -eq 'blocked') "second lock acquisition succeeded ($child)"
    }
    finally {
        Exit-WinMintImageServicingLock $held
        Remove-Item Env:WINMINT_MOUNT_HELPER -ErrorAction SilentlyContinue
    }

    # owner file with live PID fails without discard
    $script:mounted = @(New-MountedImage -MountDir $installMount -ImageFile (Join-Path $workDirectory 'media\sources\install.wim'))
    New-OwnerRecord -Kind 'install' -ProcessId $PID -MountDirectory $installMount | Out-Null
    $liveThrew = $false
    try {
        Resolve-WinMintStaleMount @ctx | Out-Null
    }
    catch {
        $liveThrew = $true
        if ([string]$_.Exception.Message -notmatch 'servicing already active') {
            throw "unexpected live-owner error: $($_.Exception.Message)"
        }
    }
    Assert-True $liveThrew 'live owner did not fail'
    Assert-True ($script:discardCalls.Count -eq 0) 'live owner discarded a mount'
    Assert-True (Test-Path -LiteralPath (Join-Path $ownerRoot 'install.json')) 'live owner file removed'

    # dead/missing owner plus owned mount discards and verifies
    $script:discardCalls.Clear()
    $script:mounted = @(New-MountedImage -MountDir $installMount -ImageFile (Join-Path $workDirectory 'media\sources\install.wim'))
    New-OwnerRecord -Kind 'install' -ProcessId 1 -MountDirectory $installMount | Out-Null
    $deadResult = Resolve-WinMintStaleMount @ctx
    Assert-True ($deadResult.recoveryAction -eq 'discard') "expected discard, got $($deadResult.recoveryAction)"
    Assert-True ($script:discardCalls.Count -eq 1 -and $script:discardCalls[0] -eq $installMount) 'dead owner did not discard owned mount'
    Assert-False (Test-Path -LiteralPath (Join-Path $ownerRoot 'install.json')) 'dead owner file remained after verified discard'
    Assert-True ($script:mounted.Count -eq 0) 'discard did not verify mount gone'

    $script:discardCalls.Clear()
    $script:mounted = @(New-MountedImage -MountDir $bootMount -ImageFile (Join-Path $workDirectory 'media\sources\boot.wim'))
    $missingResult = Resolve-WinMintStaleMount @ctx
    Assert-True ($missingResult.recoveryAction -eq 'discard') "missing owner expected discard, got $($missingResult.recoveryAction)"
    Assert-True ($script:discardCalls.Contains($bootMount)) 'missing owner did not discard boot mount'

    # discard stale-state failure triggers one Cleanup-Wim and re-query
    $script:discardCalls.Clear()
    $script:cleanupCount = 0
    $script:queryCount = 0
    $script:discardFail = $installMount
    $script:mounted = @(New-MountedImage -MountDir $installMount -ImageFile (Join-Path $workDirectory 'media\sources\install.wim'))
    New-OwnerRecord -Kind 'install' -ProcessId 1 -MountDirectory $installMount | Out-Null
    $cleanupThrew = $false
    try {
        Resolve-WinMintStaleMount @ctx | Out-Null
    }
    catch {
        $cleanupThrew = $true
    }
    Assert-True $cleanupThrew 'stale discard did not fail recovery'
    Assert-True ($script:cleanupCount -eq 1) "Cleanup-Wim count $($script:cleanupCount)"
    Assert-True ($script:queryCount -ge 2) "expected re-query after Cleanup-Wim, queries=$($script:queryCount)"
    Assert-True ($script:discardCalls.Count -eq 1) 'stale discard retried Unmount'

    # unrelated mount is never discarded
    $script:discardCalls.Clear()
    $script:mounted = @(New-MountedImage -MountDir $unrelatedMount -ImageFile (Join-Path $root 'foreign.wim'))
    $unrelated = Resolve-WinMintStaleMount @ctx
    Assert-True ($unrelated.recoveryAction -eq 'none' -or $unrelated.recoveryAction -eq 'owner-cleanup') "unrelated got $($unrelated.recoveryAction)"
    Assert-True ($script:discardCalls.Count -eq 0) 'unrelated mount was discarded'

    # cache WIM path is never discarded/mounted
    $script:discardCalls.Clear()
    $script:mounted = @(New-MountedImage -MountDir $unrelatedMount -ImageFile $cacheWim)
    $cacheMounted = $false
    try {
        Resolve-WinMintStaleMount @ctx | Out-Null
    }
    catch {
        $cacheMounted = [string]$_.Exception.Message -match 'Prepared media'
    }
    Assert-True $cacheMounted 'cache WIM mount was not rejected'
    Assert-True ($script:discardCalls.Count -eq 0) 'cache WIM path was discarded'

    # owner file is written immediately before mount; install/boot cannot overwrite each other
    $installOwner = Write-WinMintMountOwner -Kind install -ServicingRoot $servicingRoot -WorkDirectory $workDirectory -MountDirectory $installMount -ImageFile (Join-Path $workDirectory 'media\sources\install.wim') -SourceIsoSha256 ('a' * 64) -SourceIndex 3
    $bootOwner = Write-WinMintMountOwner -Kind boot -ServicingRoot $servicingRoot -WorkDirectory $workDirectory -MountDirectory $bootMount -ImageFile (Join-Path $workDirectory 'media\sources\boot.wim') -SourceIsoSha256 ('a' * 64) -SourceIndex 1
    Assert-True ((Split-Path $installOwner -Leaf) -eq 'install.json') 'install owner path'
    Assert-True ((Split-Path $bootOwner -Leaf) -eq 'boot.json') 'boot owner path'
    $installDoc = Get-Content -LiteralPath $installOwner -Raw | ConvertFrom-Json
    $bootDoc = Get-Content -LiteralPath $bootOwner -Raw | ConvertFrom-Json
    Assert-True ($installDoc.mountKind -eq 'install' -and $bootDoc.mountKind -eq 'boot') 'owner kinds mixed'
    Assert-True ($installDoc.processId -eq $PID) 'owner processId'
    Assert-True ((Test-Path -LiteralPath $installOwner) -and (Test-Path -LiteralPath $bootOwner)) 'one owner overwrote the other'

    # owner is removed only after successful unmount/discard
    Remove-WinMintMountOwner -Kind install -ServicingRoot $servicingRoot
    Assert-False (Test-Path -LiteralPath $installOwner) 'install owner remained'
    Assert-True (Test-Path -LiteralPath $bootOwner) 'boot owner removed by install cleanup'

    # no WinMint mount: stale owner file removed
    $script:mounted = @()
    New-OwnerRecord -Kind 'boot' -ProcessId 1 -MountDirectory $bootMount | Out-Null
    $staleOwner = Resolve-WinMintStaleMount @ctx
    Assert-True ($staleOwner.recoveryAction -eq 'owner-cleanup') "expected owner-cleanup, got $($staleOwner.recoveryAction)"
    Assert-False (Test-Path -LiteralPath (Join-Path $ownerRoot 'boot.json')) 'stale owner file remained'

    # failed recovery stops before Source ISO / Prepared media mutation (loop order)
    $plan = Get-Content -LiteralPath (Join-Path $repo 'servicing/Invoke-ServicingPlan.ps1') -Raw
    $lockAt = $plan.IndexOf('Enter-WinMintImageServicingLock')
    $resolveAt = $plan.IndexOf('Resolve-WinMintStaleMount')
    $stageAt = $plan.IndexOf('Resolve-KernelScript -Opcode')
    Assert-True ($lockAt -ge 0 -and $resolveAt -ge 0 -and $stageAt -ge 0) 'elevated loop missing lock/recovery'
    Assert-True ($lockAt -lt $resolveAt -and $resolveAt -lt $stageAt) 'recovery is not before Source ISO / stage mutation'

    $mountKernel = Get-Content -LiteralPath (Join-Path $repo 'servicing/Mount-InstallWim.ps1') -Raw
    $writeAt = $mountKernel.IndexOf('Write-WinMintMountOwner')
    $dismAt = $mountKernel.IndexOf('/Mount-Image')
    Assert-True ($writeAt -ge 0 -and $writeAt -lt $dismAt) 'install owner is not written immediately before mount'

    $exportKernel = Get-Content -LiteralPath (Join-Path $repo 'servicing/Export-Wim.ps1') -Raw
    $unmountAt = $exportKernel.IndexOf('/Unmount-Image')
    $removeAt = $exportKernel.IndexOf('Remove-WinMintMountOwner')
    Assert-True ($unmountAt -ge 0 -and $removeAt -gt $unmountAt) 'install owner is not removed after unmount'

    $bootKernel = Get-Content -LiteralPath (Join-Path $repo 'servicing/Patch-BootWimApply.ps1') -Raw
    Assert-True ($bootKernel.Contains('Write-WinMintMountOwner')) 'boot owner not written before mount'
    Assert-True ($bootKernel.Contains('Remove-WinMintMountOwner')) 'boot owner not removed after unmount'

    $workEvidence = Join-Path $root 'evidence-work'
    New-Item -ItemType Directory -Force -Path $workEvidence | Out-Null
    $sidecar = Join-Path $workEvidence 'prepared-media.json'
    @{
        'source.isoSha256'            = ('a' * 64)
        'source.isoLength'            = 10
        'source.index'                = 3
        'mediaCache.schema'           = 1
        'mediaCache.key'              = 'v1\aaa\index-3'
        'mediaCache.entryPath'        = 'C:\prepared'
        'mediaCache.outcome'          = 'hit'
        'mediaCache.installWimSha256' = ('b' * 64)
        'mediaCache.bootWimSha256'    = ('c' * 64)
        'mediaCache.copyMode'         = 'copy'
        'mediaCache.recoveryAction'   = 'discard'
        'mediaCache.previousMedia'    = (Join-Path $workEvidence 'media.previous-x')
        'timings.sourceHashMs'        = 1
        'timings.cacheValidateMs'     = 2
        'timings.cachePrepareMs'      = 3
        'timings.runMediaCopyMs'      = 4
        'timings.mountMs'             = 5
    } | ConvertTo-Json | Set-Content -LiteralPath $sidecar -Encoding utf8
    $merged = Merge-WinMintPreparedMediaEvidence -Evidence @{ schemaVersion = 'winmint.image.evidence/v1' } -WorkDirectory $workEvidence -PhaseTimings @{ exportMs = 6; buildIsoMs = 7 } -RecoveryAction 'none'
    foreach ($name in @(
            'source.isoSha256', 'source.isoLength', 'source.index',
            'mediaCache.schema', 'mediaCache.key', 'mediaCache.entryPath', 'mediaCache.outcome',
            'mediaCache.installWimSha256', 'mediaCache.bootWimSha256', 'mediaCache.copyMode',
            'mediaCache.recoveryAction',
            'timings.sourceHashMs', 'timings.cacheValidateMs', 'timings.cachePrepareMs',
            'timings.runMediaCopyMs', 'timings.mountMs', 'timings.exportMs', 'timings.buildIsoMs')) {
        Assert-True ($merged.ContainsKey($name)) "merged evidence missing $name"
    }
    Assert-False ($merged.ContainsKey('mediaCache.previousMedia')) 'previous media path leaked into evidence'
    Assert-True ([int]$merged['timings.exportMs'] -eq 6 -and [int]$merged['timings.buildIsoMs'] -eq 7) 'phase timings not merged'
    Assert-True ([string]$merged['mediaCache.recoveryAction'] -eq 'discard') 'recovery overwritten'

    Write-Output 'Test-WinMintMountRecovery ok'
}
finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
