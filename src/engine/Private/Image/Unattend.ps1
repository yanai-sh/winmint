#Requires -Version 7.3

function Assert-WinMintAgentToolSources {
    # WinMint installs first-logon tools exclusively through winget. Validate the
    # catalog at build time so an unsupported source fails the build here, with a
    # clear message, rather than silently failing per-tool on the user's first
    # logon. github/store are documented in packages.json's sourcePolicy as
    # reserved rationale, but are not implemented.
    param([Parameter(Mandatory)][string]$ManifestPath)

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $manifest.PSObject.Properties['tools']) { return }
    foreach ($toolProp in $manifest.tools.PSObject.Properties) {
        $toolSource = [string]$toolProp.Value.source
        if (-not [string]::IsNullOrWhiteSpace($toolSource) -and $toolSource -ne 'winget') {
            throw "Unsupported install source '$toolSource' for tool '$($toolProp.Name)' in packages.json. WinMint only supports the 'winget' install source."
        }
    }
}

function New-WinMintAgentProfile {
    param([Parameter(Mandatory)]$BuildConfig)

    $normalizeWslDistro = {
        param([string]$Distro)
        switch -Regex ($Distro) {
            '^Ubuntu-\d+\.\d+$'     { 'Ubuntu'; break }
            '^FedoraLinux-\d+$'     { 'FedoraLinux'; break }
            default                 { $Distro }
        }
    }
    $wslDistros = @(
        @($BuildConfig.Wsl2Distros) |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and [string]$_ -ne 'None' } |
            ForEach-Object { ([string]$_) -split ',' } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and [string]$_ -ne 'None' } |
            ForEach-Object { & $normalizeWslDistro ([string]$_).Trim() } |
            Select-Object -Unique
    )
    if ($wslDistros.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($BuildConfig.Wsl2Distro) -and $BuildConfig.Wsl2Distro -ne 'None') {
        $wslDistros = @([string]$BuildConfig.Wsl2Distro -split ',' | ForEach-Object { & $normalizeWslDistro ([string]$_).Trim() } | Where-Object { $_ -and $_ -ne 'None' } | Select-Object -Unique)
    }
    $wslDistro = if ($wslDistros.Count -eq 0) { 'None' } elseif ($wslDistros.Count -eq 1) { $wslDistros[0] } else { $wslDistros -join ',' }
    $needsPackageManagers = (
        @($BuildConfig.Editors).Count -gt 0 -or
        [bool]$BuildConfig.InstallWindhawk -or
        [bool]$BuildConfig.InstallYasb -or
        [bool]$BuildConfig.InstallKomorebi
    )
    $needsFlowEverything = [bool]$BuildConfig.InstallFlowEverything
    $needsRaycast = [bool]$BuildConfig.InstallRaycast
    if ($needsFlowEverything -or $needsRaycast) { $needsPackageManagers = $true }
    [ordered]@{
        profile = [string]$BuildConfig.Profile
        editors = @($BuildConfig.Editors)
        modules = [ordered]@{
            packageManagers = [ordered]@{ enabled = $needsPackageManagers }
            git = [ordered]@{
                enabled = $false
                defaultBranch = 'main'
                credentialHelper = 'manager'
            }
            dotfiles = [ordered]@{
                enabled = $false
                repository = ''
                installScript = ''
            }
            wsl = [ordered]@{
                enabled = ($wslDistros.Count -gt 0)
                distro = $wslDistro
                distros = @($wslDistros)
            }
            # Optional launcher + instant file search.
            flowEverything = [ordered]@{ enabled = $needsFlowEverything }
            raycast = [ordered]@{ enabled = $needsRaycast }
            liveInstallAudit = [ordered]@{ enabled = [bool]$BuildConfig.LiveInstallAudit }
            phoneLink = [ordered]@{
                enabled = [bool]$BuildConfig.PhoneLink
                showInFileExplorer = [bool]$BuildConfig.PhoneLink
                crossDeviceCopyPaste = [bool]$BuildConfig.PhoneLink
                hideCrossDeviceHomeFolder = [bool]$BuildConfig.PhoneLink
            }
            shell = [ordered]@{
                komorebi = [bool]$BuildConfig.InstallKomorebi
                yasb = [bool]$BuildConfig.InstallYasb
                whkd = [bool]$BuildConfig.InstallKomorebi
            }
            windhawk = [ordered]@{ enabled = [bool]$BuildConfig.InstallWindhawk }
        }
    }
}

