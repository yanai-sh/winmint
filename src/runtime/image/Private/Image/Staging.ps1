#Requires -Version 7.6

function Get-WinMintHostDismArch {
    $a = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch -Regex ([string]$a) {
        '^ARM64$' { 'arm64'; break }
        '^(AMD64|IA64)$' { 'amd64'; break }
        default { 'x86' }
    }
}

function Get-WinMintDismFileBuild {
    param([Parameter(Mandatory)][string]$Exe)
    try {
        $pv = [string](Get-Item -LiteralPath $Exe -ErrorAction Stop).VersionInfo.ProductVersion
        if ($pv -match '\d+\.\d+\.(\d+)') { return [int]$matches[1] }
    }
    catch { }
    return 0
}

function Get-WinMintDismExe {
    <#
    <summary>
    Resolves the dism.exe WinMint uses for servicing: the newest available by
    build number, preferring a host-arch-native ADK build, then the in-box dism.
    Windows 11 25H2 (build 26200) ships an enablement package over the 24H2
    servicing stack, so the in-box dism reports build 26100 and STRIPS edition/
    installation/product metadata when committing a 26200 image (verified). A
    matching ADK dism whose build is >= the image build commits cleanly. Cached
    after first resolution.
    </summary>
    #>
    $cached = Get-Variable -Name WinMintDismExe -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($cached -and (Test-Path -LiteralPath $cached)) {
        return $cached
    }
    $hostArch = Get-WinMintHostDismArch
    $candidates = [System.Collections.Generic.List[object]]::new()
    $kits = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Windows Kits\10\Assessment and Deployment Kit\Deployment Tools'
    foreach ($arch in @('arm64', 'amd64', 'x86')) {
        $exe = Join-Path $kits "$arch\DISM\dism.exe"
        if (Test-Path -LiteralPath $exe) {
            $candidates.Add([pscustomobject]@{ Path = $exe; Arch = $arch; Build = (Get-WinMintDismFileBuild $exe); Native = ($arch -eq $hostArch); InBox = $false })
        }
    }
    $inbox = Join-Path $env:WINDIR 'System32\dism.exe'
    if (Test-Path -LiteralPath $inbox) {
        $candidates.Add([pscustomobject]@{ Path = $inbox; Arch = $hostArch; Build = (Get-WinMintDismFileBuild $inbox); Native = $true; InBox = $true })
    }
    if ($candidates.Count -eq 0) {
        $script:WinMintDismExe = 'dism.exe'
        return $script:WinMintDismExe
    }
    # Newest build wins; tie-break to host-arch-native, then to the in-box dism.
    $best = $candidates |
        Sort-Object @{ Expression = { [int]$_.Build }; Descending = $true },
                    @{ Expression = { [int][bool]$_.Native }; Descending = $true },
                    @{ Expression = { [int][bool]$_.InBox }; Descending = $true } |
        Select-Object -First 1
    $script:WinMintDismExe = $best.Path
    LogVerbose "Servicing dism: $($best.Path) (build $($best.Build), arch $($best.Arch), inbox=$($best.InBox))"
    return $script:WinMintDismExe
}

function Mount-WinMintImage {
    <# <summary>Mounts a WIM index via the resolved servicing dism.exe (not the in-box-bound Mount-WindowsImage cmdlet), so mount and commit share one stack.</summary> #>
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][string]$MountDir
    )
    if (Test-Path -LiteralPath $MountDir) {
        if (Get-Command Test-WinMintMountedImagePath -ErrorAction SilentlyContinue) {
            if (Test-WinMintMountedImagePath -Path $MountDir) {
                Dismount-WinMintImageMount -MountDir $MountDir
            }
        }
        if (Test-Path -LiteralPath $MountDir) {
            Remove-Item -LiteralPath $MountDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        $null = New-Item -ItemType Directory -Path $MountDir -Force
    }
    Invoke-DismExe -Arguments @('/English', '/Mount-Image', "/ImageFile:$ImagePath", "/Index:$Index", "/MountDir:$MountDir") | Out-Null
}

function Save-WinMintImageMount {
    <# <summary>Commits and unmounts a mounted image via the resolved servicing dism.exe. Using a dism whose build is >= the image build preserves edition metadata on commit.</summary> #>
    param([Parameter(Mandatory)][string]$MountDir)
    Invoke-DismExe -Arguments @('/English', '/Unmount-Image', "/MountDir:$MountDir", '/Commit') | Out-Null
}

function Dismount-WinMintImageMount {
    <# <summary>Best-effort discard of a mounted image via the resolved servicing dism.exe; used on failure/cleanup paths.</summary> #>
    param([Parameter(Mandatory)][string]$MountDir)
    try { Invoke-DismExe -Arguments @('/English', '/Unmount-Image', "/MountDir:$MountDir", '/Discard') | Out-Null }
    catch { Write-Verbose "Discard mount ${MountDir}: $($_.Exception.Message)" }
}

