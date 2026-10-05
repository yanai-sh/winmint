#requires -Version 7.6
<#
.SYNOPSIS
  Prevent the failure mode that hit ~386 GB: stacked output ISOs + multiple full Apply/Smoke workdirs.
.NOTES
  Targets:
    - Flat output dirs (v1-style): keep N newest *.iso (default 1 — timestamped Apply must not stack)
    - .scratch (v2): keep N newest *heavy* child workdirs (media/out.iso/vhdx); drop the rest
    - Nested media.previous-* / media.incoming-* under a kept workdir
  Do not age-purge WIM/ISO bytes by LastWriteTime (Source ISO timestamps survive copy).
  After just smoke / host-apply / Cli build: -SkipIfBusy (skip if dism.exe or the ImageServicing mutex is held).
  Apply/Smoke also Clear-WinMintPriorOutputIsos at start (ISO trim does not need the servicing lock).
  Never touches paths outside -Root.
#>
param(
    [string] $Root = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.scratch'),
    [int] $KeepIso = 1,
    [int] $KeepWorkDirs = 1,
    [int] $MaxAgeDays = 14,
    [switch] $Wipe,
    [switch] $WhatIf,
    [switch] $SkipIfBusy,
    [switch] $NoRun,
    [switch] $SelfCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Same name as servicing/Resolve-WinMintMount.ps1 — probe only, do not hold.
$script:WinMintImageServicingMutexName = 'Global\WinMint.ImageServicing.v1'

function Test-WinMintImageServicingBusy {
    if (@(Get-Process -Name dism -ErrorAction SilentlyContinue).Count -gt 0) { return $true }
    $mutex = $null
    try {
        $mutex = [System.Threading.Mutex]::new($false, $script:WinMintImageServicingMutexName)
        try {
            if ($mutex.WaitOne(0)) {
                [void]$mutex.ReleaseMutex()
                return $false
            }
            return $true
        }
        catch [System.Threading.AbandonedMutexException] {
            try { [void]$mutex.ReleaseMutex() } catch {
                Write-Debug "ReleaseMutex: $_"
            }
            return $false
        }
    }
    catch {
        return $true
    }
    finally {
        if ($null -ne $mutex) { $mutex.Dispose() }
    }
}

function Test-HeavyWorkDir {
    param([Parameter(Mandatory)][string] $Dir)
    if (Test-Path -LiteralPath (Join-Path $Dir 'out.iso')) { return $true }
    if (@(Get-ChildItem -LiteralPath $Dir -Filter 'winmint_*.iso' -File -ErrorAction SilentlyContinue).Count -gt 0) { return $true }
    if (Test-Path -LiteralPath (Join-Path $Dir 'install.wim')) { return $true }
    if (Test-Path -LiteralPath (Join-Path $Dir 'media\sources\install.wim')) { return $true }
    $disks = @(Get-ChildItem -LiteralPath $Dir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '^\.(vhdx|avhdx)$' })
    return $disks.Count -gt 0
}

