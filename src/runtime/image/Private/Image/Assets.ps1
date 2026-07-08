#Requires -Version 7.6

function Sync-NerdFont {
    param([ValidateNotNullOrEmpty()][string]$FontDir)
    function Invoke-WinMintNerdFontPackageSync {
        param(
            [Parameter(Mandatory)][string]$DisplayName,
            [Parameter(Mandatory)][string]$RepoSlug,
            [Parameter(Mandatory)][string]$AssetRegex,
            [Parameter(Mandatory)][string[]]$CachePatterns,
            [Parameter(Mandatory)][scriptblock]$GetCacheHit,
            [Parameter(Mandatory)][scriptblock]$RestoreFromCache,
            [Parameter(Mandatory)][scriptblock]$PublishCache,
            [Parameter(Mandatory)][string]$TempPrefix
        )

        Write-SectionHeader "Host: $DisplayName font sync"
        Invoke-Action "Downloading $DisplayName (Nerd Font) into .\assets\runtime\fonts if missing" {
            LogVerbose $FontDir
            $null = New-Item -Path $FontDir -ItemType Directory -Force
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            try {
                if (Get-ChildItem -LiteralPath $FontDir -Filter '*CascadiaCodeNF-Regular.ttf' -File -ErrorAction SilentlyContinue | Select-Object -First 1) {
                    LogOK 'Cascadia Code Nerd Font is already present.'
                    return
                }

                $cachedRoot = & $GetCacheHit
                if ($null -ne $cachedRoot) {
                    Log "Restoring $DisplayName Nerd Font from temp cache (skipping GitHub + zip extract)…"
                    & $RestoreFromCache -FontDir $FontDir -CacheRootDir $cachedRoot
                    LogOK "$DisplayName Nerd Font restored from temp cache."
                    return
                }
                $payload = Resolve-WinMintGitHubReleasePayload `
                    -Name "$DisplayName (Nerd Font)" `
                    -RepoSlug $RepoSlug `
                    -CachePatterns $CachePatterns `
                    -HashLabel $DisplayName `
                    -AssetSelector {
                        param($Asset, $Release)
                        [void]$Release
                        if ([string]$Asset.name -match $AssetRegex) { return 1 }
                        return 0
                    }
                $zipPath = [string]$payload.Path
                Add-WinMintManifestPayloadFact -Payload $payload
                $extRoot = Join-Path (Get-Win11IsoProcessTempPath) ($TempPrefix + [Guid]::NewGuid().ToString('n'))
                try {
                    $null = New-Item -ItemType Directory -Path $extRoot -Force
                    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extRoot)
                    Get-ChildItem -LiteralPath $extRoot -Recurse -File |
                        Where-Object { $_.Name -match 'NF.*\.(ttf|otf)$' } |
                        Copy-Item -Destination $FontDir -Force
                    & $PublishCache -FontDir $FontDir -TagName $payload.Version -AssetName $payload.AssetName `
                        -SourceUrl $payload.SourceUrl -Sha256 $payload.Sha256 -SizeBytes $payload.SizeBytes
                }
                finally {
                    Remove-WinMintPayloadResult -Payload $payload
                    Remove-Item -LiteralPath $extRoot -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            catch { LogWarn "$DisplayName sync failed: $_" }
        }
    }

    Invoke-WinMintNerdFontPackageSync `
        -DisplayName 'Cascadia Code' `
        -RepoSlug 'microsoft/cascadia-code' `
        -AssetRegex 'CascadiaCode-.*\.zip' `
        -CachePatterns @('CascadiaCode-*.zip') `
        -GetCacheHit { Get-WinMintCascadiaNerdFontCacheHit } `
        -RestoreFromCache {
            param($FontDir, $CacheRootDir)
            Restore-WinMintCascadiaNerdFontFromCache -FontDir $FontDir -CacheRootDir $CacheRootDir
        } `
        -PublishCache {
            param($FontDir, $TagName, $AssetName, $SourceUrl, $Sha256, $SizeBytes)
            Publish-WinMintCascadiaNerdFontCache `
                -FontDir $FontDir `
                -TagName $TagName `
                -AssetName $AssetName `
                -SourceUrl $SourceUrl `
                -Sha256 $Sha256 `
                -SizeBytes $SizeBytes
        } `
        -TempPrefix 'Win11ISO_Cascadia_ext_'
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
    Write-SectionHeader 'Image: fonts from .\assets\runtime\fonts'
    $fontDir = Join-Path $ScriptDir 'assets\runtime\fonts'
    if (-not (Test-Path $fontDir)) { return }
    $fonts = @(Get-ChildItem -LiteralPath $fontDir -Filter '*CascadiaCodeNF*' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.ttf', '.otf' })
    if ($fonts.Count -eq 0) {
        LogWarn "No Cascadia Code NF font files found under $fontDir; skipping offline font install."
        return
    }

    Invoke-Action "Installing $($fonts.Count) Cascadia Code NF font file(s) into the offline Windows image" {
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
    $cursorsDir = Join-Path $ScriptDir 'assets\runtime\cursors'
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

function Install-OfflineWindowsTerminalSettings {
    param([ValidateNotNullOrEmpty()][string]$MountDir, [ValidateNotNullOrEmpty()][string]$ScriptDir)
    Write-SectionHeader 'Image: Windows Terminal settings'
    Invoke-Action 'Installing the default Windows Terminal profile for PowerShell 7' {
        $settingsSrc = Join-Path $ScriptDir 'assets\runtime\windows-terminal\settings.json'
        if (-not (Test-Path -LiteralPath $settingsSrc)) {
            LogWarn "Windows Terminal settings asset missing: $settingsSrc"
            return
        }

        $settingsDir = Join-Path $MountDir 'Users\Default\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
        $null = New-Item -ItemType Directory -Path $settingsDir -Force -ErrorAction Stop
        Copy-Item -LiteralPath $settingsSrc -Destination (Join-Path $settingsDir 'settings.json') -Force
        LogOK 'Staged default Windows Terminal settings for PowerShell 7.'
    }
}

function Install-OfflineWinget {
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir,
        [Parameter(Mandatory)][string]$TargetArch
    )
    Write-SectionHeader 'Image: winget (offline bundle)'
    Invoke-Action 'Provisioning winget with DISM (offline msixbundle)' {
        LogVerbose "Mount: $MountDir"
        $bundlePath = $null
        $dependencyZipPath = $null
        $bundlePayload = $null
        $dependencyPayload = $null
        $dependencyExpandDir = $null
        try {
            $wingetPayloads = Resolve-WinMintGitHubReleasePayloadSet `
                -RepoSlug 'microsoft/winget-cli' `
                -PayloadSpecs @(
                    [ordered]@{
                        Name = 'winget'
                        AssetSelector = { param($Asset, $Release) [void]$Release; if ([string]$Asset.name -match '\.msixbundle$') { 1 } else { 0 } }
                        CachePatterns = @('Microsoft.DesktopAppInstaller_*.msixbundle', '*.msixbundle')
                        HashLabel = 'winget'
                    }
                    [ordered]@{
                        Name = 'winget dependencies'
                        AssetSelector = { param($Asset, $Release) [void]$Release; if ([string]$Asset.name -eq 'DesktopAppInstaller_Dependencies.zip') { 1 } else { 0 } }
                        CachePatterns = @('DesktopAppInstaller_Dependencies.zip')
                        HashLabel = 'winget dependencies'
                    }
                )

            $bundlePayload = $wingetPayloads | Where-Object { [string]$_.Name -eq 'winget' } | Select-Object -First 1
            $dependencyPayload = $wingetPayloads | Where-Object { [string]$_.Name -eq 'winget dependencies' } | Select-Object -First 1
            if (-not $bundlePayload -or -not $dependencyPayload) {
                throw 'winget payload store did not return both required payloads.'
            }
            $bundlePath = [string]$bundlePayload.Path
            $dependencyZipPath = [string]$dependencyPayload.Path
            Add-WinMintManifestPayloadFact -Payload $bundlePayload
            Add-WinMintManifestPayloadFact -Payload $dependencyPayload

            $dependencyExpandDir = Join-Path (Get-Win11IsoProcessTempPath) ('winget_dependencies_' + [Guid]::NewGuid().ToString('n'))
            Expand-Archive -LiteralPath $dependencyZipPath -DestinationPath $dependencyExpandDir -Force
            $dependencyArch = switch ($TargetArch) {
                'arm64' { 'arm64' }
                'amd64' { 'x64' }
                'x64' { 'x64' }
                'x86' { 'x86' }
                default { throw "Unsupported winget dependency architecture '$TargetArch'." }
            }
            $dependencyPackages = @(
                Get-ChildItem -LiteralPath (Join-Path $dependencyExpandDir $dependencyArch) -File -ErrorAction Stop |
                    Where-Object { $_.Extension -in @('.appx', '.msix') } |
                    Sort-Object Name |
                    ForEach-Object { $_.FullName }
            )
            if ($dependencyPackages.Count -eq 0) {
                throw "winget dependency archive contains no $dependencyArch dependency packages."
            }

            $dismArgs = @('/English', "/Image:$MountDir", '/Add-ProvisionedAppxPackage', "/PackagePath:$bundlePath")
            foreach ($dependencyPackage in $dependencyPackages) {
                $dismArgs += "/DependencyPackagePath:$dependencyPackage"
            }
            $dismArgs += '/SkipLicense'
            Invoke-DismExe -Arguments $dismArgs | Out-Null
        }
        catch { LogWarn "Winget pre-provisioning failed: $_" }
        finally {
            Remove-WinMintPayloadResult -Payload $bundlePayload
            Remove-WinMintPayloadResult -Payload $dependencyPayload
            if ($dependencyExpandDir -and (Test-Path -LiteralPath $dependencyExpandDir)) {
                Remove-Item -LiteralPath $dependencyExpandDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