function Get-ISOArchitecture {
    <# <summary>Identifies architecture using fixed switch syntax.</summary> #>
    param([ValidateNotNullOrEmpty()][string]$ImagePath, [int]$Index = 1)
    $info = Get-WindowsImage -ImagePath $ImagePath -Index $Index -ErrorAction SilentlyContinue
    if ($null -ne $info -and $info.PSObject.Properties.Match('Architecture').Count -gt 0) {
        switch ([int]$info.Architecture) {
            9 { return 'amd64' }
            12 { return 'arm64' }
            0 { return 'x86' }
        }
    }

    $dismOut = & (Get-WinMintDismExe) /English /Get-ImageInfo /ImageFile:"$ImagePath" /Index:$Index 2>&1
    $archLine = $dismOut | Where-Object { $_ -match 'Architecture\s*:\s*(.+)$' } | Select-Object -First 1
    if ($archLine -match 'Architecture\s*:\s*(.+)$') {
        switch -Regex ($matches[1].Trim().ToLower()) {
            '^(x64|amd64)$' { return 'amd64' }
            '^arm64$' { return 'arm64' }
            '^x86$' { return 'x86' }
        }
    }
    throw "Could not determine WIM architecture."
}

function Get-WinMintDismExeVersion {
    # Report the version of the resolved servicing dism (the one that actually
    # mounts/commits), so the capability guard checks the tool we will use. Read
    # the file's ProductVersion first (reliable); fall back to parsing /?.
    $exe = Get-WinMintDismExe
    try {
        $pv = [string](Get-Item -LiteralPath $exe -ErrorAction Stop).VersionInfo.ProductVersion
        if ($pv -match '(\d+\.\d+\.\d+(?:\.\d+)?)') { return [version]$matches[1] }
    }
    catch { }
    $versionLine = (& $exe /English /? 2>&1 | Where-Object { $_ -match 'Version:\s*([0-9.]+)' } | Select-Object -First 1)
    if ($versionLine -match 'Version:\s*([0-9.]+)') {
        return [version]$matches[1]
    }
    throw 'Could not determine dism.exe version.'
}

function Get-WinMintWimImageVersion {
    param(
        [ValidateNotNullOrEmpty()][string]$ImagePath,
        [int]$Index = 1
    )

    $dismOut = & (Get-WinMintDismExe) /English /Get-WimInfo /WimFile:"$ImagePath" /Index:$Index 2>&1
    $versionLine = $dismOut | Where-Object { $_ -match '^\s*Version\s*:\s*([0-9.]+)' } | Select-Object -Last 1
    $servicePackBuildLine = $dismOut | Where-Object { $_ -match '^\s*ServicePack Build\s*:\s*(\d+)' } | Select-Object -First 1

    if ($versionLine -notmatch '^\s*Version\s*:\s*([0-9.]+)') {
        throw "Could not determine Windows image version for $ImagePath."
    }
    $base = [version]$matches[1]
    $ubr = 0
    if ($servicePackBuildLine -match '^\s*ServicePack Build\s*:\s*(\d+)') {
        $ubr = [int]$matches[1]
    }

    return [pscustomobject]@{
        Version = $base
        Build = [int]$base.Build
        Ubr = $ubr
        Display = if ($ubr -gt 0) { "$base.$ubr" } else { [string]$base }
    }
}

function Get-WinMintWimImageMetadata {
    param(
        [ValidateNotNullOrEmpty()][string]$ImagePath,
        [int]$Index = 1
    )

    $dismOut = & (Get-WinMintDismExe) /English /Get-WimInfo /WimFile:"$ImagePath" /Index:$Index 2>&1
    $versionLine = $dismOut | Where-Object { $_ -match '^\s*Version\s*:\s*([0-9.]+)' } | Select-Object -Last 1
    $servicePackBuildLine = $dismOut | Where-Object { $_ -match '^\s*ServicePack Build\s*:\s*(\d+)' } | Select-Object -First 1
    $languages = [System.Collections.Generic.List[string]]::new()
    $captureLanguages = $false
    $values = @{}

    foreach ($line in $dismOut) {
        $text = [string]$line
        if ($text -match '^\s*([^:]+?)\s*:\s*(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            $values[$key] = $value
            $captureLanguages = ($key -eq 'Languages')
            if ($captureLanguages -and -not [string]::IsNullOrWhiteSpace($value)) {
                # Some dism builds put the code inline ("Languages : en-US (Default)");
                # capture just the language tag, dropping the "(Default)" annotation.
                if ($value -match '^([A-Za-z]{2,3}(?:-[A-Za-z0-9]+)+)') { $languages.Add($matches[1]) | Out-Null }
                else { $languages.Add($value) | Out-Null }
            }
            continue
        }
        # Other dism builds (incl. the in-box 26100 and ADK 28000 on a 25H2 image)
        # list each language on its own indented line, usually with a "(Default)"
        # suffix ("\ten-US (Default)"); match the leading tag, not the whole line.
        if ($captureLanguages -and $text -match '^\s+([A-Za-z]{2,3}(?:-[A-Za-z0-9]+)+)(?:\s|$)') {
            $languages.Add($matches[1].Trim()) | Out-Null
        }
        elseif ($captureLanguages -and -not [string]::IsNullOrWhiteSpace($text)) {
            $captureLanguages = $false
        }
    }

    if ($versionLine -notmatch '^\s*Version\s*:\s*([0-9.]+)') {
        throw "Could not determine Windows image version for $ImagePath index $Index."
    }
    $base = [version]$matches[1]
    $ubr = 0
    if ($servicePackBuildLine -match '^\s*ServicePack Build\s*:\s*(\d+)') {
        $ubr = [int]$matches[1]
    }

    [pscustomobject]@{
        ImageIndex = $Index
        Name = [string]$values['Name']
        Architecture = [string]$values['Architecture']
        Version = [string]$base
        Build = [int]$base.Build
        Ubr = $ubr
        Edition = [string]$values['Edition']
        Installation = [string]$values['Installation']
        ProductType = [string]$values['ProductType']
        Languages = @($languages | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }
}

function Get-WinMintSelectedWimMetadata {
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][object[]]$Images
    )

    @(
        foreach ($image in $Images) {
            Get-WinMintWimImageMetadata -ImagePath $ImagePath -Index ([int]$image.ImageIndex)
        }
    )
}

