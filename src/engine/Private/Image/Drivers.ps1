#Requires -Version 7.3

function Invoke-DriverMsiAdministrativeInstall {
    <# <summary>msiexec /a administrative install; fails if the tree contains no .inf (DISM requirement).</summary> #>
    param(
        [Parameter(Mandatory)][string]$MsiPath,
        [Parameter(Mandatory)][string]$Destination
    )
    if (-not (Test-Path -LiteralPath $MsiPath)) { throw "Driver MSI not found: $MsiPath" }
    $null = New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop

    $oldPref = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $msiArgs = @('/a', "`"$MsiPath`"", '/qn', "TARGETDIR=`"$Destination`"")
        Log "Extracting driver MSI (this can take 1-3 minutes for Surface bundles)…"
        $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -PassThru -WindowStyle Hidden
        if ($null -eq $proc) { throw "msiexec failed to launch: $MsiPath" }
        # Cap at 10 minutes. A Surface driver MSI normally extracts in ~60-90s;
        # anything slower means msiexec is hung waiting on a network resource
        # or registry call. Kill rather than hang the build forever.
        if (-not $proc.WaitForExit(600 * 1000)) {
            try { $proc.Kill() } catch { }
            throw "msiexec administrative install timed out after 10 minutes: $MsiPath"
        }
        if ($proc.ExitCode -ne 0) {
            throw "msiexec administrative install failed (exit $($proc.ExitCode)): $MsiPath"
        }
    }
    finally {
        $PSNativeCommandUseErrorActionPreference = $oldPref
    }

    $infCount = (Get-ChildItem -LiteralPath $Destination -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($infCount -lt 1) {
        throw "Administrative install produced no .inf files under $Destination (MSI: $MsiPath)."
    }
    return [int]$infCount
}

function Expand-DriverMSI {
    param([ValidateNotNullOrEmpty()][string]$MsiPath, [ValidateNotNullOrEmpty()][string]$Destination)
    if (-not (Test-Path -LiteralPath $MsiPath)) { throw "Driver MSI not found: $MsiPath" }

    $cached = Get-WinMintDriverMsiSingleExtractCacheHit -MsiPath $MsiPath
    if ($null -ne $cached) {
        Log 'Restoring driver MSI extract from temp cache…'
        if (Test-Path -LiteralPath $Destination) {
            Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue
        }
        $null = New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop
        Invoke-RobocopyChecked -Source $cached -Dest $Destination -UserFacingMessage 'Copying cached driver MSI extract…'
        Clear-WinMintReadOnlyAttribute -Path $Destination
        return
    }

    Invoke-Action 'Extracting driver MSI for DISM' {
        LogVerbose "MSI: $MsiPath -> $Destination"
        $c = Invoke-DriverMsiAdministrativeInstall -MsiPath $MsiPath -Destination $Destination
        LogOK "Extracted $c .inf file(s) from the MSI."
    }
    Publish-WinMintDriverMsiSingleExtractCache -MsiPath $MsiPath -SourceDir $Destination
}

function Expand-WinMintDriverZip {
    param(
        [ValidateNotNullOrEmpty()][string]$ZipPath,
        [ValidateNotNullOrEmpty()][string]$Destination
    )
    if (-not (Test-Path -LiteralPath $ZipPath)) { throw "Driver ZIP not found: $ZipPath" }
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue
    }
    $null = New-Item -ItemType Directory -Path $Destination -Force
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $Destination -Force
    $infCount = (Get-ChildItem -LiteralPath $Destination -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($infCount -lt 1) {
        throw "Driver ZIP contains no .inf files after extraction: $ZipPath"
    }
    LogOK "Extracted driver ZIP ($infCount .inf file(s))."
}

function Test-Win11IsoDriverPayloadDirectory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $false }
    $payload = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.inf', '.msi', '.zip' } |
        Select-Object -First 1
    return $null -ne $payload
}

function Test-Win11IsoDriverPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer) { return (Test-Win11IsoDriverPayloadDirectory -Path $item.FullName) }
    return $item.Extension -in '.inf', '.msi', '.zip'
}

