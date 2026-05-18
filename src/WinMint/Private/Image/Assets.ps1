#Requires -Version 7.3

function Sync-NerdFont {
    param([ValidateNotNullOrEmpty()][string]$FontDir)
    Write-SectionHeader 'Host: Cascadia font sync'
    Invoke-Action 'Downloading Cascadia Code (Nerd Font) into .\assets\fonts if missing' {
        LogVerbose $FontDir
        $null = New-Item -Path $FontDir -ItemType Directory -Force
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        try {
            if (Get-ChildItem -LiteralPath $FontDir -Filter '*CascadiaCodeNF-Regular.ttf' -File -ErrorAction SilentlyContinue | Select-Object -First 1) {
                LogOK 'Cascadia Code Nerd Font is already present.'
                return
            }
            $cachedRoot = Get-WinMintCascadiaNerdFontCacheHit
            if ($null -ne $cachedRoot) {
                Log 'Restoring Cascadia Code Nerd Font from temp cache (skipping GitHub + zip extract)…'
                Restore-WinMintCascadiaNerdFontFromCache -FontDir $FontDir -CacheRootDir $cachedRoot
                LogOK 'Cascadia Code Nerd Font restored from temp cache.'
                return
            }
            $cascRel = Invoke-RestMethod -Verbose:$false -Uri 'https://api.github.com/repos/microsoft/cascadia-code/releases/latest'
            $cascAsset = $cascRel.assets | Where-Object name -match 'CascadiaCode-.*\.zip' | Select-Object -First 1
            if (-not $cascAsset) {
                $available = ($cascRel.assets | ForEach-Object { $_.name }) -join ', '
                LogWarn "Cascadia Code: no .zip asset matching 'CascadiaCode-*.zip' in latest release. Available: $available"
                return
            }
            $cascZipUrl = $cascAsset.browser_download_url
            $cascZipPath = Invoke-WebRequestCachedFile -Uri $cascZipUrl -CacheFileName $cascAsset.name
            $cascHash = Assert-Win11IsoFileHash -FilePath $cascZipPath -Label 'Cascadia Code'
            Add-WinMintManifestPayload -Name 'Cascadia Code (Nerd Font)' -SourceUrl $cascZipUrl `
                -Version $cascRel.tag_name -Sha256 $cascHash -SizeBytes (Get-Item -LiteralPath $cascZipPath).Length
            $extRoot = Join-Path (Get-Win11IsoProcessTempPath) ('Win11ISO_Cascadia_ext_' + [Guid]::NewGuid().ToString('n'))
            try {
                $null = New-Item -ItemType Directory -Path $extRoot -Force
                [System.IO.Compression.ZipFile]::ExtractToDirectory($cascZipPath, $extRoot)
                Get-ChildItem -LiteralPath $extRoot -Recurse -Filter '*NF*.ttf' | Copy-Item -Destination $FontDir -Force
                Publish-WinMintCascadiaNerdFontCache -FontDir $FontDir -TagName $cascRel.tag_name -AssetName $cascAsset.name `
                    -SourceUrl $cascZipUrl -Sha256 $cascHash -SizeBytes (Get-Item -LiteralPath $cascZipPath).Length
            }
            finally {
                if (-not (Test-IsPathUnderWin11IsoDependencyCache $cascZipPath)) { Remove-Item -LiteralPath $cascZipPath -Force -ErrorAction SilentlyContinue }
                Remove-Item -LiteralPath $extRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        catch { LogWarn "Cascadia sync failed: $_" }
    }
}

function Sync-Cursor {
    param(
        [ValidateNotNullOrEmpty()][string]$CursorsDir,
        [string]$PackKind = 'Windows11Modern'
    )
    if ([string]::IsNullOrWhiteSpace($PackKind) -or $PackKind -eq 'None') {
        $PackKind = $script:Win11IsoDefaultCursorPackKind
    }
    if (-not $script:Win11IsoCursorPackCatalog.ContainsKey($PackKind)) {
        throw "Unsupported cursor pack '$PackKind'. WinMint uses Windows 11 Modern."
    }
    Write-SectionHeader 'Host: cursor theme'
    Invoke-Action "Checking bundled cursor pack ($PackKind)" {
        LogVerbose $CursorsDir
        $meta = $script:Win11IsoCursorPackCatalog[$PackKind]
        $srcDir = Join-Path $CursorsDir $meta.HostSourceDir
        $marker = Join-Path $CursorsDir $meta.MarkerRelPath
        if (-not (Test-Path -LiteralPath $marker)) {
            throw "Bundled cursor pack missing expected file: $marker"
        }
        $missingRequired = @(
            $script:Win11IsoCursorSchemeOrder |
                Where-Object { -not (Test-Path -LiteralPath (Resolve-WinMintCursorSourceFile -PackMeta $meta -SourceDir $srcDir -RoleFile $_)) }
        )
        if ($missingRequired.Count -gt 0) {
            throw "Bundled cursor pack '$PackKind' is missing required role file(s): $($missingRequired -join ', ')"
        }
        LogOK "Bundled Windows 11 Modern cursor pack is present."
    }
}

function Resolve-WinMintCursorSourceFile {
    param(
        [Parameter(Mandatory)][hashtable]$PackMeta,
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$RoleFile
    )

    $sourceFile = $RoleFile
    if ($PackMeta.ContainsKey('RoleFiles') -and $PackMeta.RoleFiles.ContainsKey($RoleFile)) {
        $sourceFile = [string]$PackMeta.RoleFiles[$RoleFile]
    }
    return Join-Path $SourceDir $sourceFile
}

function Install-OfflineFont {
    param([ValidateNotNullOrEmpty()][string]$MountDir, [ValidateNotNullOrEmpty()][string]$ScriptDir)
    Write-SectionHeader 'Image: fonts from .\assets\fonts'
    $fontDir = Join-Path $ScriptDir 'assets\fonts'
    if (-not (Test-Path $fontDir)) { return }
    $fonts = @(Get-ChildItem -LiteralPath $fontDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.ttf', '.otf' })
    if ($fonts.Count -eq 0) { return }

    Invoke-Action "Installing $($fonts.Count) font file(s) into the offline Windows image" {
        LogVerbose "Mount: $MountDir"
        $null = & reg.exe load 'HKLM\Win11ISO_FontSOFTWARE' (Join-Path $MountDir 'Windows\System32\config\SOFTWARE')
        try {
            foreach ($font in $fonts) {
                $null = Copy-Item -Path $font.FullName -Destination (Join-Path $MountDir 'Windows\Fonts') -Force
                $suffix = ($font.Extension -eq '.ttf') ? "(TrueType)" : "(OpenType)"
                $fontName = "$([IO.Path]::GetFileNameWithoutExtension($font.Name)) $suffix"
                $null = & reg.exe add "HKLM\Win11ISO_FontSOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" /v "$fontName" /t REG_SZ /d "$($font.Name)" /f
            }
        }
        finally {
            [GC]::Collect(); [GC]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds 500
            $null = & reg.exe unload 'HKLM\Win11ISO_FontSOFTWARE'
        }
    }
}

function Install-OfflineCursor {
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir,
        [ValidateNotNullOrEmpty()][string]$ScriptDir,
        [string]$CursorPackKind = 'Windows11Modern'
    )
    if ([string]::IsNullOrWhiteSpace($CursorPackKind) -or $CursorPackKind -eq 'None') {
        $CursorPackKind = $script:Win11IsoDefaultCursorPackKind
    }
    if (-not $script:Win11IsoCursorPackCatalog.ContainsKey($CursorPackKind)) {
        throw "Unsupported cursor pack '$CursorPackKind'. WinMint uses Windows 11 Modern."
    }
    Write-SectionHeader 'Image: default user cursor scheme'
    $cursorsDir = Join-Path $ScriptDir 'assets\cursors'
    $meta = $script:Win11IsoCursorPackCatalog[$CursorPackKind]
    $srcDir = Join-Path $cursorsDir $meta.HostSourceDir
    if (-not (Test-Path -LiteralPath $srcDir)) {
        throw "Bundled cursor pack '$CursorPackKind' folder missing: $srcDir"
    }
    $cursorFiles = @(
        @(Get-ChildItem -LiteralPath $srcDir -Filter '*.cur' -File -ErrorAction SilentlyContinue) +
        @(Get-ChildItem -LiteralPath $srcDir -Filter '*.ani' -File -ErrorAction SilentlyContinue)
    )
    if ($cursorFiles.Count -eq 0) {
        LogWarn "Cursor pack '$CursorPackKind': no .cur/.ani files in $srcDir"
        return
    }
    $missingRequired = @(
        $script:Win11IsoCursorSchemeOrder |
            Where-Object { -not (Test-Path -LiteralPath (Resolve-WinMintCursorSourceFile -PackMeta $meta -SourceDir $srcDir -RoleFile $_)) }
    )
    if ($missingRequired.Count -gt 0) {
        throw "Cursor pack '$CursorPackKind': missing required Windows cursor role file(s): $($missingRequired -join ', ')"
    }

    Invoke-Action "Installing cursor scheme ($CursorPackKind) for the default user profile" {
        LogVerbose "Mount: $MountDir"
        $winCursors = Join-Path $MountDir 'Windows\Cursors'
        $null = New-Item -Path $winCursors -ItemType Directory -Force

        $schemeName = [string]$meta.SchemeName
        $destSeg    = [string]$meta.DestSegment
        $destDir    = Join-Path $winCursors $destSeg
        $null = New-Item -Path $destDir -ItemType Directory -Force
        foreach ($roleFile in @($script:Win11IsoCursorSchemeOrder | Sort-Object -Unique)) {
            $sourcePath = Resolve-WinMintCursorSourceFile -PackMeta $meta -SourceDir $srcDir -RoleFile $roleFile
            if (Test-Path -LiteralPath $sourcePath) {
                Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $destDir $roleFile) -Force
            }
        }
        $base = "%SystemRoot%\Cursors\$destSeg"
        $order = $script:Win11IsoCursorSchemeOrder
        $regPairs = @($script:Win11IsoCursorRegistryPairs)

        $null = & reg.exe load 'HKLM\peNTUSER' (Join-Path $MountDir 'Users\Default\ntuser.dat')
        try {
            $schemesKey = 'HKLM\peNTUSER\Control Panel\Cursors\Schemes'
            $cursorsKey = 'HKLM\peNTUSER\Control Panel\Cursors'
            $schemeList = ($order | ForEach-Object { "$base\$_" }) -join ','
            $null = & reg.exe add "`"$schemesKey`"" /v "$schemeName" /t REG_EXPAND_SZ /d "$schemeList" /f
            $null = & reg.exe add "`"$cursorsKey`"" /ve /t REG_SZ /d "$schemeName" /f
            foreach ($p in $regPairs) {
                $null = & reg.exe add "`"$cursorsKey`"" /v "$($p.Name)" /t REG_EXPAND_SZ /d "$base\$($p.File)" /f
            }
        }
        finally {
            [GC]::Collect(); [GC]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds 500
            $null = & reg.exe unload 'HKLM\peNTUSER'
        }
        LogOK "Default user cursor scheme applied ($CursorPackKind)."
    }
}

function Install-OfflineWinget {
    param([ValidateNotNullOrEmpty()][string]$MountDir)
    Write-SectionHeader 'Image: winget (offline bundle)'
    Invoke-Action 'Provisioning winget with DISM (offline msixbundle)' {
        LogVerbose "Mount: $MountDir"
        $bundlePath = $null
        try {
            $sourceUrl = ''
            $version = 'cached'
            $assetName = ''
            try {
                $rel = Invoke-RestMethod -Verbose:$false -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
                $asset = $rel.assets | Where-Object { $_.name -match '\.msixbundle$' } | Select-Object -First 1
                if (-not $asset) { throw 'winget-cli: no .msixbundle asset in latest GitHub release.' }
                $bundlePath = Invoke-WebRequestCachedFile -Uri $asset.browser_download_url -CacheFileName $asset.name
                $sourceUrl = $asset.browser_download_url
                $version = $rel.tag_name
                $assetName = $asset.name
            }
            catch {
                LogWarn "winget release lookup failed; trying cached msixbundle. $($_.Exception.Message)"
                $bundlePath = Get-WinMintCachedDownloadFile -Patterns @('Microsoft.DesktopAppInstaller_*.msixbundle', '*.msixbundle')
                if (-not $bundlePath) { throw 'winget cache missing Microsoft.DesktopAppInstaller msixbundle.' }
                $assetName = [IO.Path]::GetFileName($bundlePath)
                $sourceUrl = "cache:$assetName"
            }
            $wingetHash = Assert-Win11IsoFileHash -FilePath $bundlePath -Label "winget ($assetName)"
            Add-WinMintManifestPayload -Name 'winget' -SourceUrl $sourceUrl `
                -Version $version -Sha256 $wingetHash -SizeBytes (Get-Item -LiteralPath $bundlePath).Length
            Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Add-ProvisionedAppxPackage', "/PackagePath:$bundlePath", '/SkipLicense') | Out-Null
        }
        catch { LogWarn "Winget pre-provisioning failed: $_" }
        finally {
            if ($bundlePath -and (Test-Path -LiteralPath $bundlePath) -and -not (Test-IsPathUnderWin11IsoDependencyCache $bundlePath)) {
                Remove-Item -LiteralPath $bundlePath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