function New-WinMintSetupProfile {
    param([Parameter(Mandatory)]$BuildConfig)

    [ordered]@{
        schemaVersion = 2
        profile = [string]$BuildConfig.Profile
        appxRemovalPrefixes = @($BuildConfig.AppxPackages)
        appxCatalogVersion = [int]$BuildConfig.AppxCatalogVersion
        registryTweaks = @($BuildConfig.RegistryTweaks)
        windowsFeatures = @($BuildConfig.Features)
        defaultUser = [ordered]@{
            darkMode = $true
            stickyKeysOff = [bool]$BuildConfig.Tweaks.StickyKeys
        }
        setupComplete = [ordered]@{
            preserveWindowsUpdate = ([string]$BuildConfig.Tweaks.UpdatePolicy -eq 'All')
            disableVirtualDesktopFlyout = [bool]$BuildConfig.InstallWindhawk
            removeRecall = $true
        }
        aiRemoval = [ordered]@{
            policy = [string]$BuildConfig.AiRemoval.Policy
            catalogVersion = [int]$BuildConfig.AiRemoval.CatalogVersion
            appxPrefixes = @($BuildConfig.AiRemoval.AppxPrefixes)
            removeRecall = $true
            disableAiServices = (@($BuildConfig.AiRemoval.ServicesToDisable).Count -gt 0)
            disableAiTasks = $true
            aggressiveExperimental = [bool]$BuildConfig.AiRemoval.AggressiveExperimental
            optionalFeatures = @($BuildConfig.AiRemoval.OptionalFeatures)
            servicesToDisable = @($BuildConfig.AiRemoval.ServicesToDisable)
            scheduledTaskPatternsToDisable = @($BuildConfig.AiRemoval.ScheduledTaskPatternsToDisable)
        }
        windowsPolicy = [ordered]@{
            dualBoot = ([string]$BuildConfig.DiskMode -eq 'DualBootReserved')
            disableFastStartup = ([string]$BuildConfig.DiskMode -eq 'DualBootReserved')
            preventDeviceEncryption = ([string]$BuildConfig.DiskMode -eq 'DualBootReserved')
            disableWpbtExecution = $true
            realTimeIsUniversal = ([string]$BuildConfig.DiskMode -eq 'DualBootReserved')
            primaryAssumption = [string]$BuildConfig.PrimaryAssumption
        }
        regional = [ordered]@{
            timeZoneId = [string]$BuildConfig.TimeZoneId
            dmaInterop = [ordered]@{
                enabled = [bool]$BuildConfig.DmaInterop.Enabled
                setupCountry = [string]$BuildConfig.DmaInterop.SetupCountry
                setupUserLocale = [string]$BuildConfig.SetupUserLocale
                setupHomeLocationGeoId = [int]$BuildConfig.SetupHomeLocationGeoId
                restoreTimeZoneId = [string]$BuildConfig.TimeZoneId
                restoreUserLocale = [string]$BuildConfig.UserLocale
                restoreHomeLocationGeoId = [int]$BuildConfig.HomeLocationGeoId
                restoreLocationServices = [bool]$BuildConfig.DmaInterop.RestoreLocationServices
            }
        }
        privacy = [ordered]@{
            telemetry = [bool]$BuildConfig.Privacy.Telemetry
            advertisingId = [bool]$BuildConfig.Privacy.AdvertisingId
            location = [bool]$BuildConfig.Privacy.Location
            timeline = [bool]$BuildConfig.Privacy.Timeline
            disableTelemetryTasks = [bool]$BuildConfig.Privacy.Telemetry
            telemetryTaskPatternsToDisable = @($BuildConfig.TelemetryTaskPatterns)
        }
        power = [ordered]@{
            formFactor = [string]$BuildConfig.FormFactor
            dualBoot = ([string]$BuildConfig.DiskMode -eq 'DualBootReserved')
            disableHibernationOnDesktop = $true
            desktopPowerPlan = 'HighPerformance'
        }
        edge = [ordered]@{
            # Edge browser is removed by default via the DMA-supported in-OS
            # uninstall, which only works while the device is still in the EEA
            # setup region (DMA interop on). With -KeepEdge or -NoDmaInterop there
            # is no EULA-blessed path, so removal is skipped and logged.
            removeEdge = ((-not [bool]$BuildConfig.Keep.Edge) -and [bool]$BuildConfig.DmaInterop.Enabled)
            keepEdge = [bool]$BuildConfig.Keep.Edge
            dmaInteropEnabled = [bool]$BuildConfig.DmaInterop.Enabled
        }
    }
}

function New-WinMintSetupPlan {
    param(
        [Parameter(Mandatory)]$BuildConfig,
        [Parameter(Mandatory)]$SetupProfile,
        [Parameter(Mandatory)]$AgentProfile
    )

    $diskMode = [string]$BuildConfig.DiskMode
    $accountMode = [string]$BuildConfig.AccountMode
    $firstLogonModules = [System.Collections.Generic.List[string]]::new()
    foreach ($module in @($AgentProfile.modules.PSObject.Properties.Name)) {
        $value = $AgentProfile.modules.$module
        $enabled = $false
        if ($value -is [bool]) {
            $enabled = [bool]$value
        }
        elseif ($value -and $value.PSObject.Properties['enabled']) {
            $enabled = [bool]$value.enabled
        }
        elseif ($module -eq 'shell' -and $value) {
            $enabled = [bool]$value.komorebi -or [bool]$value.yasb -or [bool]$value.whkd
        }
        if ($enabled) { $firstLogonModules.Add($module) | Out-Null }
    }
    if (@($BuildConfig.Editors).Count -gt 0) { $firstLogonModules.Add('editors') | Out-Null }

    [ordered]@{
        schemaVersion = 2
        profile = [string]$BuildConfig.Profile
        generatedBy = 'WinMint backend'
        accountMode = $accountMode
        editionMode = [string]$BuildConfig.EditionMode
        diskMode = $diskMode
        phases = @(
            [ordered]@{
                id = 'windowsPE'
                context = 'Windows PE'
                entrypoint = 'autounattend.xml RunSynchronous'
                responsibilities = @(
                    'apply optional hardware compatibility bypass',
                    'prepare disk layout when automated disk mode is selected',
                    'hand Windows Setup the selected edition policy'
                )
            }
            [ordered]@{
                id = 'specialize'
                context = 'SYSTEM before first user'
                entrypoint = 'C:\Windows\Setup\Scripts\Specialize.ps1'
                responsibilities = @(
                    'apply machine policy that must exist before OOBE',
                    'load setup profile from WinMintSetupProfile.json'
                )
            }
            [ordered]@{
                id = 'setupComplete'
                context = 'SYSTEM after Windows Setup'
                entrypoint = 'C:\Windows\Setup\Scripts\SetupComplete.cmd'
                responsibilities = @(
                    'run SetupComplete.ps1',
                    'finish machine-level cleanup',
                    'keep Windows Update and serviceability infrastructure intact'
                )
            }
            [ordered]@{
                id = 'defaultUser'
                context = 'Default user registry hive'
                entrypoint = 'C:\Windows\Setup\Scripts\DefaultUser.ps1'
                responsibilities = @(
                    'apply HKCU defaults for newly-created users',
                    'keep known folders local',
                    'remove default-user first-run pressure'
                )
            }
            [ordered]@{
                id = 'firstLogon'
                context = 'Live user at first sign-in'
                entrypoint = 'C:\Windows\Setup\Scripts\FirstLogon.ps1'
                responsibilities = @(
                    'clear autologon residue',
                    'run WinMintAgent',
                    'write retry/audit state',
                    'finish live-user package and shell setup'
                )
            }
        )
        stagedArtifacts = @(
            'autounattend.xml',
            'C:\Windows\Setup\Scripts\WinMintSetupProfile.json',
            'C:\Windows\Setup\Scripts\Specialize.ps1',
            'C:\Windows\Setup\Scripts\DefaultUser.ps1',
            'C:\Windows\Setup\Scripts\SetupComplete.cmd',
            'C:\Windows\Setup\Scripts\SetupComplete.ps1',
            'C:\Windows\Setup\Scripts\FirstLogon.ps1',
            'C:\Windows\Setup\Scripts\WinMintAgent\BuildProfile.json'
        )
        generatedProfiles = [ordered]@{
            setupProfile = $SetupProfile
            agentProfile = $AgentProfile
        }
        firstLogon = [ordered]@{
            modules = @($firstLogonModules | Select-Object -Unique)
            editors = @($BuildConfig.Editors)
            wslDistros = @($BuildConfig.Wsl2Distros)
        }
        notes = @(
            'UI and CLI must treat this plan as backend output; neither should duplicate setup-phase business logic.',
            $(if ([bool]$BuildConfig.DmaInterop.Enabled) {
                    'Windows setup uses an EEA region for opt-in DMA interoperability, disables automatic time-zone updates, then FirstLogon restores the configured regional defaults.'
                } else {
                    'DMA interoperability setup-region override is disabled; setup uses the configured regional defaults.'
                }),
            'OneDrive is not offered or auto-provisioned by default; manual reinstall remains possible after setup.'
        )
    }
}