function Resolve-Win11IsoCustomDriverSource {
    param(
        [string]$Path,
        [Parameter(Mandatory)][string]$WorkDir,
        [switch]$DryRun
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.PSIsContainer) {
        if (-not (Test-Win11IsoDriverPayloadDirectory -Path $item.FullName)) {
            throw "Custom driver folder contains no .inf or .msi files: $($item.FullName)"
        }
        $infCount = (Get-ChildItem -LiteralPath $item.FullName -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($infCount -gt 0) {
            return [pscustomobject]@{ Source = $item.FullName; Label = 'Custom drivers (folder)'; Ready = $true }
        }
        if ($DryRun) {
            return [pscustomobject]@{ Source = $item.FullName; Label = 'Custom drivers (MSI in folder; expanded during full build)'; Ready = $false }
        }
        $dest = Join-Path $WorkDir 'custom_driver_msi'
        $msis = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -Filter '*.msi' -File -ErrorAction SilentlyContinue)
        $fingerprint = Get-WinMintDriverMsiSetFingerprint -MsiFiles $msis
        $cachedBundle = Get-WinMintDriverMsiBundleCacheHit -Fingerprint $fingerprint
        if ($null -ne $cachedBundle) {
            Log 'Restoring custom driver MSI folder extracts from temp cache…'
            $null = New-Item -ItemType Directory -Path $dest -Force
            Invoke-RobocopyChecked -Source $cachedBundle -Dest $dest -UserFacingMessage 'Copying cached custom driver MSI extracts…'
            Clear-WinMintReadOnlyAttribute -Path $dest
            return [pscustomobject]@{ Source = $dest; Label = 'Custom drivers (expanded MSI)'; Ready = $true }
        }
        $null = New-Item -ItemType Directory -Path $dest -Force
        foreach ($msi in $msis) {
            $safe = [IO.Path]::GetFileNameWithoutExtension($msi.Name) -creplace '[^\w\-\.]', '_'
            $sub = Join-Path $dest $safe
            $added = Invoke-DriverMsiAdministrativeInstall -MsiPath $msi.FullName -Destination $sub
            LogOK "Expanded $($msi.Name) ($added .inf file(s))."
        }
        Publish-WinMintDriverMsiBundleCache -Fingerprint $fingerprint -SourceParentDir $dest
        return [pscustomobject]@{ Source = $dest; Label = 'Custom drivers (expanded MSI)'; Ready = $true }
    }

    switch ($item.Extension.ToLowerInvariant()) {
        '.inf' {
            return [pscustomobject]@{ Source = $item.DirectoryName; Label = "Custom INF ($($item.Name))"; Ready = $true }
        }
        '.msi' {
            if ($DryRun) {
                return [pscustomobject]@{ Source = $item.FullName; Label = "Custom MSI ($($item.Name); expanded during full build)"; Ready = $false }
            }
            # Unique destination per MSI stem so a future call with a different MSI
            # file doesn't overwrite this one's expanded tree.
            $stem = [IO.Path]::GetFileNameWithoutExtension($item.Name) -creplace '[^\w\-\.]', '_'
            $dest = Join-Path $WorkDir ('custom_driver_msi_' + $stem)
            Expand-DriverMSI -MsiPath $item.FullName -Destination $dest
            return [pscustomobject]@{ Source = $dest; Label = "Custom MSI ($($item.Name))"; Ready = $true }
        }
        '.zip' {
            if ($DryRun) {
                return [pscustomobject]@{ Source = $item.FullName; Label = "Custom driver ZIP ($($item.Name); extracted during full build)"; Ready = $false }
            }
            $stem = [IO.Path]::GetFileNameWithoutExtension($item.Name) -creplace '[^\w\-\.]', '_'
            $dest = Join-Path $WorkDir ('custom_driver_zip_' + $stem)
            Expand-WinMintDriverZip -ZipPath $item.FullName -Destination $dest
            return [pscustomobject]@{ Source = $dest; Label = "Custom ZIP ($($item.Name))"; Ready = $true }
        }
        default {
            throw "Custom driver path must be a .inf file, .msi file, .zip file, or folder: $($item.FullName)"
        }
    }
}