function Assert-WinMintDismCanServiceWim {
    param(
        [ValidateNotNullOrEmpty()][string]$ImagePath,
        [int]$Index = 1
    )

    # The DISM build is the servicing-capability signal, NOT the host OS build.
    # The tool that actually mounts and commits the image is dism.exe (and the
    # PowerShell Mount/Dismount-WindowsImage cmdlets that bind to the same
    # servicing stack). A no-op mount+commit of a build-26200 image with a
    # build-26100 dism was verified to strip EditionId/InstallationType/
    # ProductType, so the host OS version is irrelevant: only a dism whose build
    # is >= the image build can commit it without corrupting edition metadata.
    # Note: Windows 11 25H2 ships an enablement package over the 24H2 servicing
    # stack, so a 25H2 host's in-box dism still reports 26100 and CANNOT safely
    # service a 26200 image; the matching ADK dism (build >= image) is required.
    $dismVersion = Get-WinMintDismExeVersion
    $imageVersion = Get-WinMintWimImageVersion -ImagePath $ImagePath -Index $Index
    if ([int]$imageVersion.Build -gt [int]$dismVersion.Build) {
        throw @(
            "WinMint cannot safely service this Windows image with the current DISM engine."
            "Image build: $($imageVersion.Display)"
            "DISM build: $dismVersion"
            'Install a Windows ADK whose DISM build is at least as new as the source image,'
            'or build from an ISO whose image build is not newer than the DISM engine.'
            'A 25H2 (26200) image cannot be serviced by an in-box 24H2 (26100) DISM,'
            'even on a 25H2 host.'
            'Refusing to continue because downlevel DISM servicing strips edition/language metadata and produces a setup product-key/edition validation loop.'
        ) -join [Environment]::NewLine
    }
}

function Assert-WinMintDismCanServiceImages {
    param(
        [ValidateNotNullOrEmpty()][string]$ImagePath,
        [Parameter(Mandatory)][object[]]$Images
    )

    foreach ($image in $Images) {
        Assert-WinMintDismCanServiceWim -ImagePath $ImagePath -Index ([int]$image.ImageIndex)
    }
}

function Assert-WinMintWimMetadataHealthy {
    param(
        [ValidateNotNullOrEmpty()][string]$ImagePath,
        [Parameter(Mandatory)][object[]]$ExpectedMetadata,
        [ValidateNotNullOrEmpty()][string]$ExpectedArchitecture,
        [switch]$AllowIndexRenumber
    )

    $images = @(Get-WindowsImage -ImagePath $ImagePath -ErrorAction Stop | Sort-Object ImageIndex)
    if ($images.Count -lt 1) { throw "install.wim validation failed: no images found in $ImagePath." }
    if (-not $AllowIndexRenumber -and $images.Count -lt @($ExpectedMetadata).Count) {
        throw "install.wim validation failed: expected at least $(@($ExpectedMetadata).Count) image(s), found $($images.Count)."
    }

    foreach ($expected in @($ExpectedMetadata)) {
        $match = $null
        if (-not $AllowIndexRenumber) {
            $match = $images | Where-Object { [int]$_.ImageIndex -eq [int]$expected.ImageIndex } | Select-Object -First 1
        }
        if (-not $match -and -not [string]::IsNullOrWhiteSpace([string]$expected.Name)) {
            $match = $images | Where-Object { [string]$_.ImageName -eq [string]$expected.Name } | Select-Object -First 1
        }
        if (-not $match) {
            throw "install.wim validation failed: expected image '$($expected.Name)' was not found after servicing."
        }

        $actual = Get-WinMintWimImageMetadata -ImagePath $ImagePath -Index ([int]$match.ImageIndex)
        $required = @('Edition', 'Installation', 'ProductType')
        foreach ($field in $required) {
            $value = [string]$actual.$field
            if ([string]::IsNullOrWhiteSpace($value) -or $value -eq '<undefined>') {
                throw "install.wim validation failed: image '$($actual.Name)' has invalid $field metadata ('$value'). This media will not be published."
            }
        }
        if (@($actual.Languages).Count -lt 1) {
            throw "install.wim validation failed: image '$($actual.Name)' has no language metadata. This media will not be published."
        }
        if ([string]$actual.Architecture -ne $ExpectedArchitecture) {
            throw "install.wim validation failed: image '$($actual.Name)' architecture is '$($actual.Architecture)', expected '$ExpectedArchitecture'."
        }
        if ([int]$actual.Build -ne [int]$expected.Build) {
            throw "install.wim validation failed: image '$($actual.Name)' build changed from $($expected.Build) to $($actual.Build)."
        }
    }
    LogOK "install.wim metadata validation passed ($(@($ExpectedMetadata).Count) expected image(s))."
}