function Get-WinMintDualBootWindowsRatio {
    param([string]$Preset)

    switch ($Preset) {
        'WindowsHeavy' { 0.70; break }
        'Balanced'     { 0.60; break }
        'EvenSplit'    { 0.50; break }
        'LinuxHeavy'   { 0.40; break }
        default        { throw "Unsupported dual-boot preset: $Preset" }
    }
}

function New-WinMintWindowsOnlyDiskpartPowerShellCommand {
    param([Parameter(Mandatory)]$DiskLayout)

    $windowsMinimumGb = [int](Get-WinMintProfileSetting $DiskLayout 'windowsMinimumGb' 256)
    $efiMb = [int](Get-WinMintProfileSetting $DiskLayout 'efiMb' 1024)
    $msrMb = [int](Get-WinMintProfileSetting $DiskLayout 'msrMb' 16)
    $recoveryMb = [int](Get-WinMintProfileSetting $DiskLayout 'recoveryMb' 1024)

    $script = @"
`$ErrorActionPreference='Stop';
`$disk=Get-Disk -Number 0;
`$totalMb=[math]::Floor(`$disk.Size/1MB);
`$usableMb=[int](`$totalMb-$efiMb-$msrMb-$recoveryMb);
if (`$usableMb -lt ($windowsMinimumGb*1024)) { throw "Windows partition would be `$([math]::Floor(`$usableMb/1024)) GB; minimum is $windowsMinimumGb GB." }
@(
'select disk 0',
'clean',
'convert gpt',
'create partition efi size=$efiMb',
'format quick fs=fat32 label=ESP',
'create partition msr size=$msrMb',
'create partition primary',
'format quick fs=ntfs label=WINMINT',
'shrink minimum=$recoveryMb desired=$recoveryMb',
'create partition primary size=$recoveryMb',
'format quick fs=ntfs label=WinRE',
'set id=de94bba4-06d1-4d40-a16a-bfd50179d6ac',
'gpt attributes=0x8000000000000001'
) | Set-Content -LiteralPath 'X:\winmint_dp.txt' -Encoding ASCII;
diskpart.exe /s X:\winmint_dp.txt
"@
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script))
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
}

function New-WinMintDualBootDiskpartPowerShellCommand {
    param([Parameter(Mandatory)]$DiskLayout)

    $preset = [string](Get-WinMintProfileSetting $DiskLayout 'preset' '')
    $ratio = Get-WinMintDualBootWindowsRatio -Preset $preset
    $roundingGb = [int](Get-WinMintProfileSetting $DiskLayout 'roundingGb' 64)
    $windowsMinimumGb = [int](Get-WinMintProfileSetting $DiskLayout 'windowsMinimumGb' 256)
    $linuxMinimumGb = [int](Get-WinMintProfileSetting $DiskLayout 'linuxMinimumGb' 128)
    $efiMb = [int](Get-WinMintProfileSetting $DiskLayout 'efiMb' 1024)
    $msrMb = [int](Get-WinMintProfileSetting $DiskLayout 'msrMb' 16)
    $recoveryMb = [int](Get-WinMintProfileSetting $DiskLayout 'recoveryMb' 1024)

    $script = @"
`$ErrorActionPreference='Stop';
`$disk=Get-Disk -Number 0;
`$totalGb=[math]::Floor(`$disk.Size/1GB);
`$reservedGb=[math]::Ceiling(($efiMb+$msrMb+$recoveryMb)/1024);
`$usableGb=`$totalGb-`$reservedGb;
`$windowsGb=[math]::Round((`$usableGb*$ratio)/$roundingGb,0,[System.MidpointRounding]::AwayFromZero)*$roundingGb;
if (`$windowsGb -lt $windowsMinimumGb) { throw "Windows partition would be `$windowsGb GB; minimum is $windowsMinimumGb GB." }
`$linuxGb=`$usableGb-`$windowsGb;
if (`$linuxGb -lt $linuxMinimumGb) { throw "Linux reserved space would be `$linuxGb GB; minimum is $linuxMinimumGb GB." }
`$windowsMb=[int](`$windowsGb*1024);
@(
'select disk 0',
'clean',
'convert gpt',
'create partition efi size=$efiMb',
'format quick fs=fat32 label=ESP',
'create partition msr size=$msrMb',
"create partition primary size=`$windowsMb",
'format quick fs=ntfs label=WINMINT',
'create partition primary size=$recoveryMb',
'format quick fs=ntfs label=WinRE',
'set id=de94bba4-06d1-4d40-a16a-bfd50179d6ac',
'gpt attributes=0x8000000000000001'
) | Set-Content -LiteralPath 'X:\winmint_dp.txt' -Encoding ASCII;
diskpart.exe /s X:\winmint_dp.txt
"@
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script))
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
}