function Invoke-ArtifactHygiene {
    param(
        [Parameter(Mandatory)][string] $Root,
        [int] $KeepIso = 1,
        [int] $KeepWorkDirs = 1,
        [int] $MaxAgeDays = 14,
        [switch] $Wipe,
        [switch] $WhatIf,
        [switch] $SkipIfBusy
    )
    if ($SkipIfBusy -and (Test-WinMintImageServicingBusy)) {
        Write-Output "Hygiene skipped: servicing busy root=$Root"
        return
    }
    if ($KeepIso -lt 0) { throw 'KeepIso must be >= 0' }
    if ($KeepWorkDirs -lt 0) { throw 'KeepWorkDirs must be >= 0' }
    if ($MaxAgeDays -lt 0) { throw 'MaxAgeDays must be >= 0' }
    if (-not (Test-Path -LiteralPath $Root)) {
        Write-Output "Root missing (nothing to clean): $Root"
        return
    }

    if ($Wipe) {
        $kids = @(Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue)
        foreach ($k in $kids) {
            if ($WhatIf) { Write-Output "Would wipe: $($k.FullName)" }
            else {
                Remove-Item -LiteralPath $k.FullName -Recurse -Force
                Write-Output "Wiped: $($k.FullName)"
            }
        }
        Write-Output "Hygiene wipe ok root=$Root removed=$($kids.Count)"
        return
    }

    $cutoff = (Get-Date).AddDays(-$MaxAgeDays)
    $workDrop = 0
    $sideDrop = 0
    $retainDrop = 0

    # v2 failure mode: smoke/ + work/ + apply-full/ each hold a full media tree + ISO + VHDX.
    $heavy = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-HeavyWorkDir -Dir $_.FullName } |
        Sort-Object LastWriteTime -Descending)
    foreach ($d in @($heavy | Select-Object -Skip $KeepWorkDirs)) {
        $workDrop++
        if ($WhatIf) { Write-Output "Would remove (workdir retain>$KeepWorkDirs): $($d.FullName)" }
        else {
            Remove-Item -LiteralPath $d.FullName -Recurse -Force
            Write-Output "Removed (workdir): $($d.FullName)"
        }
    }
    foreach ($d in @($heavy | Select-Object -First $KeepWorkDirs)) {
        if ($d.LastWriteTime -lt $cutoff) {
            $workDrop++
            if ($WhatIf) { Write-Output "Would remove (workdir age): $($d.FullName)" }
            else {
                Remove-Item -LiteralPath $d.FullName -Recurse -Force
                Write-Output "Removed (workdir age): $($d.FullName)"
            }
        }
    }

    # Failed-retry leftovers inside a kept workdir. Current media/ stays.
    $side = @(Get-ChildItem -LiteralPath $Root -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'media.previous-*' -or $_.Name -like 'media.incoming-*' })
    foreach ($d in $side) {
        $sideDrop++
        if ($WhatIf) { Write-Output "Would remove (side media): $($d.FullName)" }
        else {
            Remove-Item -LiteralPath $d.FullName -Recurse -Force
            Write-Output "Removed (side media): $($d.FullName)"
        }
    }

    # v1 failure mode: output\WinMint-*.iso stacked indefinitely.
    $isos = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.iso' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    foreach ($f in @($isos | Select-Object -Skip $KeepIso)) {
        $retainDrop++
        if ($WhatIf) { Write-Output "Would remove (iso retain>$KeepIso): $($f.FullName)" }
        else {
            Remove-Item -LiteralPath $f.FullName -Force
            Write-Output "Removed (iso retain): $($f.FullName)"
        }
    }

    Write-Output "Hygiene ok root=$Root keepIso=$KeepIso keepWorkDirs=$KeepWorkDirs maxAgeDays=$MaxAgeDays workDrop=$workDrop sideDrop=$sideDrop retainDrop=$retainDrop"
}

