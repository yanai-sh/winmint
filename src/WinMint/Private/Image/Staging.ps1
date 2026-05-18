#Requires -Version 7.3

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

    $dismOut = & dism.exe /English /Get-ImageInfo /ImageFile:"$ImagePath" /Index:$Index 2>&1
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
        if ($null -ne $script:DismProgressCallback) {
            & dism.exe @Arguments 2>&1 | ForEach-Object {
                $line = [string]$_
                $lines.Add($line)
                if ($line -match '\[\s*=*\s*([\d.]+)%') {
                    & $script:DismProgressCallback ([double]$Matches[1])
                }
            }
        } else {
            & dism.exe @Arguments 2>&1 | ForEach-Object { $lines.Add([string]$_) }
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
        [ValidateSet('None', 'Custom', 'Host')][string]$DriverSource = 'None',
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
    if ($DriverSource -eq 'Custom') {
        $sourcesReported++
        if ([string]::IsNullOrWhiteSpace($CustomDriverPath)) {
            LogWarn 'Custom drivers selected but no path is set.'
        }
        elseif (-not (Test-Path -LiteralPath $CustomDriverPath)) {
            LogWarn "Custom driver path not found: $CustomDriverPath"
        }
        else {
            $item = Get-Item -LiteralPath $CustomDriverPath -ErrorAction Stop
            if ($item.PSIsContainer) {
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

    # 3. Repo-bundled assets\drivers (always also a candidate). Only mention it when it has
    # contents — silent when empty AND the user already chose another source.
    $drvArchLocal = Join-Path $ScriptDirForChecks "assets\drivers\$detected"
    $drvLocal     = if (Test-Path -LiteralPath $drvArchLocal) { $drvArchLocal } else { Join-Path $ScriptDirForChecks 'assets\drivers' }
    $drvLabel     = if (Test-Path -LiteralPath $drvArchLocal) { ".\assets\drivers\$detected" } else { '.\assets\drivers' }
    $localContributes = $false
    if (Test-Path -LiteralPath $drvLocal) {
        $nInf = (Get-ChildItem -LiteralPath $drvLocal -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($nInf -ge 1) {
            LogOK "${drvLabel}: $nInf .inf file(s) will be considered."
            $localContributes = $true
        }
        else {
            $allMsis = @(Get-ChildItem -LiteralPath $drvLocal -Recurse -Filter '*.msi' -File -ErrorAction SilentlyContinue)
            $nMsi = @($allMsis | Where-Object {
                    $rel = $_.FullName.Substring($drvLocal.Length).TrimStart([char[]]@('\', '/'))
                    $top = ($rel -split '[\\/]')[0]
                    $top -notlike '_msi_extract*'
                }).Count
            if ($nMsi -ge 1) {
                LogOK "${drvLabel}: $nMsi MSI installer(s) found; the build expands them before DISM."
                $localContributes = $true
            }
            elseif ($sourcesReported -eq 0) {
                # Only flag the empty repo folder when nothing else is configured —
                # otherwise it's just an unused bundled-assets slot, not a problem.
                LogWarn "${drvLabel} exists but has no .inf or usable MSI files."
            }
        }
    }
    if ($localContributes) {
        $sourcesReported++
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
    $gh = @{
        'User-Agent'      = 'WinMint/1.0 (PowerShell offline ISO builder)'
        'Accept'          = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    Write-SectionHeader 'Dry run: web checks and ISO layout'
    Log 'Checking boot files required for the ISO…'
    $efisysRel = 'efi\microsoft\boot\efisys.bin'
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

    $cascRel = Invoke-RestMethod -Verbose:$false -Uri 'https://api.github.com/repos/microsoft/cascadia-code/releases/latest' -Headers $gh
    $cascAsset = $cascRel.assets | Where-Object name -match 'CascadiaCode-.*\.zip' | Select-Object -First 1
    if (-not $cascAsset) { throw 'Dry-run: Cascadia Code latest release has no .zip asset matching CascadiaCode-*.zip.' }
    & $probeHead $cascAsset.browser_download_url 'Cascadia zip'

    Start-Sleep -Milliseconds 150
    $viveResolved = Get-WinMintViveToolReleaseAsset -TargetArch $TargetArch -Headers $gh
    & $probeHead $viveResolved.Asset.browser_download_url "ViVeTool ($TargetArch)"

    Start-Sleep -Milliseconds 150
    $wgRel = Invoke-RestMethod -Verbose:$false -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -Headers $gh
    $wgAsset = $wgRel.assets | Where-Object { $_.name -match '\.msixbundle$' } | Select-Object -First 1
    if (-not $wgAsset) { throw 'Dry-run: winget-cli latest release has no .msixbundle asset.' }
    & $probeHead $wgAsset.browser_download_url 'Winget msixbundle'

    LogOK 'GitHub assets resolved and download URLs respond (where reachable).'
}

function Invoke-DismAddDriverToImage {
    <# <summary>Offline /Add-Driver with full DISM output on failure.</summary> #>
    param(
        [ValidateNotNullOrEmpty()][string]$ImageMountPath,
        [ValidateNotNullOrEmpty()][string]$DriverSource
    )
    Invoke-DismExe -Arguments @('/English', "/Image:$ImageMountPath", '/Add-Driver', "/Driver:$DriverSource", '/Recurse', '/ForceUnsigned') | Out-Null
}

function Dismount-OfflineHive {
    param([ValidateNotNullOrEmpty()][string]$HivePath)
    Invoke-Action 'Closing offline registry hive' {
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
        'Microsoft.Windows.PowerShell.ISE~~~0.0.1.0'
        'Print.Fax.Scan~~~~0.0.1.0'
        'XPS.Viewer~~~0.0.1.0'
    )
    $features = @(
        'MicrosoftWindowsPowerShellV2Root'
    )

    $removed = [System.Collections.Generic.List[string]]::new()
    Invoke-Action 'Removing unused capabilities (Steps Recorder, PS ISE, Fax/Scan, XPS Viewer)' {
        foreach ($cap in $capabilities) {
            try {
                Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Remove-Capability', "/CapabilityName:$cap") | Out-Null
                LogOK "Removed: $cap"
                $removed.Add($cap)
            }
            catch { LogWarn "Capability not present or already removed: $cap" }
        }
    }
    if ($null -ne $script:WinMintBuildManifest) {
        $script:WinMintBuildManifest.removals.capabilitiesRemoved = $removed.ToArray()
    }

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

    if ($null -ne $script:WinMintBuildManifest) {
        $script:WinMintBuildManifest.removals['oneDriveSetupStubs'] = [ordered]@{
            intent = 'Do not offer or auto-provision OneDrive on fresh installs; users can reinstall OneDrive later from Microsoft or winget.'
            removed = $removed.ToArray()
            notFound = $notFound.ToArray()
            failed = $failed.ToArray()
        }
    }
}

function Invoke-AppxRemoval {
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir,
        [string[]]$PackagePrefixes = $script:AppxBloatware
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
        if ($null -ne $script:WinMintBuildManifest) {
            $script:WinMintBuildManifest.removals.appxRemoved = $removedNames.ToArray()
            $script:WinMintBuildManifest.removals.appxRemovedCount = $removed
        }
        if ($removedNames.Count -gt 0) {
            Write-Win11IsoAppxDeprovisionedEntry -MountDir $MountDir -PackageNames $removedNames.ToArray()
        }
    }
}
