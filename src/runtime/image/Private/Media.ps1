#Requires -Version 7.6

function Dismount-Win11IsoDiskImageLiteral {
    <# <summary>Dismounts a mounted ISO (or other disk image) by file path so the virtual drive letter is released. Idempotent.</summary> #>
    param([string]$LiteralImagePath)
    if ([string]::IsNullOrWhiteSpace($LiteralImagePath)) { return }
    if (-not (Test-Path -LiteralPath $LiteralImagePath)) {
        Write-Verbose "Dismount-Win11IsoDiskImageLiteral: file not found, skip: $LiteralImagePath"
        return
    }
    $full = [IO.Path]::GetFullPath($LiteralImagePath)
    $attached = $false
    try {
        foreach ($di in @(Get-DiskImage -ImagePath $full -ErrorAction SilentlyContinue)) {
            if ($null -eq $di) { continue }
            if ($di.Attached) { $attached = $true; break }
        }
    }
    catch {
        Write-Verbose "Get-DiskImage '$full': $($_.Exception.Message)"
    }
    if (-not $attached) {
        Write-Verbose "Dismount-Win11IsoDiskImageLiteral: not attached, skip: $full"
        return
    }
    try {
        LogVerbose "Dismount-DiskImage: $full"
        $null = Dismount-DiskImage -ImagePath $full -ErrorAction Stop
    }
    catch {
        LogWarn "Dismount-DiskImage failed for '$full': $($_.Exception.Message)"
        try { $null = Dismount-DiskImage -ImagePath $full -ErrorAction SilentlyContinue } catch { Write-Verbose "Dismount-DiskImage retry: $($_.Exception.Message)" }
    }
}

function Push-Win11IsoAutoPlaySuppression {
    $states = [System.Collections.Generic.List[object]]::new()
    foreach ($key in @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    )) {
        $existed = Test-Path -LiteralPath $key
        if (-not $existed) { $null = New-Item -Path $key -Force -ErrorAction SilentlyContinue }
        $hadValue = $false
        $oldValue = $null
        try {
            $item = Get-Item -LiteralPath $key -ErrorAction Stop
            if ($item.Property -contains 'NoDriveTypeAutoRun') {
                $hadValue = $true
                $oldValue = (Get-ItemProperty -LiteralPath $key).NoDriveTypeAutoRun
            }
            $null = Set-ItemProperty -Path $key -Name 'NoDriveTypeAutoRun' -Value 255 -Type DWord -Force
            $states.Add([pscustomobject]@{ Key = $key; Existed = $existed; HadValue = $hadValue; Value = $oldValue })
        }
        catch {
            Write-Verbose "AutoPlay suppression skipped for ${key}: $($_.Exception.Message)"
        }
    }
    return $states.ToArray()
}