function Install-Autounattend {
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir, [ValidateNotNullOrEmpty()][string]$IsoContents,
        [ValidateNotNullOrEmpty()][string]$AutounattendTemplate, [ValidateNotNullOrEmpty()][string]$ImageArch,
        [string]$TimeZone, [string]$TargetPCName, [string]$TargetUser, [ValidateSet('Local', 'MicrosoftOobe')][string]$AccountMode = 'Local', [string]$TargetPass,
        [string]$EditionName, [ValidateSet('TargetLicense', 'Fixed')][string]$EditionMode = 'TargetLicense', [string]$ProductKey = '', [int]$InstallImageCount = 0, [bool]$AutoWipeDisk, [bool]$AutoLogon,
        [object]$DiskLayout,
        [bool]$HardwareBypass = $false,
        [string]$InputLocale, [string]$SystemLocale, [string]$UILanguage, [string]$UILanguageFallback, [string]$UserLocale,
        [ValidateNotNullOrEmpty()][string]$ScriptRoot,
        [object]$AgentProfile,
        [object]$SetupProfile,
        [object]$SetupPlan,
        [switch]$DryRun
    )
    Write-SectionHeader 'Unattended setup (autounattend.xml)'

    $xmlDoc = [xml]::new()
    try { $xmlDoc.LoadXml($AutounattendTemplate) } catch { throw "Autounattend XML is invalid: $_" }

    $nsMgr = [System.Xml.XmlNamespaceManager]::new($xmlDoc.NameTable)
    $nsMgr.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')

    Log 'Updating autounattend (PC name, account, edition mode, locales, disk behavior)...'

    if ($SetupPlan -and $null -ne $script:WinMintBuildManifest) {
        $script:WinMintBuildManifest['setupPlan'] = [ordered]@{
            schemaVersion = [int]$SetupPlan.schemaVersion
            accountMode = [string]$SetupPlan.accountMode
            editionMode = [string]$SetupPlan.editionMode
            diskMode = [string]$SetupPlan.diskMode
            phases = @($SetupPlan.phases | ForEach-Object {
                [ordered]@{
                    id = [string]$_.id
                    context = [string]$_.context
                    entrypoint = [string]$_.entrypoint
                    responsibilities = @($_.responsibilities)
                }
            })
            stagedArtifacts = @($SetupPlan.stagedArtifacts)
            firstLogonModules = @($SetupPlan.firstLogon.modules)
            notes = @($SetupPlan.notes)
        }
    }

    $components = $xmlDoc.SelectNodes('//u:component', $nsMgr)
    foreach ($comp in $components) {
        if ($comp.HasAttribute('processorArchitecture')) { $comp.SetAttribute('processorArchitecture', $ImageArch) }
    }

    if ($HardwareBypass) {
        $wpSetupRunSync = $xmlDoc.SelectSingleNode(
            '//u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-Setup"]/u:RunSynchronous', $nsMgr)
        if ($wpSetupRunSync) {
            $xmlNs = 'urn:schemas-microsoft-com:unattend'
            $wcmNs = 'http://schemas.microsoft.com/WMIConfig/2002/State'
            $maxOrder = @($wpSetupRunSync.SelectNodes('u:RunSynchronousCommand/u:Order', $nsMgr) |
                ForEach-Object { [int]$_.InnerText } |
                Measure-Object -Maximum).Maximum
            $nextOrder = if ($null -ne $maxOrder) { [int]$maxOrder + 1 } else { 1 }
            foreach ($valueName in @(
                    'BypassTPMCheck',
                    'BypassSecureBootCheck',
                    'BypassCPUCheck',
                    'BypassRAMCheck',
                    'BypassStorageCheck'
                )) {
                $cmdEl = $xmlDoc.CreateElement('RunSynchronousCommand', $xmlNs)
                $null = $cmdEl.SetAttribute('action', $wcmNs, 'add')
                $orderEl = $xmlDoc.CreateElement('Order', $xmlNs); $orderEl.InnerText = "$nextOrder"
                $pathEl = $xmlDoc.CreateElement('Path', $xmlNs)
                $pathEl.InnerText = "reg.exe add `"HKLM\SYSTEM\Setup\LabConfig`" /v $valueName /t REG_DWORD /d 1 /f"
                $null = $cmdEl.AppendChild($orderEl)
                $null = $cmdEl.AppendChild($pathEl)
                $null = $wpSetupRunSync.AppendChild($cmdEl)
                $nextOrder++
            }
            LogWarn 'Hardware compatibility bypass enabled for Windows Setup checks.'
        }
        else {
            LogWarn 'Hardware compatibility bypass selected, but the windowsPE RunSynchronous block was not found.'
        }
    }

    $tzNode = $xmlDoc.SelectSingleNode('//u:TimeZone', $nsMgr)
    if ($tzNode -and $TimeZone) { $tzNode.InnerText = $TimeZone }

    Merge-UnattendInternationalXml -XmlDoc $xmlDoc -NsMgr $nsMgr -InputLocale $InputLocale -SystemLocale $SystemLocale -UILanguage $UILanguage -UILanguageFallback $UILanguageFallback -UserLocale $UserLocale

    $installFromNode = $xmlDoc.SelectSingleNode('//u:ImageInstall/u:OSImage/u:InstallFrom', $nsMgr)
    if (-not [string]::IsNullOrWhiteSpace($ProductKey)) {
        # Inject a generic edition key (VM/container ISO or keyless build host):
        # selects the edition and skips the Setup product-key page. This is NOT an
        # activating key — a real device still activates via its firmware license.
        $pkNode = $xmlDoc.SelectSingleNode('//u:UserData/u:ProductKey', $nsMgr)
        if ($pkNode) {
            $keyNode = $pkNode.SelectSingleNode('u:Key', $nsMgr)
            if (-not $keyNode) {
                $keyNode = $xmlDoc.CreateElement('Key', 'urn:schemas-microsoft-com:unattend')
                $null = $pkNode.PrependChild($keyNode)
            }
            $keyNode.InnerText = $ProductKey
            Log "Product key: injected generic key for '$EditionName' (skips the setup key page; does not activate)."
        }
    }
    else {
        # Keyless default: strip the product key so the device firmware/digital
        # license activates the matching edition on real hardware.
        foreach ($productKeyNode in @($xmlDoc.SelectNodes('//u:ProductKey', $nsMgr))) {
            $null = $productKeyNode.ParentNode.RemoveChild($productKeyNode)
        }
    }
    if ($EditionMode -eq 'Fixed') {
        $editionNode = $xmlDoc.SelectSingleNode('//u:MetaData[u:Key="/IMAGE/NAME"]/u:Value', $nsMgr)
        if ($editionNode) { $editionNode.InnerText = $EditionName }
        Log "Edition mode: fixed image selection ($EditionName) via ImageInstall metadata; activation remains the target device license."
    }
    elseif ($InstallImageCount -eq 1) {
        $xmlNs = 'urn:schemas-microsoft-com:unattend'
        if (-not $installFromNode) {
            $osImageNode = $xmlDoc.SelectSingleNode('//u:ImageInstall/u:OSImage', $nsMgr)
            if ($osImageNode) {
                $installFromNode = $xmlDoc.CreateElement('InstallFrom', $xmlNs)
                $null = $osImageNode.PrependChild($installFromNode)
            }
        }
        if ($installFromNode) {
            foreach ($metadata in @($installFromNode.SelectNodes('u:MetaData', $nsMgr))) {
                $null = $installFromNode.RemoveChild($metadata)
            }
            $metadataNode = $xmlDoc.CreateElement('MetaData', $xmlNs)
            $keyNode = $xmlDoc.CreateElement('Key', $xmlNs); $keyNode.InnerText = '/IMAGE/INDEX'
            $valueNode = $xmlDoc.CreateElement('Value', $xmlNs); $valueNode.InnerText = '1'
            $null = $metadataNode.AppendChild($keyNode)
            $null = $metadataNode.AppendChild($valueNode)
            $null = $installFromNode.AppendChild($metadataNode)
        }
        Log 'Edition mode: target license on single-image media - selecting install.wim index 1 without a product key.'
    }
    else {
        if ($installFromNode) { $null = $installFromNode.ParentNode.RemoveChild($installFromNode) }
        Log 'Edition mode: target license - Windows Setup will use the target device firmware key when available; no product key is written.'
    }

    $pcNode = $xmlDoc.SelectSingleNode('//u:ComputerName', $nsMgr)
    if ($pcNode -and $TargetPCName) { $pcNode.InnerText = $TargetPCName }

    $hideWirelessNode = $xmlDoc.SelectSingleNode('//u:OOBE/u:HideWirelessSetupInOOBE', $nsMgr)
    if ($hideWirelessNode) { $hideWirelessNode.InnerText = 'false' }
    Log 'OOBE network page remains visible so Wi-Fi can be joined before FirstLogon automation.'

    if ($AccountMode -eq 'MicrosoftOobe') {
        $bypassNroNode = $xmlDoc.SelectSingleNode('//u:RunSynchronousCommand[contains(u:Path, "BypassNRO")]', $nsMgr)
        if ($bypassNroNode) { $null = $bypassNroNode.ParentNode.RemoveChild($bypassNroNode) }
        foreach ($path in @(
                '//u:OOBE/u:HideOnlineAccountScreens',
                '//u:OOBE/u:HideLocalAccountScreen',
                '//u:UserAccounts'
            )) {
            $node = $xmlDoc.SelectSingleNode($path, $nsMgr)
            if ($node) { $null = $node.ParentNode.RemoveChild($node) }
        }
        if ($AutoLogon) {
            LogWarn 'Autologon ignored because Microsoft account OOBE lets the user create/sign in to the account interactively.'
        }
        Log 'Account mode: official OOBE — Microsoft account/local-account choice is handled by Windows Setup.'
    }
    else {
        $bypassNroNode = $xmlDoc.SelectSingleNode('//u:RunSynchronousCommand[contains(u:Path, "BypassNRO")]', $nsMgr)
        if (-not $bypassNroNode) {
            LogWarn 'Local account mode selected, but BypassNRO is missing from the unattend template.'
        }
        $userNode = $xmlDoc.SelectSingleNode('//u:LocalAccount/u:Name', $nsMgr)
        if ($userNode -and $TargetUser) { $userNode.InnerText = $TargetUser }

        $accountPasswordNode = $xmlDoc.SelectSingleNode('//u:LocalAccount/u:Password', $nsMgr)
        $passNode = $xmlDoc.SelectSingleNode('//u:LocalAccount/u:Password/u:Value', $nsMgr)
        if ($TargetPass) {
            if ($passNode) {
                $passNode.InnerText = [Convert]::ToBase64String(
                    [System.Text.Encoding]::Unicode.GetBytes($TargetPass + 'Password'))
            }
        }
        elseif ($accountPasswordNode) {
            $null = $accountPasswordNode.ParentNode.RemoveChild($accountPasswordNode)
            Log 'Local account password omitted; Windows will create a passwordless local administrator.'
        }
    }

    if ($AccountMode -eq 'Local' -and $AutoLogon -and $TargetPass) {
        $shellNode = $xmlDoc.SelectSingleNode('//u:component[@name="Microsoft-Windows-Shell-Setup"]', $nsMgr)
        if ($shellNode) {
            $xmlNs = 'urn:schemas-microsoft-com:unattend'
            $autoLogonEl = $xmlDoc.CreateElement('AutoLogon', $xmlNs)
            $passEl  = $xmlDoc.CreateElement('Password',   $xmlNs)
            $passVal = $xmlDoc.CreateElement('Value',      $xmlNs)
            $passVal.InnerText = [Convert]::ToBase64String(
                [System.Text.Encoding]::Unicode.GetBytes($TargetPass + 'Password'))
            $passPlain = $xmlDoc.CreateElement('PlainText', $xmlNs); $passPlain.InnerText = 'false'
            $null = $passEl.AppendChild($passVal); $null = $passEl.AppendChild($passPlain)
            $null = $autoLogonEl.AppendChild($passEl)
            $enabledEl = $xmlDoc.CreateElement('Enabled', $xmlNs); $enabledEl.InnerText = 'true'
            $null = $autoLogonEl.AppendChild($enabledEl)
            # One automatic logon is enough: FirstLogon.ps1 clears the plaintext password
            # immediately and registers a RunOnce retry. A LogonCount of 2 would leave
            # DefaultPassword resident across an extra reboot for no benefit.
            $countEl = $xmlDoc.CreateElement('LogonCount', $xmlNs); $countEl.InnerText = '1'
            $null = $autoLogonEl.AppendChild($countEl)
            $userEl = $xmlDoc.CreateElement('Username', $xmlNs); $userEl.InnerText = $TargetUser
            $null = $autoLogonEl.AppendChild($userEl)
            $null = $shellNode.AppendChild($autoLogonEl)
            LogOK "Autologon configured for $TargetUser."
        }
    }

    $diskLayoutMode = if ($DiskLayout) { [string](Get-WinMintProfileSetting $DiskLayout 'mode' '') } else { '' }
    if ([string]::IsNullOrWhiteSpace($diskLayoutMode)) {
        $diskLayoutMode = if ($AutoWipeDisk) { 'AutoWipeDisk0' } else { 'Manual' }
    }
    if ($AutoWipeDisk -and $null -eq $DiskLayout) {
        $DiskLayout = [ordered]@{
            mode = $diskLayoutMode
            preset = ''
            roundingGb = 64
            windowsMinimumGb = 256
            windowsRecommendedGb = 384
            linuxMinimumGb = 128
            linuxRecommendedGb = 256
            efiMb = 1024
            msrMb = 16
            recoveryMb = 1024
        }
    }

    $diskConfigNode = $xmlDoc.SelectSingleNode('//u:DiskConfiguration', $nsMgr)
    if (-not $AutoWipeDisk) {
        Log 'Disk layout: manual — standard Setup disk UI; autounattend does not clear the primary disk.'
        if ($diskConfigNode) { $null = $diskConfigNode.ParentNode.RemoveChild($diskConfigNode) }
        $installToNode = $xmlDoc.SelectSingleNode('//u:InstallTo', $nsMgr)
        if ($installToNode) { $null = $installToNode.ParentNode.RemoveChild($installToNode) }
    }
    elseif ($diskLayoutMode -eq 'AutoWipeDisk0') {
        Log 'Disk layout: native unattend wipe — EFI (1 GB) + MSR (16 MB) + Windows on the primary disk.'
    }
    else {
        if ($diskLayoutMode -eq 'DualBootReserved') {
            $preset = [string](Get-WinMintProfileSetting $DiskLayout 'preset' 'Balanced')
            Log "Disk layout: dual boot reserved ($preset) — EFI (1 GB) + MSR (16 MB) + rounded Windows + WinRE (1 GB), Linux space left unallocated."
        }
        else {
            Log 'Disk layout: automated diskpart — EFI (1 GB) + MSR (16 MB) + Windows + WinRE (1 GB) on the primary disk.'
        }
        if ($diskConfigNode) { $null = $diskConfigNode.ParentNode.RemoveChild($diskConfigNode) }
        # InstallTo (disk 0, partition 3) is retained: EFI=1, MSR=2, Windows=3, Recovery=4

        $wpSetupComp = $xmlDoc.SelectSingleNode(
            '//u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-Setup"]/u:RunSynchronous', $nsMgr)
        if ($wpSetupComp) {
            $xmlNs = 'urn:schemas-microsoft-com:unattend'
            $wcmNs = 'http://schemas.microsoft.com/WMIConfig/2002/State'
            $maxOrder = @($wpSetupComp.SelectNodes('u:RunSynchronousCommand/u:Order', $nsMgr) |
                ForEach-Object { [int]$_.InnerText } |
                Measure-Object -Maximum).Maximum
            $nextOrder = $maxOrder + 1

            $dpLines = if ($diskLayoutMode -eq 'DualBootReserved') {
                @(New-WinMintDualBootDiskpartPowerShellCommand -DiskLayout $DiskLayout)
            }
            else {
                @(New-WinMintWindowsOnlyDiskpartPowerShellCommand -DiskLayout $DiskLayout)
            }

            foreach ($line in $dpLines) {
                $cmdEl   = $xmlDoc.CreateElement('RunSynchronousCommand', $xmlNs)
                $null    = $cmdEl.SetAttribute('action', $wcmNs, 'add')
                $orderEl = $xmlDoc.CreateElement('Order', $xmlNs); $orderEl.InnerText = "$nextOrder"
                $pathEl  = $xmlDoc.CreateElement('Path',  $xmlNs); $pathEl.InnerText  = $line
                $null    = $cmdEl.AppendChild($orderEl)
                $null    = $cmdEl.AppendChild($pathEl)
                $null    = $wpSetupComp.AppendChild($cmdEl)
                $nextOrder++
            }
            LogOK 'Diskpart script (EFI + MSR + Windows + WinRE) injected into windowsPE RunSynchronous.'
        }
    }

    if ($DryRun) {
        $xmlWriterSettings = [System.Xml.XmlWriterSettings]::new()
        $xmlWriterSettings.Indent = $true
        $xmlWriterSettings.Encoding = [System.Text.UTF8Encoding]::new($false)
        $stringWriter = [System.IO.StringWriter]::new()
        $xmlWriter = [System.Xml.XmlWriter]::Create($stringWriter, $xmlWriterSettings)
        try { $xmlDoc.Save($xmlWriter) } finally { $xmlWriter.Close() }
        $autounattendXml = $stringWriter.ToString()
        LogOK 'Validated autounattend.xml generation in memory.'

        $setupProfileJson = ''
        if ($SetupProfile) {
            $setupProfileJson = $SetupProfile | ConvertTo-Json -Depth 12
            $null = $setupProfileJson | ConvertFrom-Json -ErrorAction Stop
            LogOK 'Validated setup profile JSON generation in memory.'
        }
        $agentProfileJson = ''
        if ($AgentProfile) {
            $agentProfileJson = $AgentProfile | ConvertTo-Json -Depth 12
            $null = $agentProfileJson | ConvertFrom-Json -ErrorAction Stop
            LogOK 'Validated WinMintAgent profile JSON generation in memory.'
        }
        $setupPlanJson = ''
        if ($SetupPlan) {
            $setupPlanJson = $SetupPlan | ConvertTo-Json -Depth 16
            $null = $setupPlanJson | ConvertFrom-Json -ErrorAction Stop
            LogOK 'Validated setup plan JSON generation in memory.'
        }

        Write-SectionHeader 'Autounattend summary (dry run)' -Accent Yellow -RuleColor Grey
        $autoWipeDisplay = if ($AutoWipeDisk) { '[red]Yes — repartition primary disk[/]' } else { '[green]No — manual Setup disk UI[/]' }
        $autoLogonDisplay = if ($AutoLogon) { '[green]Yes[/]' } else { '[silver]No[/]' }
        $hardwareBypassDisplay = if ($HardwareBypass) { '[yellow]Yes — unsupported hardware checks bypassed[/]' } else { '[green]No[/]' }
        Write-SpectreKeyValueTable -Title '[bold cyan3]Prepared XML (in memory only)[/]' -TableColor Grey -Rows @(
            [pscustomobject]@{ Item = 'Computer name'; Value = "[green]$TargetPCName[/]" }
            [pscustomobject]@{ Item = 'User name'; Value = "[green]$TargetUser[/]" }
            [pscustomobject]@{ Item = 'Account mode'; Value = $(if ($AccountMode -eq 'MicrosoftOobe') { '[green]Official OOBE[/]' } else { '[green]Local unattended[/]' }) }
            [pscustomobject]@{ Item = 'Edition'; Value = $(if ($EditionMode -eq 'Fixed') { "[green]$EditionName[/]" } else { '[green]Target license[/]' }) }
            [pscustomobject]@{ Item = 'Time zone'; Value = "[green]$TimeZone[/]" }
            [pscustomobject]@{ Item = 'Input locale'; Value = "[green]$InputLocale[/]" }
            [pscustomobject]@{ Item = 'System locale'; Value = "[green]$SystemLocale[/]" }
            [pscustomobject]@{ Item = 'UI language'; Value = "[green]$UILanguage[/]" }
            [pscustomobject]@{ Item = 'User locale'; Value = "[green]$UserLocale[/]" }
            [pscustomobject]@{ Item = 'Unattended clears primary disk'; Value = $autoWipeDisplay }
            [pscustomobject]@{ Item = 'Autologon'; Value = $autoLogonDisplay }
            [pscustomobject]@{ Item = 'Hardware bypass'; Value = $hardwareBypassDisplay }
        )
        return [pscustomobject]@{
            AutounattendXml = $autounattendXml
            SetupProfileJson = $setupProfileJson
            AgentProfileJson = $agentProfileJson
            SetupPlanJson = $setupPlanJson
        }
    }

    Invoke-Action 'Writing autounattend.xml and setup scripts onto the ISO' {
        LogVerbose "Mount: $MountDir | ISO staging: $IsoContents"

        $bundleDir = Join-Path $ScriptRoot 'src\setup'
        if (Test-Path -LiteralPath $bundleDir) {
            $destScripts = Join-Path $MountDir 'Windows\Setup\Scripts'
            $null = New-Item -ItemType Directory -Path $destScripts -Force -ErrorAction SilentlyContinue
            $wallpaperSrc = Join-Path $ScriptRoot 'assets\runtime\wallpaper\Bloom-wallpaper-OLED-muted.png'
            if (-not (Test-Path -LiteralPath $wallpaperSrc)) {
                throw "WinMint wallpaper asset is missing: $wallpaperSrc"
            }
            $wallpaperDir = Join-Path $MountDir 'Windows\Web\Wallpaper\WinMint'
            $null = New-Item -ItemType Directory -Path $wallpaperDir -Force -ErrorAction SilentlyContinue
            Copy-Item -LiteralPath $wallpaperSrc -Destination (Join-Path $wallpaperDir 'WinMint-Bloom-OLED.png') -Force
            LogOK 'Staged WinMint Bloom OLED wallpaper into the offline image.'
            $utf8Bom = [System.Text.UTF8Encoding]::new($true)
            foreach ($n in @('SetupComplete.cmd', 'SetupComplete.ps1', 'Specialize.ps1', 'DefaultUser.ps1', 'FirstLogon.ps1')) {
                $src = Join-Path $bundleDir $n
                if (-not (Test-Path -LiteralPath $src)) { continue }
                $destPath = Join-Path $destScripts $n
                if ($n -like '*.cmd') {
                    # Batch files must be ASCII with no BOM — a UTF-8 BOM makes cmd.exe
                    # fail on the first line.
                    [System.IO.File]::WriteAllBytes($destPath, [System.Text.Encoding]::ASCII.GetBytes((Get-Content -LiteralPath $src -Raw)))
                }
                else {
                    [System.IO.File]::WriteAllText($destPath, (Get-Content -LiteralPath $src -Raw), $utf8Bom)
                }
            }
            $setupCompleteModuleSrc = Join-Path $bundleDir 'SetupComplete'
            if (Test-Path -LiteralPath $setupCompleteModuleSrc) {
                $setupCompleteModuleDest = Join-Path $destScripts 'SetupComplete'
                $null = New-Item -ItemType Directory -Path $setupCompleteModuleDest -Force -ErrorAction SilentlyContinue
                foreach ($moduleFile in @(Get-ChildItem -LiteralPath $setupCompleteModuleSrc -Filter '*.ps1' -File)) {
                    [System.IO.File]::WriteAllText((Join-Path $setupCompleteModuleDest $moduleFile.Name), (Get-Content -LiteralPath $moduleFile.FullName -Raw), $utf8Bom)
                }
            }
            $auditSrc = Join-Path $ScriptRoot 'tools\audit\Audit-LiveInstall.ps1'
            if (Test-Path -LiteralPath $auditSrc) {
                [System.IO.File]::WriteAllText((Join-Path $destScripts 'Audit-LiveInstall.ps1'), (Get-Content -LiteralPath $auditSrc -Raw), $utf8Bom)
            }
            if ($SetupProfile) {
                $setupProfileJson = $SetupProfile | ConvertTo-Json -Depth 12
                Set-Content -LiteralPath (Join-Path $destScripts 'WinMintSetupProfile.json') -Value $setupProfileJson -Encoding UTF8
                LogOK 'Generated setup profile for specialize, SetupComplete, and FirstLogon scripts.'
            }
            if ($SetupPlan) {
                $setupPlanJson = $SetupPlan | ConvertTo-Json -Depth 16
                Set-Content -LiteralPath (Join-Path $destScripts 'WinMintSetupPlan.json') -Value $setupPlanJson -Encoding UTF8
                LogOK 'Generated setup plan for CLI/UI inspection and install-phase audit.'
            }
            $agentSrc = Join-Path $ScriptRoot 'src\agent'
            if (Test-Path -LiteralPath $agentSrc) {
                $agentDest = Join-Path $destScripts 'WinMintAgent'
                Copy-Item -LiteralPath $agentSrc -Destination $agentDest -Recurse -Force
                $pkgManifest = Get-WinMintPath -Name Config -ChildPath 'packages.json'
                if (Test-Path -LiteralPath $pkgManifest) {
                    Assert-WinMintAgentToolSources -ManifestPath $pkgManifest
                    Copy-Item -LiteralPath $pkgManifest -Destination (Join-Path $agentDest 'packages.json') -Force
                }
                if ($AgentProfile) {
                    $profileJson = $AgentProfile | ConvertTo-Json -Depth 12
                    Set-Content -LiteralPath (Join-Path $agentDest 'BuildProfile.json') -Value $profileJson -Encoding UTF8
                    LogOK 'Generated WinMintAgent profile from the selected wizard options.'
                }
                $windhawkSelected = $false
                try { $windhawkSelected = [bool]$AgentProfile.modules.windhawk.enabled } catch { $windhawkSelected = $false }
                if ($windhawkSelected) {
                    $windhawkAssetDir = Join-Path $agentDest 'Assets\Windhawk'
                    $null = New-Item -ItemType Directory -Path $windhawkAssetDir -Force
                    Copy-Item -LiteralPath (Get-WinMintPath -Name Setup -ChildPath 'WindhawkBootstrap.ps1') -Destination (Join-Path $windhawkAssetDir 'WindhawkBootstrap.ps1') -Force
                    Copy-Item -LiteralPath (Get-WinMintPath -Name Setup -ChildPath 'WindhawkBootstrap.Helpers.ps1') -Destination (Join-Path $windhawkAssetDir 'WindhawkBootstrap.Helpers.ps1') -Force
                    Copy-Item -LiteralPath (Get-WinMintPath -Name Setup -ChildPath 'DisableVirtualDesktopFlyouts.ps1') -Destination (Join-Path $windhawkAssetDir 'DisableVirtualDesktopFlyouts.ps1') -Force
                    Copy-Item -LiteralPath (Join-Path $ScriptRoot 'assets\runtime\desktop\windhawk\preset.json') -Destination (Join-Path $windhawkAssetDir 'preset.json') -Force
                    LogOK 'Staged Windhawk preset for first-logon setup.'
                }
                $yasbSelected = $false
                try { $yasbSelected = [bool]$AgentProfile.modules.shell.yasb } catch { $yasbSelected = $false }
                if ($yasbSelected) {
                    $yasbSourceDir = Join-Path $ScriptRoot 'assets\runtime\desktop\yasb'
                    $yasbAssetDir = Join-Path $agentDest 'Assets\Yasb'
                    if (-not (Test-Path -LiteralPath $yasbSourceDir)) {
                        throw "YASB preset assets are missing: $yasbSourceDir"
                    }
                    $null = New-Item -ItemType Directory -Path $yasbAssetDir -Force
                    Copy-Item -LiteralPath (Join-Path $yasbSourceDir 'config.yaml') -Destination (Join-Path $yasbAssetDir 'config.yaml') -Force
                    Copy-Item -LiteralPath (Join-Path $yasbSourceDir 'styles.css') -Destination (Join-Path $yasbAssetDir 'styles.css') -Force
                    LogOK 'Staged YASB preset for first-logon setup.'
                }
                $komorebiSelected = $false
                try { $komorebiSelected = [bool]$AgentProfile.modules.shell.komorebi } catch { $komorebiSelected = $false }
                if ($komorebiSelected) {
                    $komorebiSourceDir = Join-Path $ScriptRoot 'assets\runtime\desktop\komorebi'
                    $komorebiAssetDir = Join-Path $agentDest 'Assets\Komorebi'
                    if (-not (Test-Path -LiteralPath $komorebiSourceDir)) {
                        throw "Komorebi preset assets are missing: $komorebiSourceDir"
                    }
                    $null = New-Item -ItemType Directory -Path $komorebiAssetDir -Force
                    foreach ($name in @('komorebi.json', 'applications.json', 'whkdrc')) {
                        Copy-Item -LiteralPath (Join-Path $komorebiSourceDir $name) -Destination (Join-Path $komorebiAssetDir $name) -Force
                    }
                    LogOK 'Staged Komorebi preset for first-logon setup.'
                }
            }
            LogOK 'Copied setup scripts into the offline image (matching files only).'
        }
        else {
            throw "WinMint setup script directory is missing: $bundleDir"
        }

        $outputPath = Join-Path $IsoContents 'autounattend.xml'
        $xmlWriterSettings = [System.Xml.XmlWriterSettings]::new()
        $xmlWriterSettings.Indent = $true
        $xmlWriterSettings.Encoding = [System.Text.UTF8Encoding]::new($false)
        $xmlWriter = [System.Xml.XmlWriter]::Create($outputPath, $xmlWriterSettings)
        try { $xmlDoc.Save($xmlWriter) } finally { $xmlWriter.Close() }
        LogOK 'autounattend.xml written next to the staged ISO (ready for oscdimg).'
    }
}

function Install-WinPEUtility {
    param([ValidateNotNullOrEmpty()][string]$IsoContents, [bool]$AutoWipeDisk)
    Write-SectionHeader 'WinPE: optional disk tools'

    if ($AutoWipeDisk) {
        Log 'Skipping WinPE FormatDisk helper (automated disk layout is already enabled).'
        return
    }

    Invoke-Action 'Patching WinPE with dark theme and optional FormatDisk helper' {
        LogVerbose "ISO tree: $IsoContents"
        $bootWim = Join-Path $IsoContents 'sources\boot.wim'
        if (-not (Test-Path $bootWim)) { return }

        $null = Set-ItemProperty -Path $bootWim -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        $bootMount = Join-Path (Get-Win11IsoProcessTempPath) "Win11ISO_BootMount_$(Get-Random)"
        $null = New-Item -Path $bootMount -ItemType Directory -Force

        try {
            Mount-WinMintImage -ImagePath $bootWim -Index $script:BootWimWinPEUtilityMountIndex -MountDir $bootMount
            Log 'Applying dark theme and FormatDisk.cmd to WinPE…'
            $peSystem = Join-Path $bootMount 'Windows\System32\config\SYSTEM'
            $peSoftware = Join-Path $bootMount 'Windows\System32\config\SOFTWARE'
            $null = & reg.exe load 'HKLM\peSYSTEM' $peSystem
            try {
                $null = & reg.exe load 'HKLM\peSOFTWARE' $peSoftware
                try {
                    $null = & reg.exe add 'HKLM\peSOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' /v AppsUseLightTheme /t REG_DWORD /d 0 /f
                    $null = & reg.exe add 'HKLM\peSOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' /v SystemUsesLightTheme /t REG_DWORD /d 0 /f
                }
                finally {
                    [GC]::Collect(); [GC]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds 500
                    $null = & reg.exe unload 'HKLM\peSOFTWARE'
                }
            }
            finally {
                [GC]::Collect(); [GC]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds 500
                $null = & reg.exe unload 'HKLM\peSYSTEM'
            }

            $cmdScript = @"
@echo off
setlocal EnableDelayedExpansion
color 0B
echo ===============================================================================
echo                DEV WORKSTATION DISK SETUP (Suggested Layout)
echo ===============================================================================
echo [ EFI Boot (1GB) ]  [ MSR (16MB) ]  [ Windows C: (Remaining) ]
echo ===============================================================================
list disk | diskpart | findstr /R /C:"Disk [0-9]"
echo ===============================================================================
set /p TARGET_DISK="Select Disk Number to format (or Q to quit): "
if /I "%TARGET_DISK%"=="Q" ( exit /b )
echo select disk %TARGET_DISK% > %TEMP%\dp.txt
echo clean >> %TEMP%\dp.txt
echo convert gpt >> %TEMP%\dp.txt
echo create partition efi size=1024 >> %TEMP%\dp.txt
echo format quick fs=fat32 label="System" >> %TEMP%\dp.txt
echo create partition msr size=16 >> %TEMP%\dp.txt
echo create partition primary >> %TEMP%\dp.txt
echo format quick fs=ntfs label="Windows" >> %TEMP%\dp.txt
diskpart.exe /s %TEMP%\dp.txt >nul
del %TEMP%\dp.txt
color 0A
echo SUCCESS: Disk %TARGET_DISK% is provisioned.
pause
"@
            Set-Content -Path (Join-Path $bootMount 'Windows\System32\FormatDisk.cmd') -Value $cmdScript -Encoding ASCII -Force
            Save-WinMintImageMount -MountDir $bootMount
        }
        catch {
            LogWarn "WinPE Utility injection failed: $_"
            Dismount-WinMintImageMount -MountDir $bootMount
        }
        finally {
            $null = Remove-Item $bootMount -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