function Invoke-RobocopyChecked {
    param(
        [ValidateNotNullOrEmpty()][string]$Source,
        [ValidateNotNullOrEmpty()][string]$Dest,
        [string]$UserFacingMessage
    )
    $msgDry = if ($UserFacingMessage) { $UserFacingMessage } else { 'Copying the mounted ISO into the working folder for dry-run validation…' }
    $msgFull = if ($UserFacingMessage) { $UserFacingMessage } else { 'Copying the mounted ISO into the working folder (~5 GB, 1-3 minutes; robocopy runs silently)…' }
    if ($DryRun) {
        Log $msgDry
        LogVerbose "robocopy `"$Source`" `"$Dest`""
    }
    else {
        Log $msgFull
        LogVerbose "robocopy `"$Source`" `"$Dest`""
    }
    if ($Source -like '\\?\Volume{*') {
        foreach ($item in (Get-ChildItem -LiteralPath $Source -Force -ErrorAction Stop)) {
            Copy-Item -LiteralPath $item.FullName -Destination $Dest -Recurse -Force -ErrorAction Stop
        }
    }
    else {
        $oldPref = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
        $null = & robocopy.exe "$Source" "$Dest" /E /NFL /NDL /NJH /NJS
        $code = $LASTEXITCODE
        $PSNativeCommandUseErrorActionPreference = $oldPref
        if ($code -ge 8) { throw "robocopy exit $code" }
    }
}

function Clear-WinMintReadOnlyAttribute {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $oldPref = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $null = & attrib.exe -R "$Path\*" /S /D 2>&1
        # attrib.exe returns 0 for success and is idempotent; ignore non-zero
        # because some descendants (junction reparse points) report E_ACCESS but
        # the underlying read-only flag is still cleared on real files.
    }
    finally {
        $PSNativeCommandUseErrorActionPreference = $oldPref
    }
    LogVerbose "Cleared read-only attribute recursively under $Path"
}