function Pop-Win11IsoAutoPlaySuppression {
    param([object[]]$State)
    foreach ($entry in @($State)) {
        try {
            if ($entry.HadValue) {
                $null = Set-ItemProperty -Path $entry.Key -Name 'NoDriveTypeAutoRun' -Value $entry.Value -Force
            }
            else {
                $null = Remove-ItemProperty -Path $entry.Key -Name 'NoDriveTypeAutoRun' -Force -ErrorAction SilentlyContinue
                if (-not $entry.Existed) {
                    $keyItem = Get-Item -LiteralPath $entry.Key -ErrorAction SilentlyContinue
                    if ($keyItem -and $keyItem.Property.Count -eq 0) {
                        $null = Remove-Item -LiteralPath $entry.Key -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
        catch {
            Write-Verbose "AutoPlay restore skipped for $($entry.Key): $($_.Exception.Message)"
        }
    }
}

function ConvertTo-WinMintComparablePath {
    param([Parameter(Mandatory)][string]$Path)
    try {
        return [IO.Path]::GetFullPath($Path).TrimEnd([char]'\', [char]'/')
    }
    catch {
        return $Path.TrimEnd([char]'\', [char]'/')
    }
}

function Test-WinMintComparablePathIsUnderRoot {
    <# <summary>True when Candidate is the root folder or a descendant of Root (case-insensitive).</summary> #>
    param(
        [Parameter(Mandatory)][string]$Candidate,
        [Parameter(Mandatory)][string]$Root
    )
    $c = ConvertTo-WinMintComparablePath -Path $Candidate
    $r = ConvertTo-WinMintComparablePath -Path $Root
    if ($c.Length -lt $r.Length) { return $false }
    if ($c.Equals($r, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    $sep = [IO.Path]::DirectorySeparatorChar
    return $c.StartsWith($r + $sep, [StringComparison]::OrdinalIgnoreCase)
}

function Test-WinMintMountedImagePath {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path,
        [object[]]$MountedImages
    )

    $images = if ($PSBoundParameters.ContainsKey('MountedImages')) {
        @($MountedImages)
    }
    else {
        try { @(Get-WindowsImage -Mounted -ErrorAction Stop) }
        catch { @() }
    }

    $target = ConvertTo-WinMintComparablePath -Path $Path
    foreach ($image in $images) {
        $status = if ($image.PSObject.Properties['MountStatus']) { [string]$image.MountStatus } else { '' }
        if ($status.Equals('Invalid', [StringComparison]::OrdinalIgnoreCase)) { continue }

        $candidate = $null
        foreach ($propertyName in @('MountPath', 'Path')) {
            if ($image.PSObject.Properties[$propertyName]) {
                $candidate = [string]$image.$propertyName
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if ((ConvertTo-WinMintComparablePath -Path $candidate) -eq $target) { return $true }
    }
    return $false
}

function Invoke-Cleanup {
    param([string]$MountDir, [string]$SourceIso, [string]$WorkDir)
    # Must not use Invoke-Action here — Invoke-Action skips its scriptblock in DryRun mode,
    # but cleanup must always run (called from the outer finally block).
    Log 'Removing temp folders and dismounting images'
    LogVerbose "MountDir=$MountDir | SourceIso=$SourceIso | WorkDir=$WorkDir"
    if ($MountDir -and (Test-Path -LiteralPath $MountDir) -and (Test-WinMintMountedImagePath -Path $MountDir)) {
        try {
            $null = Dismount-WindowsImage -Path $MountDir -Discard -ErrorAction SilentlyContinue
        }
        catch {
            Write-Verbose "Dismount-WindowsImage (discard): $($_.Exception.Message)"
        }
    }
    foreach ($orphan in @(Get-ChildItem -LiteralPath (Get-Win11IsoProcessTempPath) -Filter 'Win11ISO_BootMount_*' -Directory -ErrorAction SilentlyContinue)) {
        try { $null = Dismount-WindowsImage -Path $orphan.FullName -Discard -ErrorAction SilentlyContinue } catch { Write-Verbose "Dismount orphan boot mount $($orphan.Name): $($_.Exception.Message)" }
        $null = Remove-Item -LiteralPath $orphan.FullName -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $orphan.FullName) {
            Write-Warning "Cleanup: boot mount '$($orphan.FullName)' could not be removed (WIM may still be locked). Remediate with: dism /cleanup-wim && Remove-Item '$($orphan.FullName)' -Recurse -Force"
        }
    }
    Dismount-Win11IsoDiskImageLiteral -LiteralImagePath $SourceIso
    if ($WorkDir -and (Test-Path $WorkDir)) { $null = Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}

function Invoke-Win11IsoStartupCleanup {
    # Sweep temp dirs left behind by builds that were aborted (window closed, crash, power loss).
    # Safe to call before the UI shows — runs synchronously but is instant when nothing is orphaned.
    $ProgressPreference = 'SilentlyContinue'
    $InformationPreference = 'SilentlyContinue'
    $temp = Get-Win11IsoProcessTempPath

    try { Import-Module Dism -ErrorAction SilentlyContinue | Out-Null } catch {}
    try { Import-Module Storage -ErrorAction SilentlyContinue | Out-Null } catch {}

    # Any mounted WIM whose mount path lives under %TEMP% (abnormal layouts, not only WinMint_ISO_*).
    try {
        foreach ($image in @(Get-WindowsImage -Mounted -ErrorAction SilentlyContinue)) {
            if ($null -eq $image) { continue }
            $mountPath = $null
            foreach ($propertyName in @('MountPath', 'Path')) {
                if ($image.PSObject.Properties[$propertyName]) {
                    $mountPath = [string]$image.$propertyName
                    break
                }
            }
            if ([string]::IsNullOrWhiteSpace($mountPath)) { continue }
            if (-not (Test-WinMintComparablePathIsUnderRoot -Candidate $mountPath -Root $temp)) { continue }
            try { $null = Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction SilentlyContinue } catch {}
        }
    }
    catch {
        Write-Verbose "Invoke-Win11IsoStartupCleanup WIM sweep: $($_.Exception.Message)"
    }

    # Disk images mounted from under %TEMP% only (never arbitrary user paths).
    try {
        foreach ($di in @(Get-DiskImage -ErrorAction SilentlyContinue)) {
            if ($null -eq $di) { continue }
            if (-not $di.Attached) { continue }
            $img = [string]$di.ImagePath
            if ([string]::IsNullOrWhiteSpace($img)) { continue }
            if (-not (Test-WinMintComparablePathIsUnderRoot -Candidate $img -Root $temp)) { continue }
            Dismount-Win11IsoDiskImageLiteral -LiteralImagePath $img
        }
    }
    catch {
        Write-Verbose "Invoke-Win11IsoStartupCleanup DiskImage sweep: $($_.Exception.Message)"
    }

    # Orphaned build work dirs — can be multi-GB
    foreach ($dir in @(Get-ChildItem -LiteralPath $temp -Filter 'WinMint_ISO_*' -Directory -ErrorAction SilentlyContinue)) {
        $mountPath = Join-Path $dir.FullName 'mount'
        if ((Test-Path -LiteralPath $mountPath) -and (Test-WinMintMountedImagePath -Path $mountPath)) {
            try { $null = Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction SilentlyContinue } catch {}
        }
        $null = Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $dir.FullName) {
            Write-Warning "Startup cleanup: '$($dir.FullName)' still locked — run 'dism /cleanup-wim' to release."
        }
    }

    # Orphaned boot WIM mount dirs
    foreach ($dir in @(Get-ChildItem -LiteralPath $temp -Filter 'Win11ISO_BootMount_*' -Directory -ErrorAction SilentlyContinue)) {
        try { $null = Dismount-WindowsImage -Path $dir.FullName -Discard -ErrorAction SilentlyContinue } catch {}
        $null = Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Orphaned expand/extract scratch dirs
    foreach ($pattern in 'pwsh7_expand_*', 'vivetool_expand_*', 'Win11ISO_Cascadia_ext_*') {
        foreach ($dir in @(Get-ChildItem -LiteralPath $temp -Filter $pattern -Directory -ErrorAction SilentlyContinue)) {
            $null = Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    try { Invoke-WinMintAllBuildCachesMaintenance } catch { Write-Verbose "Invoke-Win11IsoStartupCleanup build caches: $($_.Exception.Message)" }
}

