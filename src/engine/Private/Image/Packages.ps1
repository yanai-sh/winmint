#Requires -Version 7.3

function Copy-WinMintPayloadDirectoryChildren {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SourceDir,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$DestinationDir
    )

    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
        throw "Payload source directory not found: $SourceDir"
    }

    $null = New-Item -ItemType Directory -Path $DestinationDir -Force -ErrorAction Stop
    foreach ($item in @(Get-ChildItem -LiteralPath $SourceDir -Force -ErrorAction Stop)) {
        Copy-Item -LiteralPath $item.FullName -Destination $DestinationDir -Recurse -Force -ErrorAction Stop
    }
}

function Install-OfflinePowerShell7 {
    <# <summary>Extract GitHub PowerShell release zip into the offline image so specialize / SetupComplete / FirstLogon can run pwsh.exe.</summary> #>
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir,
        [Parameter(Mandatory)][string]$TargetArch
    )
    Write-SectionHeader 'Image: PowerShell 7'
    Invoke-Action 'Installing PowerShell 7 into the offline image (pwsh for setup scripts)' {
        LogVerbose "Mount: $MountDir | arch: $TargetArch"
        $zip = $null
        $expand = $null
        try {
            $suffix = switch ($TargetArch) {
                'arm64' { 'win-arm64' }
                'x86' { 'win-x86' }
                default { 'win-x64' }
            }
            $assetName = ''
            $sourceUrl = ''
            $version = 'cached'
            try {
                # Always fetches latest PowerShell 7. To pin a specific version: replace /releases/latest with /releases/tags/v7.x.y
                $rel = Invoke-RestMethod -Verbose:$false -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -Headers @{ 'User-Agent' = 'WinMint/1.0' }
                $asset = @($rel.assets | Where-Object { $_.name -match ('PowerShell-\d+\.\d+\.\d+-' + [regex]::Escape($suffix) + '\.zip$') }) | Select-Object -First 1
                if (-not $asset) {
                    $asset = @($rel.assets | Where-Object { $_.name -like "*-$suffix.zip" }) | Select-Object -First 1
                }
                if (-not $asset -and $suffix -eq 'win-x86') {
                    $asset = @($rel.assets | Where-Object { $_.name -like '*-win-x64.zip' }) | Select-Object -First 1
                }
                if (-not $asset) { throw "PowerShell release: no .zip asset matching *-$suffix.zip" }

                $zip = Invoke-WebRequestCachedFile -Uri $asset.browser_download_url -CacheFileName $asset.name -Headers @{ 'User-Agent' = 'WinMint/1.0' }
                $assetName = $asset.name
                $sourceUrl = $asset.browser_download_url
                $version = $rel.tag_name
            }
            catch {
                LogWarn "PowerShell 7 release lookup failed; trying cached zip. $($_.Exception.Message)"
                $zip = Get-WinMintCachedDownloadFile -Patterns @("PowerShell-*-$suffix.zip")
                if (-not $zip) { throw "PowerShell 7 cache missing PowerShell-*-$suffix.zip." }
                $assetName = [IO.Path]::GetFileName($zip)
                $sourceUrl = "cache:$assetName"
                if ($assetName -match 'PowerShell-(?<Version>\d+\.\d+\.\d+)-') {
                    $version = 'v' + $Matches.Version
                }
            }

            $ps7Hash = Assert-Win11IsoFileHash -FilePath $zip -Label "PowerShell 7 ($assetName)"
            Add-WinMintManifestPayload -Name 'PowerShell 7' -SourceUrl $sourceUrl `
                -Version $version -Sha256 $ps7Hash -SizeBytes (Get-Item -LiteralPath $zip).Length
            $expand = Join-Path (Get-Win11IsoProcessTempPath) ('pwsh7_expand_' + [Guid]::NewGuid().ToString('n'))
            Expand-Archive -LiteralPath $zip -DestinationPath $expand -Force
            $sourceDir = $expand
            if (-not (Test-Path -LiteralPath (Join-Path $sourceDir 'pwsh.exe'))) {
                $inner = @(Get-ChildItem -LiteralPath $expand -Directory -ErrorAction Stop |
                    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'pwsh.exe') })
                if ($inner.Count -ne 1) {
                    throw 'PowerShell zip: could not locate pwsh.exe at archive root or in a single top-level directory.'
                }
                $sourceDir = $inner[0].FullName
            }

            $dest = Join-Path $MountDir 'Program Files\PowerShell\7'
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction Stop }
            Copy-WinMintPayloadDirectoryChildren -SourceDir $sourceDir -DestinationDir $dest

            $pwshExe = Join-Path $dest 'pwsh.exe'
            if (-not (Test-Path -LiteralPath $pwshExe)) { throw "pwsh.exe missing after staging: $pwshExe" }
            LogOK "PowerShell 7 staged in the offline image (release: $version)."
            LogVerbose "$pwshExe (release asset: $assetName)"
        }
        catch {
            LogWarn "PowerShell 7 staging failed; setup scripts will fall back to Windows PowerShell. $($_.Exception.Message)"
        }
        finally {
            if ($zip -and (Test-Path -LiteralPath $zip) -and -not (Test-IsPathUnderWin11IsoDependencyCache $zip)) {
                Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
            }
            if ($expand -and (Test-Path -LiteralPath $expand)) { Remove-Item -LiteralPath $expand -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Get-WinMintViveToolReleaseAsset {
    param(
        [Parameter(Mandatory)][string]$TargetArch,
        [hashtable]$Headers = @{ 'User-Agent' = 'WinMint/1.0' }
    )

    $rel = Invoke-RestMethod -Verbose:$false -Uri 'https://api.github.com/repos/thebookisclosed/ViVe/releases/latest' -Headers $Headers
    $zipAssets = @($rel.assets | Where-Object { $_.name -match '\.zip$' })
    if ($zipAssets.Count -eq 0) { throw "ViVeTool release $($rel.tag_name) has no .zip assets." }

    $asset = if ($TargetArch -eq 'arm64') {
        $zipAssets | Where-Object { $_.name -match '(?i)(SnapdragonArm64|ARM64CLR|Arm64)' } | Select-Object -First 1
    } else {
        $zipAssets | Where-Object { $_.name -match '(?i)IntelAmd' } | Select-Object -First 1
    }
    if (-not $asset -and $TargetArch -ne 'arm64') {
        $asset = $zipAssets | Where-Object { $_.name -notmatch '(?i)(SnapdragonArm64|ARM64CLR|Arm64)' } | Select-Object -First 1
    }
    # Permissive ARM64 fallback: if upstream renames or drops a known prefix
    # (e.g., adds ARM64EC, drops 'Snapdragon'), accept any .zip whose name
    # contains 'arm64' in any casing. The earlier filter to .zip assets
    # already excludes .txt / .sha256 / signature sidecars.
    if (-not $asset -and $TargetArch -eq 'arm64') {
        $asset = $zipAssets | Where-Object { $_.name -match '(?i)arm64' } | Select-Object -First 1
    }
    if (-not $asset) {
        $available = ($zipAssets | ForEach-Object { $_.name }) -join ', '
        throw "ViVeTool release $($rel.tag_name) has no asset matching target architecture '$TargetArch'. Available: $available"
    }

    [pscustomobject]@{ Release = $rel; Asset = $asset }
}

function Install-OfflineViveTool {
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir,
        [Parameter(Mandatory)][string]$TargetArch
    )
    Write-SectionHeader 'Image: ViVeTool'
    Invoke-Action 'Staging ViVeTool for SetupComplete feature overrides' {
        LogVerbose "Mount: $MountDir | arch: $TargetArch"
        $zip = $null
        $expand = $null
        try {
            $headers = @{
                'User-Agent' = 'WinMint/1.0 (ViVeTool)'
                'Accept' = 'application/vnd.github+json'
                'X-GitHub-Api-Version' = '2022-11-28'
            }
            $assetName = ''
            $sourceUrl = ''
            $version = 'cached'
            try {
                $resolved = Get-WinMintViveToolReleaseAsset -TargetArch $TargetArch -Headers $headers
                $zip = Invoke-WebRequestCachedFile -Uri $resolved.Asset.browser_download_url -CacheFileName $resolved.Asset.name -Headers $headers
                $assetName = $resolved.Asset.name
                $sourceUrl = $resolved.Asset.browser_download_url
                $version = $resolved.Release.tag_name
            }
            catch {
                LogWarn "ViVeTool release lookup failed; trying cached zip. $($_.Exception.Message)"
                $zip = Get-WinMintCachedDownloadFile -Patterns @(Get-WinMintViveToolCachePattern -Architecture $TargetArch)
                if (-not $zip) { throw "ViVeTool cache missing archive for architecture '$TargetArch'." }
                $assetName = [IO.Path]::GetFileName($zip)
                $sourceUrl = "cache:$assetName"
                if ($assetName -match 'ViVeTool-(?<Version>v?\d+\.\d+\.\d+)') {
                    $version = $Matches.Version
                }
            }
            $viveHash = Assert-Win11IsoFileHash -FilePath $zip -Label "ViVeTool ($assetName)"
            Add-WinMintManifestPayload -Name 'ViVeTool' -SourceUrl $sourceUrl `
                -Version $version -Sha256 $viveHash -SizeBytes (Get-Item -LiteralPath $zip).Length
            $expand = Join-Path (Get-Win11IsoProcessTempPath) ('vivetool_expand_' + [Guid]::NewGuid().ToString('n'))
            Expand-Archive -LiteralPath $zip -DestinationPath $expand -Force
            $exe = Get-ChildItem -LiteralPath $expand -Recurse -Filter 'ViVeTool.exe' -File -ErrorAction Stop |
                Select-Object -First 1
            if (-not $exe) { throw 'ViVeTool.exe missing after extracting release archive.' }

            $dest = Join-Path $MountDir 'Windows\Setup\Scripts\ViVeTool'
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction Stop }
            Copy-WinMintPayloadDirectoryChildren -SourceDir $exe.DirectoryName -DestinationDir $dest
            if (-not (Test-Path -LiteralPath (Join-Path $dest 'ViVeTool.exe'))) {
                throw "ViVeTool.exe missing after staging: $dest"
            }

            LogOK "ViVeTool staged for setup-time feature overrides (release: $version)."
            LogVerbose "Release asset: $assetName"
        }
        catch {
            LogWarn "ViVeTool staging failed; virtual desktop flyout override will be skipped. $($_.Exception.Message)"
        }
        finally {
            if ($zip -and (Test-Path -LiteralPath $zip) -and -not (Test-IsPathUnderWin11IsoDependencyCache $zip)) {
                Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
            }
            if ($expand -and (Test-Path -LiteralPath $expand)) {
                Remove-Item -LiteralPath $expand -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Remove-NonEnglishLanguageFeature {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir,
        [string[]]$PreserveLanguages = @('en-us')
    )
    Write-SectionHeader 'Image: non-English language components'
    $cmdlet = $PSCmdlet
    Invoke-Action 'Removing non-English language feature packages from the image' {
        LogVerbose "Mount: $MountDir"
        $preserve = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($language in @('en-us') + @($PreserveLanguages)) {
            if ($language -match '^[a-z]{2,3}(?:-[a-z]+)*$') {
                $null = $preserve.Add($language.ToLowerInvariant())
            }
        }
        LogVerbose "Preserving language feature packages for: $(@($preserve) -join ', ')"
        $pkgOutput = try { @((Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Get-Packages')).Output) } catch { return }
        $languageFeaturePattern = 'Microsoft-Windows-LanguageFeatures-.+?-([a-z]{2,3}(?:-[a-z]+)*)-Package~'
        $toRemove = $pkgOutput |
            Where-Object { $_ -match $languageFeaturePattern -and -not $preserve.Contains($matches[1]) } |
            ForEach-Object {
                if ($_ -match 'Package Identity\s*:\s*(.+)$') { $matches[1].Trim() }
            }
        $removedPackages = [System.Collections.Generic.List[string]]::new()
        foreach ($pkg in $toRemove) {
            if ($cmdlet.ShouldProcess($pkg, 'Remove-WindowsPackage via DISM')) {
                Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Remove-Package', "/PackageName:$pkg", '/Quiet', '/NoRestart') | Out-Null
                $removedPackages.Add($pkg) | Out-Null
            }
        }
        if ($null -ne $script:WinMintBuildManifest) {
            $script:WinMintBuildManifest.removals.languagePackagesRemoved = $removedPackages.ToArray()
            $script:WinMintBuildManifest.removals.languagePackagesRemovedCount = $removedPackages.Count
        }
    }
}

function Save-ImageWithCleanup {
    param([ValidateNotNullOrEmpty()][string]$MountDir)
    Write-SectionHeader 'Image: cleanup and save' -Accent Yellow -RuleColor Grey -DimLine 'Component cleanup and save can take several minutes; the bar below is normal.'
    Invoke-Action 'Running DISM component cleanup on the mounted Windows image' -SpectreProgressIndeterminate {
        LogVerbose "Mount: $MountDir"
        if ($null -ne $script:WinMintBuildManifest) {
            $script:WinMintBuildManifest.servicing.componentCleanup = 'StartComponentCleanup'
            $script:WinMintBuildManifest.servicing.resetBase = $false
            $script:WinMintBuildManifest.servicing.serviceabilityPolicy = 'Preserve component-store uninstall/repair metadata; do not run ResetBase by default.'
        }
        Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Cleanup-Image', '/StartComponentCleanup') | Out-Null
        LogOK 'DISM component cleanup finished.'
    }
    Invoke-Action 'Saving and dismounting the Windows image (commit can take several minutes)' -SpectreProgressIndeterminate {
        LogVerbose "Mount: $MountDir"
        $null = Dismount-WindowsImage -Path $MountDir -Save -ErrorAction Stop
        LogOK 'Windows image saved and dismounted.'
    }
}

function Export-SingleEdition {
    param([ValidateNotNullOrEmpty()][string]$LocalWim, [int]$SelectedWimIndex, [ValidateNotNullOrEmpty()][string]$SelectedEdition)
    Write-SectionHeader "Image: export $SelectedEdition"
    Invoke-Action "Exporting a single-edition install.wim ($SelectedEdition)" {
        LogVerbose "Source WIM: $LocalWim | index $SelectedWimIndex"
        $exportWim = Join-Path (Split-Path $LocalWim -Parent) 'install_export.wim'
        $null = Export-WindowsImage -SourceImagePath $LocalWim -SourceIndex $SelectedWimIndex -DestinationImagePath $exportWim -ErrorAction Stop
        Remove-Item -LiteralPath $LocalWim -Force -ErrorAction Stop
        Rename-Item -LiteralPath $exportWim -NewName 'install.wim' -Force -ErrorAction Stop
    }
}

function Get-BuildHostProcessorArchitecture {
    <# <summary>Normalized host CPU for picking oscdimg: amd64 | arm64 | x86.</summary> #>
    $a = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    switch ($a.ToString()) {
        'X64' { return 'amd64' }
        'Arm64' { return 'arm64' }
        'X86' { return 'x86' }
        default { return $a.ToString().ToLowerInvariant() }
    }
}

function Select-PreferredOscdimgExe {
    <# <summary>Pick best oscdimg for this machine: native host architecture first, with ADK amd64/x86 fallbacks.</summary> #>
    param(
        [string[]]$CandidatePaths,
        [Parameter(Mandatory)][string]$HostProcessorArch
    )
    $p = @($CandidatePaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Sort-Object -Unique)
    if ($p.Count -eq 0) { return $null }
    if ($p.Count -eq 1) { return $p[0] }

    $scorePath = {
        param([string]$Path, [string]$HostArch)
        $score = 0
        if ($Path -match '(?i)[\\/]amd64[\\/]Oscdimg[\\/]oscdimg\.exe$') { $score = 800 }
        elseif ($Path -match '(?i)[\\/]amd64[\\/].*oscdimg\.exe$') { $score = 700 }
        elseif ($Path -match '(?i)[\\/]arm64[\\/]Oscdimg[\\/]oscdimg\.exe$') { $score = 800 }
        elseif ($Path -match '(?i)[\\/]arm64[\\/].*oscdimg\.exe$') { $score = 700 }
        elseif ($Path -match '(?i)[\\/]x86[\\/]Oscdimg[\\/]oscdimg\.exe$') { $score = 600 }
        elseif ($Path -match '(?i)[\\/]x86[\\/].*oscdimg\.exe$') { $score = 500 }
        else { $score = 100 }

        if ($HostArch -eq 'arm64' -and $Path -match '(?i)[\\/]arm64[\\/]') { $score += 1000 }
        elseif ($HostArch -eq 'amd64' -and $Path -match '(?i)[\\/]amd64[\\/]') { $score += 1000 }
        elseif ($HostArch -eq 'x86' -and $Path -match '(?i)[\\/]x86[\\/]') { $score += 1000 }
        return $score
    }

    return ($p | ForEach-Object {
            [pscustomobject]@{ Path = $_; Score = & $scorePath $_ $HostProcessorArch }
        } | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Path'; Descending = $false } | Select-Object -First 1).Path
}

function Resolve-OscdimgBootdataFilePath {
    <# <summary>Absolute path for -bootdata without embedded double-quotes (PowerShell/native quoting doubles them and breaks oscdimg). Uses 8.3 short path if the path contains spaces.</summary> #>
    param([Parameter(Mandatory)][string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath)) { throw "Boot file not found: $LiteralPath" }
    $full = [IO.Path]::GetFullPath($LiteralPath)
    if ($full -notmatch '\s') { return $full }
    try {
        $short = (New-Object -ComObject Scripting.FileSystemObject).GetFile($full).ShortPath
        if ($short -and ($short -notmatch '\s')) { return $short }
    }
    catch {
        Write-Verbose "Short path for oscdimg boot file failed: $($_.Exception.Message)"
    }
    throw "Boot file path contains spaces and could not be shortened for oscdimg. Use a build/output path without spaces, or install the Windows ADK amd64 Oscdimg. Path: $full"
}

function Get-OscdimgBootDataValue {
    <# <summary>Builds oscdimg boot sector layout from install.wim architecture.</summary> #>
    param(
        [Parameter(Mandatory)][string]$IsoContentsRoot,
        [Parameter(Mandatory)][string]$ImageArch
    )
    $efisysNoPrompt = Join-Path $IsoContentsRoot 'efi\microsoft\boot\efisys_noprompt.bin'
    $efisys = if (Test-Path -LiteralPath $efisysNoPrompt) {
        $efisysNoPrompt
    }
    else {
        Join-Path $IsoContentsRoot 'efi\microsoft\boot\efisys.bin'
    }
    if (-not (Test-Path -LiteralPath $efisys)) { throw "Missing UEFI boot file for oscdimg: $efisys" }
    $efiBootName = Split-Path -Leaf $efisys
    if ($ImageArch -eq 'arm64') {
        LogOK 'ISO boot layout: UEFI only (expected for ARM64 media).'
        LogVerbose "oscdimg -bootdata: $efiBootName only (no legacy BIOS sector on ARM64)."
        $efiTok = Resolve-OscdimgBootdataFilePath -LiteralPath $efisys
        return ('1#pEF,e,b{0}' -f $efiTok)
    }
    $etfs = Join-Path $IsoContentsRoot 'boot\etfsboot.com'
    $efiTok = Resolve-OscdimgBootdataFilePath -LiteralPath $efisys
    if (Test-Path -LiteralPath $etfs) {
        LogOK 'ISO boot layout: legacy BIOS + UEFI (El Torito + EFI boot).'
        LogVerbose "oscdimg -bootdata: etfsboot.com + $efiBootName."
        $etfsTok = Resolve-OscdimgBootdataFilePath -LiteralPath $etfs
        return ('2#p0,e,b{0}#pEF,e,b{1}' -f $etfsTok, $efiTok)
    }
    LogWarn 'boot\etfsboot.com not found on the staged tree; ISO will be UEFI-only (no legacy BIOS boot sector).'
    return ('1#pEF,e,b{0}' -f $efiTok)
}

function Get-Win11IsoWingetExePath {
    <# <summary>Resolves winget.exe for package downloads (PATH or Desktop App Installer install location).</summary> #>
    $wingetCmd = (Get-Command winget -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
    if (-not $wingetCmd) {
        $wingetPkg = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $wingetPkg -and $wingetPkg.InstallLocation) {
            $wingetCmd = Join-Path $wingetPkg.InstallLocation 'winget.exe'
        }
    }
    if ($wingetCmd -and (Test-Path -LiteralPath $wingetCmd)) { return $wingetCmd }
    return $null
}

function Get-WindowsKitsOscdimgCandidates {
    $kitsRoot = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Windows Kits'
    if (-not (Test-Path -LiteralPath $kitsRoot)) { return @() }
    return @(Get-ChildItem -LiteralPath $kitsRoot -Recurse -Filter 'oscdimg.exe' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
}

function Invoke-Win11IsoWingetCommand {
    param(
        [Parameter(Mandatory)][string]$WingetPath,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $oldPref = $PSNativeCommandUseErrorActionPreference
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        $output = & $WingetPath @Arguments 2>&1
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output   = ($output | Out-String)
        }
    }
    finally {
        $PSNativeCommandUseErrorActionPreference = $oldPref
    }
}

function Install-Win11IsoWindowsAdkForOscdimg {
    <# <summary>Installs ADK Deployment Tools through WinGet. ADK manifests are x64-only, but include ARM64 oscdimg payloads.</summary> #>
    param([Parameter(Mandatory)][string]$WingetPath)

    $attempts = @(
        @('install', '-e', '--id', 'Microsoft.WindowsADK', '--architecture', 'x64', '--accept-package-agreements', '--accept-source-agreements'),
        @('install', '-e', '--id', 'Microsoft.WindowsADK', '--version', '10.1.26100.2454', '--architecture', 'x64', '--accept-package-agreements', '--accept-source-agreements')
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($wingetArgs in $attempts) {
        Log "Installing Windows ADK Deployment Tools via winget ($($wingetArgs -join ' '))."
        $result = Invoke-Win11IsoWingetCommand -WingetPath $WingetPath -Arguments $wingetArgs
        if ($result.ExitCode -eq 0) { return }
        $errors.Add("winget $($wingetArgs -join ' ') exited $($result.ExitCode)`n$($result.Output)")
        LogVerbose "Windows ADK winget install failed: $($result.Output)"
    }

    throw ($errors -join "`n---`n")
}

function Resolve-OscdimgPath {
    $hostArch = Get-BuildHostProcessorArchitecture
    # Resolve via the environment instead of a hardcoded C: drive — Windows can be
    # installed on any drive letter and the user may have the ADK on D:\ or similar.
    $kitsCandidates = Get-WindowsKitsOscdimgCandidates
    $oscdimg = Select-PreferredOscdimgExe -CandidatePaths $kitsCandidates -HostProcessorArch $hostArch
    if (-not $oscdimg) {
        $wingetPkgRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Microsoft\WinGet\Packages'
        $wgCandidates = @(
            Get-ChildItem -LiteralPath $wingetPkgRoot -Recurse -Filter 'oscdimg.exe' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match 'Microsoft\.OSCDIMG' } |
                ForEach-Object { $_.FullName }
        )
        $oscdimg = Select-PreferredOscdimgExe -CandidatePaths $wgCandidates -HostProcessorArch $hostArch
    }
    if (-not $oscdimg) {
        $dlRoot = Join-Path (Get-Win11IsoDependencyCacheRoot) 'OSCDIMG_winget'
        try {
            $null = New-Item -ItemType Directory -Path $dlRoot -Force
            $foundCache = @(Get-ChildItem -LiteralPath $dlRoot -Recurse -Filter 'oscdimg.exe' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
            $oscdimg = Select-PreferredOscdimgExe -CandidatePaths $foundCache -HostProcessorArch $hostArch
            if ($oscdimg) {
                LogVerbose "oscdimg from dependency cache: $oscdimg"
            }
            else {
                $wingetCmd = Get-Win11IsoWingetExePath
                if (-not $wingetCmd) {
                    throw 'winget.exe not found.'
                }
                $wgResult = Invoke-Win11IsoWingetCommand -WingetPath $wingetCmd -Arguments @(
                    'download',
                    '-e',
                    '--id',
                    'Microsoft.OSCDIMG',
                    '--download-directory',
                    $dlRoot,
                    '--accept-package-agreements',
                    '--accept-source-agreements'
                )
                if ($wgResult.ExitCode -ne 0) {
                    throw "winget download exited $($wgResult.ExitCode)`n$($wgResult.Output)"
                }
                $found = @(Get-ChildItem -LiteralPath $dlRoot -Recurse -Filter 'oscdimg.exe' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
                $oscdimg = Select-PreferredOscdimgExe -CandidatePaths $found -HostProcessorArch $hostArch
                if (-not $oscdimg) {
                    Remove-Item -LiteralPath $dlRoot -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
            Write-Verbose "oscdimg winget download failed: $($_.Exception.Message)"
            if (Test-Path -LiteralPath $dlRoot) {
                $still = @(Get-ChildItem -LiteralPath $dlRoot -Recurse -Filter 'oscdimg.exe' -File -ErrorAction SilentlyContinue)
                if ($still.Count -eq 0) { Remove-Item -LiteralPath $dlRoot -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
    }
    if (-not $oscdimg) {
        try {
            $wingetCmd = Get-Win11IsoWingetExePath
            if (-not $wingetCmd) {
                throw 'winget.exe not found.'
            }
            Install-Win11IsoWindowsAdkForOscdimg -WingetPath $wingetCmd
            $oscdimg = Select-PreferredOscdimgExe -CandidatePaths (Get-WindowsKitsOscdimgCandidates) -HostProcessorArch $hostArch
        }
        catch {
            Write-Verbose "Windows ADK winget install failed: $($_.Exception.Message)"
        }
    }
    if (-not $oscdimg) {
        throw @(
            'oscdimg.exe not found. Install the Windows ADK Deployment Tools,'
            'or ensure winget can install Microsoft.WindowsADK with --architecture x64.'
            'WinMint tries Microsoft.OSCDIMG first, then Microsoft.WindowsADK latest, then version 10.1.26100.2454.'
        ) -join ' '
    }
    return $oscdimg
}