function Invoke-DismExe {
    <# <summary>Runs dism.exe with stderr merged, captures output, and throws with full text on failure (works with PSNativeCommandUseErrorActionPreference).</summary> #>
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [int[]]$SuccessCodes = @(0)
    )
    $oldPref = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $lines = [System.Collections.Generic.List[string]]::new()
        $dismExe = Get-WinMintDismExe
        if ($null -ne $script:DismProgressCallback) {
            & $dismExe @Arguments 2>&1 | ForEach-Object {
                $line = [string]$_
                $lines.Add($line)
                if ($line -match '\[\s*=*\s*([\d.]+)%') {
                    & $script:DismProgressCallback ([double]$Matches[1])
                }
            }
        } else {
            & $dismExe @Arguments 2>&1 | ForEach-Object { $lines.Add([string]$_) }
        }
        $code = $LASTEXITCODE
        if ($SuccessCodes -notcontains $code) {
            throw "dism.exe failed (exit $code).`n  dism.exe $($Arguments -join ' ')`n$($lines -join "`n")"
        }
        return [pscustomobject]@{ ExitCode = $code; Output = $lines.ToArray() }
    }
    finally {
        $PSNativeCommandUseErrorActionPreference = $oldPref
    }
}

function Test-OfflineStagingReadiness {
    <# <summary>Read-only checks after ISO contents are copied: WIM metadata, arch vs hint, boot.wim indices, output dir, oscdimg, drivers.</summary> #>
    param(
        [Parameter(Mandatory)][string]$LocalInstallWim,
        [Parameter(Mandatory)][string]$IsoContentsRoot,
        [string]$ExpectedArchHint,
        [Parameter(Mandatory)][string]$ScriptDirForChecks,
        [ValidateSet('None', 'Custom', 'Host', 'HostExport', 'CustomInfFolder', 'OemMsi', 'SurfaceMsiSafe', 'SurfaceCatalog')][string]$DriverSource = 'None',
        [string]$CustomDriverPath,
        [bool]$ExportHostDrivers
    )
    if (-not (Test-Path -LiteralPath $LocalInstallWim)) {
        throw "sources\install.wim not found after staging: $LocalInstallWim"
    }
    $installMetas = @(Get-WindowsImage -ImagePath $LocalInstallWim -ErrorAction Stop)
    if ($installMetas.Count -lt 1) { throw 'Get-WindowsImage returned no images for install.wim.' }

    $archInst = $installMetas | Where-Object ImageIndex -EQ 1 | Select-Object -First 1
    if (-not $archInst) { $archInst = $installMetas[0] }
    $useIndex = [int]$archInst.ImageIndex
    # Listing all images (no -Index) often omits Architecture on each row; Get-ISOArchitecture uses -Index + DISM fallback.
    $detected = Get-ISOArchitecture -ImagePath $LocalInstallWim -Index $useIndex
    if ($ExpectedArchHint -and $detected -ne $ExpectedArchHint) {
        throw "install.wim CPU architecture is '$detected' but the ISO file name or your selection indicated '$ExpectedArchHint'."
    }
    Assert-WinMintDismCanServiceWim -ImagePath $LocalInstallWim -Index $useIndex
    LogOK "Staged install.wim looks valid ($detected, $($installMetas.Count) edition(s))."
    LogVerbose "install.wim image index in use: $($archInst.ImageIndex)."

    $bootWim = Join-Path $IsoContentsRoot 'sources\boot.wim'
    if (Test-Path -LiteralPath $bootWim) {
        $bootMetas = @(Get-WindowsImage -ImagePath $bootWim -ErrorAction Stop)
        $indexes = @($bootMetas.ImageIndex | Sort-Object)
        $forDrivers = @(@(2) | Where-Object { $_ -in $indexes })
        if ($forDrivers.Count -eq 0) { $forDrivers = @($indexes | Select-Object -Last 1) }
        if ($forDrivers.Count -eq 0) { throw 'boot.wim reported no images.' }
        $script:BootWimDriverMountIndexes = $forDrivers
        $script:BootWimWinPEUtilityMountIndex = if ($indexes -contains 2) { 2 } else { $indexes[-1] }
        LogOK "boot.wim present ($($indexes.Count) image(s)); Setup-only WinPE driver pass and utilities are wired."
        LogVerbose "boot.wim driver indexes: $($script:BootWimDriverMountIndexes -join ', '); WinPE utility index: $($script:BootWimWinPEUtilityMountIndex)."
    }
    else {
        LogWarn 'sources\boot.wim not found on the staged copy. WinPE driver injection and WinPE tweaks are skipped.'
        $script:BootWimDriverMountIndexes = @()
    }

    LogOK "Output folder: $ScriptDirForChecks"

    $oscd = Resolve-OscdimgPath
    LogOK "oscdimg resolved for the ISO step."
    LogVerbose $oscd

    # Enumerate every driver source this build will actually use, then report each one
    # honestly. A "source" contributes to injection if it ends up holding .inf files (either
    # directly or after MSI expansion). $contributing tracks whether at least one source will
    # supply drivers — if zero, we warn (unless DriverSource=None, in which case the user
    # explicitly chose default Windows drivers and the absence is intentional).
    $contributing = $false
    $sourcesReported = 0

    # 1. Custom path (.inf, .msi, or folder containing either) — primary source when DriverSource=Custom.
    if (Test-WinMintDriverSourceUsesSurfaceCatalog -Source $DriverSource) {
        try {
            $surfaceDevice = Resolve-WinMintSurfaceCatalogDevice -DeviceId $CustomDriverPath
            LogOK "Surface catalog driver package: $($surfaceDevice.name) ($($surfaceDevice.architecture)); downloaded during full build."
        }
        catch {
            LogWarn $_.Exception.Message
        }
    }
    elseif (Test-WinMintDriverSourceUsesPath -Source $DriverSource) {
        $sourcesReported++
        if ([string]::IsNullOrWhiteSpace($CustomDriverPath)) {
            LogWarn "Driver source '$DriverSource' selected but no path is set."
        }
        elseif (-not (Test-Path -LiteralPath $CustomDriverPath)) {
            LogWarn "Custom driver path not found: $CustomDriverPath"
        }
        else {
            $item = Get-Item -LiteralPath $CustomDriverPath -ErrorAction Stop
            if ((Test-WinMintDriverSourceRequiresMsi -Source $DriverSource) -and ($item.PSIsContainer -or $item.Extension -ine '.msi')) {
                LogWarn "Driver source '$DriverSource' requires an OEM .msi file: $($item.FullName)"
            }
            elseif ($item.PSIsContainer) {
                $infs = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue)
                $msis = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -Filter '*.msi' -File -ErrorAction SilentlyContinue)
                if ($infs.Count -ge 1) {
                    LogOK "Custom folder ($($item.FullName)): $($infs.Count) .inf file(s) ready for injection."
                    $contributing = $true
                }
                elseif ($msis.Count -ge 1) {
                    LogOK "Custom folder ($($item.FullName)): $($msis.Count) MSI(s) will be administrative-installed before DISM."
                    $contributing = $true
                }
                else {
                    LogWarn "Custom driver folder is empty (no .inf or .msi): $($item.FullName)"
                }
            }
            elseif ($item.Extension -ieq '.inf') {
                LogOK "Custom INF: $($item.Name) (folder $($item.DirectoryName))."
                $contributing = $true
            }
            elseif ($item.Extension -ieq '.msi') {
                LogOK "Custom MSI: $($item.Name) — administrative-installed before DISM."
                $contributing = $true
            }
            elseif ($item.Extension -ieq '.zip') {
                LogOK "Custom driver ZIP: $($item.Name) — extracted before DISM."
                $contributing = $true
            }
            else {
                LogWarn "Custom driver path is not a .inf, .msi, .zip, or folder: $($item.FullName)"
            }
        }
    }

    # 2. Host driver export — runs Export-WindowsDriver -Online at build time.
    if ($ExportHostDrivers) {
        $sourcesReported++
        LogOK 'Host driver export: Export-WindowsDriver -Online will run during the build, with pnputil fallback if needed.'
        $contributing = $true
    }

    if (-not $contributing) {
        if ($DriverSource -eq 'None') {
            Log 'Driver injection: none configured (target ships with default Windows drivers).'
        }
        else {
            LogWarn "Driver source is '$DriverSource' but no usable driver files were found across any source. The build will produce an ISO with default Windows drivers only."
        }
    }

    return [pscustomObject]@{ Architecture = $detected }
}

function Test-RemoteBuildPrerequisite {
    <# <summary>Second dry-run pass: GitHub API asset resolution (no large downloads), ISO boot files, optional autounattend XML, Export-WindowsDriver.</summary> #>
    param(
        [Parameter(Mandatory)][string]$TargetArch,
        [Parameter(Mandatory)][string]$IsoContentsRoot,
        [string]$AutounattendPath,
        [switch]$ExportHostDriversRequested
    )
    $gh = Get-WinMintGitHubApiHeaders
    $gh['Accept'] = 'application/vnd.github+json'
    $gh['X-GitHub-Api-Version'] = '2022-11-28'

    Write-SectionHeader 'Dry run: web checks and ISO layout'
    Log 'Checking boot files required for the ISO…'
    $efisysRel = if (Test-Path -LiteralPath (Join-Path $IsoContentsRoot 'efi\microsoft\boot\efisys_noprompt.bin')) {
        'efi\microsoft\boot\efisys_noprompt.bin'
    }
    else {
        'efi\microsoft\boot\efisys.bin'
    }
    $etfsRel = 'boot\etfsboot.com'
    $bootRels = if ($TargetArch -eq 'arm64') {
        @($efisysRel)
    }
    elseif (Test-Path -LiteralPath (Join-Path $IsoContentsRoot $etfsRel)) {
        @($etfsRel, $efisysRel)
    }
    else {
        @($efisysRel)
    }
    foreach ($relBoot in $bootRels) {
        $bf = Join-Path $IsoContentsRoot $relBoot
        if (-not (Test-Path -LiteralPath $bf)) { throw "Staged ISO is missing '$relBoot' (needed for ISO build). Path: $bf" }
        LogVerbose "Boot file OK: $relBoot -> $bf"
    }
    LogOK 'Boot files for oscdimg are present on the staged tree.'

    if ($AutounattendPath -and (Test-Path -LiteralPath $AutounattendPath)) {
        try {
            $raw = Get-Content -LiteralPath $AutounattendPath -Raw -ErrorAction Stop
            $xd = [xml]::new()
            $xd.LoadXml($raw)
            LogOK 'autounattend.xml is valid XML and loads cleanly.'
            LogVerbose $AutounattendPath
        }
        catch {
            throw "autounattend.xml exists but is not valid XML: $AutounattendPath — $_"
        }
    }

    if ($ExportHostDriversRequested) {
        $hostArch = Get-BuildHostProcessorArchitecture
        if ($hostArch -ne $TargetArch) {
            $archMsg = "Mirror PC drivers were requested, but the build PC architecture is '$hostArch' " +
                       "and the target ISO architecture is '$TargetArch'. " +
                       'Select an INF folder built for the target device, or skip driver injection.'
            throw $archMsg
        }
        if (
            -not (Get-Command Export-WindowsDriver -ErrorAction SilentlyContinue) -and
            -not (Get-Command pnputil.exe -CommandType Application -ErrorAction SilentlyContinue)
        ) {
            throw 'ExportHostDrivers was requested but neither Export-WindowsDriver nor pnputil.exe is available.'
        }
        LogOK 'Host driver export tooling is available.'
    }

    $probeHead = {
        param([string]$Uri, [string]$Label)
        try {
            $resp = Invoke-WebRequest -Verbose:$false -Uri $Uri -Method Head -Headers $gh -MaximumRedirection 5 -SkipHttpErrorCheck
            if ($resp.StatusCode -lt 200 -or $resp.StatusCode -ge 400) {
                LogWarn "Download URL for $Label returned HTTP $($resp.StatusCode) (HEAD)."
                LogVerbose $Uri
            }
            else {
                LogVerbose "$Label HEAD $($resp.StatusCode)"
            }
        }
        catch {
            LogWarn "Could not reach $Label over the network: $($_.Exception.Message)"
            LogVerbose $Uri
        }
    }

    Log 'Checking GitHub releases used by the build (names only; no large downloads)…'
    Start-Sleep -Milliseconds 150
    if (-not (Test-WinMintGitHubApiReachable -TimeoutSec 5)) {
        LogWarn 'GitHub API is not reachable; skipping release freshness checks and using cached payloads where available.'
        return
    }

    try {
        $cascRel = Invoke-RestMethod -Verbose:$false -Uri 'https://api.github.com/repos/microsoft/cascadia-code/releases/latest' -Headers $gh
        $cascAsset = $cascRel.assets | Where-Object name -match 'CascadiaCode-.*\.zip' | Select-Object -First 1
        if (-not $cascAsset) { throw 'Dry-run: Cascadia Code latest release has no .zip asset matching CascadiaCode-*.zip.' }
        & $probeHead $cascAsset.browser_download_url 'Cascadia zip'

        Start-Sleep -Milliseconds 150
        $wgRel = Invoke-RestMethod -Verbose:$false -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -Headers $gh
        $wgAsset = $wgRel.assets | Where-Object { $_.name -match '\.msixbundle$' } | Select-Object -First 1
        if (-not $wgAsset) { throw 'Dry-run: winget-cli latest release has no .msixbundle asset.' }
        & $probeHead $wgAsset.browser_download_url 'Winget msixbundle'

        LogOK 'GitHub assets resolved and download URLs respond (where reachable).'
    }
    catch {
        $cache = Get-WinMintOfflinePayloadCacheStatus -Architecture $TargetArch
        if ($cache.Complete) {
            LogWarn "GitHub release freshness check failed ($($_.Exception.Message)); offline payload cache is complete — continuing with cached payloads."
            return
        }
        throw
    }
}

function Invoke-DismAddDriverToImage {
    <# <summary>Offline /Add-Driver with full DISM output on failure.</summary> #>
    param(
        [ValidateNotNullOrEmpty()][string]$ImageMountPath,
        [ValidateNotNullOrEmpty()][string]$DriverSource,
        [switch]$ForceUnsigned
    )
    $arguments = @('/English', "/Image:$ImageMountPath", '/Add-Driver', "/Driver:$DriverSource", '/Recurse')
    if ($ForceUnsigned) { $arguments += '/ForceUnsigned' }
    Invoke-DismExe -Arguments $arguments | Out-Null
}

function Dismount-OfflineHive {
    param([ValidateNotNullOrEmpty()][string]$HivePath)
    # Name the hive so the several unloads per build read as distinct steps
    # (SOFTWARE, NTUSER, ...) rather than identical-looking repeated lines.
    $hiveLabel = (($HivePath -split '[\\/]')[-1] -replace '^z', '')
    Invoke-Action "Closing offline registry hive ($hiveLabel)" {
        LogVerbose "Hive: $HivePath"
        for ($a = 1; $a -le 3; $a++) {
            [GC]::Collect(); [GC]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds 500
            try {
                $null = & reg.exe unload $HivePath
                LogVerbose "Unloaded hive $HivePath"
                return
            }
            catch {
                Start-Sleep -Seconds 2
            }
        }
        throw "Failed to unload $HivePath"
    }
}

function Protect-WorkDirectory {
    param([ValidateNotNullOrEmpty()][string]$Path)
    if ($DryRun) {
        LogDry 'Would restrict the temp work folder to Administrators and SYSTEM only.'
        LogVerbose $Path
        return
    }
    Log 'Restricting access to the temp work folder…'
    LogVerbose $Path
    try {
        $acl = New-Object System.Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            'BUILTIN\Administrators', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            'NT AUTHORITY\SYSTEM', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
        Set-Acl -Path $Path -AclObject $acl
    }
    catch { LogWarn "Could not restrict permissions: $_" }
}

function Get-ArchitectureFromFilename {
    param([ValidateNotNullOrEmpty()][string]$Filename)
    $name = [IO.Path]::GetFileNameWithoutExtension($Filename)
    $matchedArm = $name -match '(?i)(arm64|aarch64)'
    $matchedX64 = $name -match '(?i)(x86[_-]?64|x64|amd64)'

    if ($matchedArm -and $matchedX64) { return $null }
    return $matchedArm ? 'arm64' : ($matchedX64 ? 'amd64' : $null)
}

# ═══════════════════════════════════════════════════════════════════════════
# BUILD PHASES
# ═══════════════════════════════════════════════════════════════════════════

function Write-Win11IsoAppxDeprovisionedEntry {
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir,
        [string[]]$PackageNames
    )
    if ($PackageNames.Count -eq 0) { return }
    $hivePath    = 'HKLM\tempDeprovSOFT'
    $softwareHive = Join-Path $MountDir 'Windows\System32\config\SOFTWARE'
    $null = & reg.exe load $hivePath $softwareHive
    try {
        foreach ($pkg in $PackageNames) {
            $keyPath = "$hivePath\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$pkg"
            $null = & reg.exe add "`"$keyPath`"" /f 2>$null
        }
        LogOK "Deprovisioned registry entries written ($($PackageNames.Count) packages)."
    } finally {
        [GC]::Collect(); [GC]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds 400
        $null = & reg.exe unload $hivePath 2>$null
    }
}