if ($SelfCheck) {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("winmint-hygiene-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        # Flat ISO retain (v1 output/)
        foreach ($i in 1..4) {
            $p = Join-Path $tmp "out-$i.iso"
            Set-Content -LiteralPath $p -Value $i
            (Get-Item -LiteralPath $p).LastWriteTime = (Get-Date).AddDays(-$i)
        }
        Invoke-ArtifactHygiene -Root $tmp -KeepIso 1 -KeepWorkDirs 9 -MaxAgeDays 365
        $left = @(Get-ChildItem -LiteralPath $tmp -Filter '*.iso' | Sort-Object Name)
        if ($left.Count -ne 1) { throw "iso retain: expected 1, got $($left.Count)" }

        # Heavy workdirs (v2 .scratch/)
        foreach ($name in @('smoke', 'work', 'apply-full')) {
            $d = Join-Path $tmp $name
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            Set-Content -LiteralPath (Join-Path $d 'out.iso') -Value $name
            (Get-Item -LiteralPath $d).LastWriteTime = (Get-Date).AddHours(-$(switch ($name) { 'smoke' { 1 } 'work' { 2 } default { 3 } }))
        }
        Invoke-ArtifactHygiene -Root $tmp -KeepIso 9 -KeepWorkDirs 1 -MaxAgeDays 365
        $dirs = @(Get-ChildItem -LiteralPath $tmp -Directory | Sort-Object Name)
        if ($dirs.Count -ne 1 -or $dirs[0].Name -ne 'smoke') {
            throw "workdir retain: expected only smoke; got $($dirs.Name -join ',')"
        }

        # Nested previous/incoming under the kept workdir; ISO-original boot.wim mtime is not a purge signal.
        Remove-Item -LiteralPath $tmp -Recurse -Force
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $smoke = Join-Path $tmp 'smoke'
        New-Item -ItemType Directory -Force -Path (Join-Path $smoke 'media\sources') | Out-Null
        $boot = Join-Path $smoke 'media\sources\boot.wim'
        Set-Content -LiteralPath $boot -Value 'boot'
        (Get-Item -LiteralPath $boot).LastWriteTime = (Get-Date).AddDays(-120)
        Set-Content -LiteralPath (Join-Path $smoke 'out.iso') -Value 'iso'
        $prev = Join-Path $smoke 'media.previous-old'
        New-Item -ItemType Directory -Force -Path $prev | Out-Null
        Set-Content -LiteralPath (Join-Path $prev 'install.wim') -Value 'old'
        $incoming = Join-Path $smoke 'media.incoming-crash'
        New-Item -ItemType Directory -Force -Path $incoming | Out-Null
        Set-Content -LiteralPath (Join-Path $incoming 'install.wim') -Value 'inc'
        Set-Content -LiteralPath (Join-Path $tmp 'sl7.password') -Value 'x' -NoNewline
        $stale = Join-Path $tmp 'warm-media-acceptance'
        New-Item -ItemType Directory -Force -Path $stale | Out-Null
        Set-Content -LiteralPath (Join-Path $stale 'out.iso') -Value 'stale'
        (Get-Item -LiteralPath $stale).LastWriteTime = (Get-Date).AddHours(-3)
        (Get-Item -LiteralPath $smoke).LastWriteTime = (Get-Date).AddHours(-1)
        Invoke-ArtifactHygiene -Root $tmp -KeepIso 1 -KeepWorkDirs 1 -MaxAgeDays 14
        if (-not (Test-Path -LiteralPath $boot)) { throw 'live boot.wim was age-purged' }
        if (Test-Path -LiteralPath $prev) { throw 'nested media.previous-* survived' }
        if (Test-Path -LiteralPath $incoming) { throw 'nested media.incoming-* survived' }
        if (Test-Path -LiteralPath $stale) { throw 'extra heavy workdir survived' }
        if (-not (Test-Path -LiteralPath (Join-Path $tmp 'sl7.password'))) { throw 'password file was removed' }
        if (-not (Test-Path -LiteralPath $smoke)) { throw 'kept workdir was removed' }

        # SkipIfBusy: another process holding the servicing mutex must not delete.
        Remove-Item -LiteralPath $tmp -Recurse -Force
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $busyDir = Join-Path $tmp 'warm-media-acceptance'
        New-Item -ItemType Directory -Force -Path $busyDir | Out-Null
        Set-Content -LiteralPath (Join-Path $busyDir 'out.iso') -Value 'stale'
        $holder = Start-Process -FilePath 'pwsh' -PassThru -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-Command',
            '$m = [System.Threading.Mutex]::new($true, ''Global\WinMint.ImageServicing.v1''); Start-Sleep -Seconds 60'
        )
        try {
            Start-Sleep -Milliseconds 800
            Invoke-ArtifactHygiene -Root $tmp -KeepIso 0 -KeepWorkDirs 0 -MaxAgeDays 0 -SkipIfBusy
            if (-not (Test-Path -LiteralPath (Join-Path $busyDir 'out.iso'))) {
                throw 'SkipIfBusy deleted while servicing mutex was held'
            }
        }
        finally {
            Stop-Process -Id $holder.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 200
        }

        # Wipe
        Invoke-ArtifactHygiene -Root $tmp -Wipe
        $after = @(Get-ChildItem -LiteralPath $tmp -Force)
        if ($after.Count -ne 0) { throw "wipe left $($after.Count) items" }

        Write-Output 'SelfCheck ok'
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    exit 0
}

function Invoke-WinMintScratchHygiene {
    param([Parameter(Mandatory)][string] $RepoRoot)
    try {
        Invoke-ArtifactHygiene -Root (Join-Path $RepoRoot '.scratch') -KeepIso 1 -KeepWorkDirs 1 -MaxAgeDays 14 -SkipIfBusy
    }
    catch {
        Write-Warning "scratch hygiene: $($_.Exception.Message)"
    }
}

if (-not $NoRun) {
    Invoke-ArtifactHygiene -Root $Root -KeepIso $KeepIso -KeepWorkDirs $KeepWorkDirs -MaxAgeDays $MaxAgeDays -Wipe:$Wipe -WhatIf:$WhatIf -SkipIfBusy:$SkipIfBusy
}