function Export-WinMintHostDrivers {
    param([Parameter(Mandatory)][string]$Destination)

    $null = New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop
    $exported = $false
    if (Get-Command Export-WindowsDriver -ErrorAction SilentlyContinue) {
        try {
            Export-WindowsDriver -Online -Destination $Destination -ErrorAction Stop | Out-Null
            $exported = $true
        }
        catch {
            LogWarn "Export-WindowsDriver failed; falling back to pnputil /export-driver. $($_.Exception.Message)"
        }
    }

    if (-not $exported) {
        $pnputil = (Get-Command pnputil.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
        if (-not $pnputil) {
            throw 'Host driver export was requested, but neither Export-WindowsDriver nor pnputil.exe is available.'
        }

        $oldPref = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
        try {
            $out = & $pnputil /export-driver * "$Destination" 2>&1
            $code = $LASTEXITCODE
        }
        finally {
            $PSNativeCommandUseErrorActionPreference = $oldPref
        }
        if ($code -ne 0) {
            throw "pnputil host driver export failed (exit $code).`n$($out | Out-String)"
        }
    }

    $infCount = (Get-ChildItem -LiteralPath $Destination -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($infCount -lt 1) {
        throw "Host driver export produced no .inf files under $Destination."
    }
    LogOK "Host driver export produced $infCount .inf file(s)."
    return [int]$infCount
}

function Get-WinMintInfClassName {
    param([Parameter(Mandatory)][string]$InfPath)
    $line = Get-Content -LiteralPath $InfPath -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '^\s*Class\s*=\s*(.+?)\s*$' } |
        Select-Object -First 1
    if ($line -match '^\s*Class\s*=\s*(.+?)\s*$') {
        return $matches[1].Trim().Trim('"').ToLowerInvariant()
    }
    return ''
}

function Copy-WinMintSetupCriticalDrivers {
    param(
        [Parameter(Mandatory)][string]$DriverSource,
        [Parameter(Mandatory)][string]$Destination
    )

    $includeClasses = @(
        'hdc', 'scsiadapter', 'system', 'usb', 'usbdevice',
        'hidclass', 'keyboard', 'mouse', 'net', 'extension'
    )
    $excludeClasses = @(
        'display', 'media', 'camera', 'bluetooth', 'sensor',
        'softwarecomponent', 'printer', 'monitor'
    )
    $null = New-Item -ItemType Directory -Path $Destination -Force
    $copied = 0
    foreach ($inf in Get-ChildItem -LiteralPath $DriverSource -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue) {
        $class = Get-WinMintInfClassName -InfPath $inf.FullName
        if ([string]::IsNullOrWhiteSpace($class)) { continue }
        if ($excludeClasses -contains $class) { continue }
        if ($includeClasses -notcontains $class) { continue }
        $rel = $inf.DirectoryName.Substring((Get-Item -LiteralPath $DriverSource).FullName.Length).TrimStart([char[]]@('\', '/'))
        $targetDir = if ([string]::IsNullOrWhiteSpace($rel)) { $Destination } else { Join-Path $Destination $rel }
        $null = New-Item -ItemType Directory -Path $targetDir -Force
        Get-ChildItem -LiteralPath $inf.DirectoryName -Force -ErrorAction SilentlyContinue |
            Copy-Item -Destination $targetDir -Recurse -Force -ErrorAction SilentlyContinue
        $copied++
    }
    return $copied
}

function Invoke-DriverInjection {
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir,
        [ValidateNotNullOrEmpty()][string]$IsoContents,
        [ValidateNotNullOrEmpty()][string]$DriverSource,
        [string]$SourceLabel,
        [bool]$InjectWinPE = $true
    )
    Write-SectionHeader "Drivers: $SourceLabel"

    Invoke-Action 'Injecting drivers into Windows and WinPE (when boot.wim is present)' {
        LogVerbose "Driver folder: $DriverSource"
        $infCount = (Get-ChildItem -LiteralPath $DriverSource -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($infCount -lt 1) {
            LogWarn "No .inf files under the driver folder; skipping injection for this source."
            LogVerbose $DriverSource
            return
        }

        Log "Driver source contains $infCount .inf file(s)."
        Log "Adding drivers to the mounted Windows image from '$SourceLabel'…"
        $windowsTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-DismAddDriverToImage -ImageMountPath $MountDir -DriverSource $DriverSource
        $windowsTimer.Stop()
        LogOK "Windows image driver injection finished in $(Format-WinMintDuration -Duration $windowsTimer.Elapsed)."

        $bootWim = Join-Path $IsoContents 'sources\boot.wim'
        if (-not $InjectWinPE) {
            LogVerbose 'WinPE driver injection already completed for this source; skipping boot.wim.'
            return
        }
        if (Test-Path $bootWim) {
            $bootDriverSource = Join-Path (Get-Win11IsoProcessTempPath) "Win11ISO_BootDrivers_$(Get-Random)"
            try {
                $bootInfCount = Copy-WinMintSetupCriticalDrivers -DriverSource $DriverSource -Destination $bootDriverSource
                if ($bootInfCount -lt 1) {
                    LogWarn 'No setup-critical drivers were detected for WinPE; skipping boot.wim driver injection for this source.'
                    return
                }
                $bootIndexes = @($script:BootWimDriverMountIndexes)
                Log "Adding drivers to WinPE boot.wim index(es): $($bootIndexes -join ', ')…"
                $null = Set-ItemProperty -Path $bootWim -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                foreach ($idx in $bootIndexes) {
                    $bootTimer = [System.Diagnostics.Stopwatch]::StartNew()
                    $bootMount = Join-Path (Get-Win11IsoProcessTempPath) "Win11ISO_BootMount_$(Get-Random)"
                    $null = New-Item -Path $bootMount -ItemType Directory -Force
                    try {
                        Log "Mounting boot.wim index $idx for WinPE driver injection."
                        $null = Mount-WindowsImage -ImagePath $bootWim -Index $idx -Path $bootMount -ErrorAction Stop
                        Invoke-DismAddDriverToImage -ImageMountPath $bootMount -DriverSource $bootDriverSource
                        $null = Dismount-WindowsImage -Path $bootMount -Save -ErrorAction Stop
                        $bootTimer.Stop()
                        LogOK "boot.wim index $idx driver injection saved in $(Format-WinMintDuration -Duration $bootTimer.Elapsed)."
                    }
                    catch {
                        $bootTimer.Stop()
                        try { $null = Dismount-WindowsImage -Path $bootMount -Discard -ErrorAction SilentlyContinue } catch { Write-Verbose "WinPE driver boot mount discard: $($_.Exception.Message)" }
                        throw
                    }
                    finally {
                        $null = Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            finally {
                $null = Remove-Item -LiteralPath $bootDriverSource -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