function Remove-WinMintCapabilities {
    param([ValidateNotNullOrEmpty()][string]$MountDir)
    Write-SectionHeader 'Image: capabilities and legacy features'

    $capabilities = @(
        'App.StepsRecorder~~~0.0.1.0'
        'Browser.InternetExplorer~~~~0.0.11.0'
        'MathRecognizer~~~~0.0.1.0'
        'Media.WindowsMediaPlayer~~~~0.0.12.0'
        'Microsoft.Wallpapers.Extended~~~~0.0.1.0'
        'Microsoft.Windows.WordPad~~~~0.0.1.0'
        'Microsoft.Windows.PowerShell.ISE~~~0.0.1.0'
        'Print.Fax.Scan~~~~0.0.1.0'
        'XPS.Viewer~~~0.0.1.0'
    )
    $features = @(
        'MicrosoftWindowsPowerShellV2Root'
    )

    $removed = [System.Collections.Generic.List[string]]::new()
    Invoke-Action 'Removing unused capabilities (legacy WMP, extended wallpapers, Steps Recorder, PS ISE, Fax/Scan, XPS Viewer)' {
        foreach ($cap in $capabilities) {
            try {
                Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Remove-Capability', "/CapabilityName:$cap") | Out-Null
                LogOK "Removed: $cap"
                $removed.Add($cap)
            }
            catch { LogWarn "Capability not present or already removed: $cap" }
        }
    }
    Set-WinMintManifestCapabilityRemovalFacts -CapabilityNames $removed.ToArray()

    $packagePatterns = @(
        'Microsoft-Windows-InternetExplorer-Optional-Package',
        'Microsoft-Windows-WordPad-FoD-Package',
        'Microsoft-Windows-TabletPCMath-Package'
    )
    $removedPackages = [System.Collections.Generic.List[string]]::new()
    Invoke-Action 'Removing matching legacy optional packages when present (IE, WordPad, Math Recognizer)' {
        $packageList = Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Get-Packages')
        $packageNames = @(
            $packageList.Output | ForEach-Object {
                if ("$_" -match 'Package Identity : (.*)') { $matches[1].Trim() }
            }
        )
        foreach ($packageName in $packageNames) {
            foreach ($pattern in $packagePatterns) {
                if ($packageName -like "*$pattern*") {
                    try {
                        Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Remove-Package', "/PackageName:$packageName") | Out-Null
                        LogOK "Removed package: $packageName"
                        $removedPackages.Add($packageName)
                    }
                    catch {
                        LogWarn "Package not present or already removed: $packageName"
                    }
                    break
                }
            }
        }
    }
    Set-WinMintManifestWindowsPackageRemovalFacts -PackageNames $removedPackages.ToArray()

    Invoke-Action 'Disabling PowerShell 2.0 (pre-AMSI engine; no legitimate use on modern hardware)' {
        foreach ($feature in $features) {
            try {
                Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Disable-Feature', "/FeatureName:$feature", '/Remove') | Out-Null
                LogOK "Disabled: $feature"
            }
            catch { LogWarn "Feature not present or already disabled: $feature" }
        }
    }
}

