#requires -Version 7.6
<#
.SYNOPSIS
  Prevent the failure mode that hit ~386 GB: stacked output ISOs + multiple full Apply/Smoke workdirs.
.NOTES
  Targets:
    - Flat output dirs (v1-style): keep N newest *.iso; age-purge media disks
    - .scratch (v2): keep N newest *heavy* child workdirs (media/out.iso/vhdx); drop the rest
  Do not run during Apply/Smoke. Never touches paths outside -Root.
#>
param(
    [string] $Root = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.scratch'),
    [int] $KeepIso = 2,
    [int] $KeepWorkDirs = 1,
    [int] $MaxAgeDays = 14,
    [switch] $Wipe,
    [switch] $WhatIf,
    [switch] $SelfCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-HeavyWorkDir {
    param([Parameter(Mandatory)][string] $Dir)
    if (Test-Path -LiteralPath (Join-Path $Dir 'out.iso')) { return $true }
    if (Test-Path -LiteralPath (Join-Path $Dir 'install.wim')) { return $true }
    if (Test-Path -LiteralPath (Join-Path $Dir 'media\sources\install.wim')) { return $true }
    $disks = @(Get-ChildItem -LiteralPath $Dir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '^\.(vhdx|avhdx)$' })
    return $disks.Count -gt 0
}

function Invoke-ArtifactHygiene {
    param(
        [Parameter(Mandatory)][string] $Root,
        [int] $KeepIso = 2,
        [int] $KeepWorkDirs = 1,
        [int] $MaxAgeDays = 14,
        [switch] $Wipe,
        [switch] $WhatIf
    )
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
    $stale = 0
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

    # Loose disks (flat output/, orphans after partial deletes).
    $media = @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '^\.(iso|wim|esd|vhdx|avhdx)$' })
    foreach ($f in @($media | Where-Object { $_.LastWriteTime -lt $cutoff })) {
        $stale++
        if ($WhatIf) { Write-Output "Would remove (age): $($f.FullName)" }
        else {
            Remove-Item -LiteralPath $f.FullName -Force
            Write-Output "Removed (age): $($f.FullName)"
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

    Write-Output "Hygiene ok root=$Root keepIso=$KeepIso keepWorkDirs=$KeepWorkDirs maxAgeDays=$MaxAgeDays workDrop=$workDrop stale=$stale retainDrop=$retainDrop"
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
        Invoke-ArtifactHygiene -Root $tmp -KeepIso 2 -KeepWorkDirs 9 -MaxAgeDays 365
        $left = @(Get-ChildItem -LiteralPath $tmp -Filter '*.iso' | Sort-Object Name)
        if ($left.Count -ne 2) { throw "iso retain: expected 2, got $($left.Count)" }

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

Invoke-ArtifactHygiene -Root $Root -KeepIso $KeepIso -KeepWorkDirs $KeepWorkDirs -MaxAgeDays $MaxAgeDays -Wipe:$Wipe -WhatIf:$WhatIf