function Remove-WinMintOneDriveSetupStub {
    param([ValidateNotNullOrEmpty()][string]$MountDir)

    Write-SectionHeader 'Image: OneDrive first-run setup stubs'

    $removed = [System.Collections.Generic.List[string]]::new()
    $notFound = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[object]]::new()
    $relativePaths = @(
        'Windows\System32\OneDriveSetup.exe',
        'Windows\SysWOW64\OneDriveSetup.exe',
        'Windows\System32\OneDriveSetup.exe.bak',
        'Windows\SysWOW64\OneDriveSetup.exe.bak'
    )

    Invoke-Action 'Removing bundled OneDrive setup stubs while preserving manual reinstall support' {
        LogVerbose "Mount: $MountDir"
        foreach ($relativePath in $relativePaths) {
            $setupFile = Join-Path $MountDir $relativePath
            if (-not (Test-Path -LiteralPath $setupFile)) {
                $notFound.Add($relativePath) | Out-Null
                LogVerbose "OneDrive setup stub not present: $relativePath"
                continue
            }

            try {
                $null = & takeown.exe /f $setupFile 2>$null
                $null = & icacls.exe $setupFile /grant 'Administrators:F' /C 2>$null
                Remove-Item -LiteralPath $setupFile -Force -ErrorAction Stop
                $removed.Add($relativePath) | Out-Null
                LogOK "Removed OneDrive setup stub: $relativePath"
            }
            catch {
                $failed.Add([ordered]@{
                    path = $relativePath
                    error = $_.Exception.Message
                }) | Out-Null
                LogWarn "Could not remove OneDrive setup stub ${relativePath}: $($_.Exception.Message)"
            }
        }
    }

    Set-WinMintManifestOneDriveSetupStubRemovalFacts `
        -Removed $removed.ToArray() `
        -NotFound $notFound.ToArray() `
        -Failed $failed.ToArray()
}

function Invoke-AppxRemoval {
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir,
        [string[]]$PackagePrefixes = $script:AppxBloatware,
        [string[]]$AiPackagePrefixes = @()
    )
    Write-SectionHeader 'Image: optional apps'
    Invoke-Action 'Removing optional preinstalled Store apps from the image' {
        LogVerbose "Mount: $MountDir"
        $list = Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Get-ProvisionedAppxPackages')
        $packages = $list.Output | ForEach-Object { if ("$_" -match 'PackageName : (.*)') { $matches[1].Trim() } }
        $removed = 0
        $removedNames = [System.Collections.Generic.List[string]]::new()
        foreach ($pkg in $packages) {
            foreach ($prefix in $PackagePrefixes) {
                if ($pkg -like "*$prefix*") {
                    try {
                        Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Remove-ProvisionedAppxPackage', "/PackageName:$pkg") | Out-Null
                        $removedNames.Add($pkg)
                        $removed++
                    }
                    catch { LogWarn "Could not remove package $pkg" }
                    break
                }
            }
        }
        LogOK "Optional apps pass finished ($removed package(s) removed)."
        $aiRemoved = @(
            if (@($AiPackagePrefixes).Count -gt 0) {
                foreach ($name in @($removedNames)) {
                    if (Test-WinMintNameMatchesAnyPrefix -Name ([string]$name) -Prefixes @($AiPackagePrefixes)) {
                        [string]$name
                    }
                }
            }
        )
        Set-WinMintManifestAppxRemovalFacts `
            -RemovedPackageNames $removedNames.ToArray() `
            -RemovedCount $removed `
            -AiRemovedPackageNames $aiRemoved
        if ($removedNames.Count -gt 0) {
            Write-Win11IsoAppxDeprovisionedEntry -MountDir $MountDir -PackageNames $removedNames.ToArray()
        }
    }
}

