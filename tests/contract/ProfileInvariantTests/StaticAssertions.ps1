#Requires -Version 7.3

function Get-WinMintSetupCompleteText {
    # SetupComplete is now a thin orchestrator plus per-concern modules under
    # src\setup\SetupComplete\. Content assertions must span both.
    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add((Get-Content -LiteralPath (Join-Path $root 'src\setup\SetupComplete.ps1') -Raw))
    $moduleDir = Join-Path $root 'src\setup\SetupComplete'
    if (Test-Path -LiteralPath $moduleDir) {
        foreach ($module in @(Get-ChildItem -LiteralPath $moduleDir -Filter '*.ps1' -File | Sort-Object Name)) {
            $parts.Add((Get-Content -LiteralPath $module.FullName -Raw))
        }
    }
    return ($parts.ToArray() -join "`n")
}

function Assert-StaticUiFlowInvariants {
    $guiRoot = Join-Path $root 'apps\gui'
    $intentPath = Join-Path $guiRoot 'src\intent.rs'
    $statePath = Join-Path $guiRoot 'src\state.rs'
    $mainPath = Join-Path $guiRoot 'src\main.rs'
    $coreProfilePath = Join-Path $root 'crates\winmint-core\src\profile.rs'

    $missingRewriteFiles = @()
    foreach ($path in @($intentPath, $statePath, $mainPath, $coreProfilePath)) {
        if (-not (Test-Path -LiteralPath $path)) {
            Add-SmokeFailure "Expected GPUI contract file to exist: $path"
            $missingRewriteFiles += $path
        }
    }
    if ($missingRewriteFiles.Count -gt 0) { return }

    $intentText = Get-Content -LiteralPath $intentPath -Raw
    $stateText = Get-Content -LiteralPath $statePath -Raw
    $mainText = Get-Content -LiteralPath $mainPath -Raw
    $coreProfileText = Get-Content -LiteralPath $coreProfilePath -Raw
    if ($stateText -notmatch 'pub\s+struct\s+BuildIntent') {
        Add-SmokeFailure 'Expected GPUI state.rs to define BuildIntent.'
    }
    foreach ($requiredField in @('architecture', 'computer_name', 'account_name', 'selected_groups', 'toolkit', 'desktop_layers')) {
        if ($stateText -notmatch "\b$([regex]::Escape($requiredField))\b") {
            Add-SmokeFailure "Expected BuildIntent to contain '$requiredField'."
        }
    }

    if ($intentText -notmatch 'winmint_core::profile') {
        Add-SmokeFailure 'GPUI intent bridge must use winmint-core profile helpers.'
    }
    if ($coreProfileText -notmatch 'pub struct GuiIntentInput') {
        Add-SmokeFailure 'winmint-core must own the typed GUI intent input contract.'
    }
    foreach ($requiredKey in @('ISOPath', 'ProfileGroups', 'DesktopUiDefault', 'InstallWindhawk', 'Wsl2Distros')) {
        if ($coreProfileText -notmatch [regex]::Escape($requiredKey)) {
            Add-SmokeFailure "winmint-core GUI intent builder must emit '$requiredKey'."
        }
    }

    $removedUiTerms = @(
        ('WinMint-Legacy' + 'UI'),
        ('legacy' + '-wpf'),
        ('Wpf' + '.Ui')
    )
    foreach ($forbidden in $removedUiTerms) {
        if ($mainText -match [regex]::Escape($forbidden) -or
            $intentText -match [regex]::Escape($forbidden) -or
            $stateText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "GPUI source must not reference removed legacy UI surface '$forbidden'."
        }
    }
    foreach ($forbidden in @('Tumbleweed', 'openSUSE')) {
        if ($stateText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "GPUI state.rs must not contain '$forbidden'."
        }
    }
}

function Assert-HardwareBypassIsExplicit {
    $unattendPath = Join-Path $root 'config\autounattend.xml'
    $unattendText = Get-Content -LiteralPath $unattendPath -Raw
    foreach ($valueName in @('BypassTPMCheck', 'BypassSecureBootCheck', 'BypassRAMCheck')) {
        if ($unattendText -match [regex]::Escape($valueName)) {
            Add-SmokeFailure "autounattend.xml must not always set $valueName; hardware bypass must be injected only when selected."
        }
    }
}

function Assert-ElevationRequiredForAllRuns {
    $cliPath = Join-Path $root 'WinMint-CLI.ps1'
    $headlessPath = Join-Path $root 'src\engine\Private\Headless.ps1'
    $enginePath = Join-Path $root 'src\engine\Engine.ps1'
    $cliText = Get-Content -LiteralPath $cliPath -Raw
    $headlessText = Get-Content -LiteralPath $headlessPath -Raw
    $engineText = Get-Content -LiteralPath $enginePath -Raw

    if ($cliText -notmatch "ContainsKey\('DryRun'\)") {
        Add-SmokeFailure 'WinMint-CLI.ps1 must route -DryRun through headless mode so tests never open the interactive ISO prompt.'
    }
    if ($headlessText -match 'Test-WinMintAdministrator\)\s+-and\s+-not\s+\$DryRun') {
        Add-SmokeFailure 'Headless elevation guard must not exempt -DryRun; UUP prep and ISO inspection still require admin.'
    }
    if ($headlessText -match 'Test-WinMintAdministrator\)\s+-and\s+-not\s+\$ValidateOnly') {
        Add-SmokeFailure 'Headless elevation guard must not exempt -ValidateOnly; validation still probes DISM/source/driver state.'
    }
    if ($engineText -match 'Test-WinMintAdministrator\)\s+-and\s+-not\s+\$DryRun') {
        Add-SmokeFailure 'Engine elevation guard must not exempt -DryRun.'
    }
    if ($headlessText -notmatch 'including -DryRun, -ValidateOnly, UUP source prep, and driver checks') {
        Add-SmokeFailure 'Headless elevation error should explain that dry-run, validate-only, source prep, and driver checks all require admin.'
    }
}

function Assert-HardwareBypassUnattendGeneration {
    $template = Get-Content -LiteralPath (Join-Path $root 'config\autounattend.xml') -Raw
    $common = @{
        MountDir = 'C:\WinMint-Mount'
        IsoContents = 'C:\WinMint-Iso'
        AutounattendTemplate = $template
        ImageArch = 'amd64'
        TimeZone = 'UTC'
        TargetPCName = 'WinMint'
        TargetUser = 'dev'
        TargetPass = ''
        EditionName = 'Windows 11 Home Single Language'
        EditionMode = 'TargetLicense'
        AutoWipeDisk = $false
        AutoLogon = $false
        InputLocale = 'en-US'
        SystemLocale = 'en-US'
        UILanguage = 'en-US'
        UILanguageFallback = 'en-US'
        UserLocale = 'en-US'
        ScriptRoot = $root
        AgentProfile = $null
        SetupProfile = $null
        DryRun = $true
    }

    $plain = Install-Autounattend @common -HardwareBypass:$false
    if ([string]$plain.AutounattendXml -match 'BypassTPMCheck') {
        Add-SmokeFailure 'Expected generated default autounattend to omit hardware bypass commands.'
    }
    if ([string]$plain.AutounattendXml -match '<Key>\s*[A-Z0-9]{5}-') {
        Add-SmokeFailure 'Expected target-license autounattend to omit generic setup product keys.'
    }
    if ([string]$plain.AutounattendXml -match '<ProductKey') {
        Add-SmokeFailure 'Expected target-license autounattend to omit ProductKey entirely.'
    }

    $singleImage = Install-Autounattend @common -HardwareBypass:$false -InstallImageCount 1
    if ([string]$singleImage.AutounattendXml -notmatch '<Key>\s*/IMAGE/INDEX\s*</Key>\s*<Value>\s*1\s*</Value>') {
        Add-SmokeFailure 'Expected single-image target-license media to pin InstallFrom /IMAGE/INDEX = 1.'
    }

    $bypass = Install-Autounattend @common -HardwareBypass:$true
    foreach ($valueName in @('BypassTPMCheck', 'BypassSecureBootCheck', 'BypassCPUCheck', 'BypassRAMCheck', 'BypassStorageCheck')) {
        if ([string]$bypass.AutounattendXml -notmatch [regex]::Escape($valueName)) {
            Add-SmokeFailure "Expected generated hardware-bypass autounattend to include $valueName."
        }
    }
}

function Assert-FixedEditionSelectionIsUnambiguous {
    $pipelineText = Get-Content -LiteralPath (Join-Path $root 'src\engine\Private\Pipeline.ps1') -Raw
    if ($pipelineText -notmatch '\$matches\.Count\s+-eq\s+1') {
        Add-SmokeFailure 'Fixed edition wildcard matching must only proceed when exactly one install image matches.'
    }
    if ($pipelineText -match 'ImageName\s+-like\s+"\*\$EditionName\*"\s*\}\s*\|\s*Select-Object\s+-First\s+1') {
        Add-SmokeFailure 'Fixed edition selection must not choose the first loose wildcard match; Home and Home Single Language must stay unambiguous.'
    }
}

function Assert-MicrosoftOobeUnattendGeneration {
    $common = @{
        MountDir = 'C:\Mount'
        IsoContents = 'C:\ISO'
        AutounattendTemplate = (Get-Content -LiteralPath (Join-Path (Get-WinMintRepositoryRoot) 'config\autounattend.xml') -Raw)
        ImageArch = 'arm64'
        TimeZone = 'Israel Standard Time'
        TargetPCName = 'SL7'
        TargetUser = 'Yanai'
        AccountMode = 'MicrosoftOobe'
        TargetPass = ''
        EditionName = 'Windows 11 Home Single Language'
        EditionMode = 'TargetLicense'
        AutoWipeDisk = $true
        AutoLogon = $false
        HardwareBypass = $false
        InputLocale = 'en-US;he-IL'
        SystemLocale = 'he-IL'
        UILanguage = 'en-US'
        UILanguageFallback = 'en-US'
        UserLocale = 'he-IL'
        ScriptRoot = (Get-WinMintRepositoryRoot)
        AgentProfile = @{}
        SetupProfile = @{}
        DryRun = $true
    }

    $prepared = Install-Autounattend @common
    $xml = [string]$prepared.AutounattendXml
    foreach ($unexpected in @('BypassNRO', 'HideOnlineAccountScreens', 'HideLocalAccountScreen', '<LocalAccount')) {
        if ($xml -match [regex]::Escape($unexpected)) {
            Add-SmokeFailure "Expected Microsoft OOBE account mode to omit '$unexpected'."
        }
    }
    foreach ($expected in @('<ComputerName>SL7</ComputerName>', '<TimeZone>Israel Standard Time</TimeZone>', '<InputLocale>en-US;he-IL</InputLocale>', '<UserLocale>he-IL</UserLocale>')) {
        if ($xml -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Expected Microsoft OOBE unattend to retain '$expected'."
        }
    }
    if ($xml -notmatch '<HideWirelessSetupInOOBE>\s*false\s*</HideWirelessSetupInOOBE>') {
        Add-SmokeFailure 'Expected Microsoft OOBE account mode to keep the network page visible.'
    }
}

function Assert-LocalAccountUnattendGeneration {
    $common = @{
        MountDir = 'C:\Mount'
        IsoContents = 'C:\ISO'
        AutounattendTemplate = (Get-Content -LiteralPath (Join-Path (Get-WinMintRepositoryRoot) 'config\autounattend.xml') -Raw)
        ImageArch = 'amd64'
        TimeZone = 'UTC'
        TargetPCName = 'WinMint'
        TargetUser = 'dev'
        AccountMode = 'Local'
        TargetPass = ''
        EditionName = 'Windows 11 Home Single Language'
        EditionMode = 'TargetLicense'
        AutoWipeDisk = $false
        AutoLogon = $false
        HardwareBypass = $false
        InputLocale = 'en-US'
        SystemLocale = 'en-US'
        UILanguage = 'en-US'
        UILanguageFallback = 'en-US'
        UserLocale = 'en-US'
        ScriptRoot = (Get-WinMintRepositoryRoot)
        AgentProfile = @{}
        SetupProfile = @{}
        DryRun = $true
    }

    $prepared = Install-Autounattend @common
    $xml = [string]$prepared.AutounattendXml
    foreach ($expected in @('BypassNRO', 'HideOnlineAccountScreens', 'HideLocalAccountScreen', '<LocalAccount', '<Name>dev</Name>')) {
        if ($xml -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Expected local account mode to include '$expected'."
        }
    }
    if ($xml -notmatch '<HideWirelessSetupInOOBE>\s*false\s*</HideWirelessSetupInOOBE>') {
        Add-SmokeFailure 'Expected local account mode to keep the network page visible.'
    }
}

function Assert-SetupCompleteDoesNotDecryptBitLocker {
    $setupCompleteText = Get-WinMintSetupCompleteText
    if ($setupCompleteText -match '\bDisable-BitLocker\b') {
        Add-SmokeFailure 'SetupComplete.ps1 must not silently disable BitLocker; WinMint should only prevent surprise auto-encryption.'
    }
    if ($setupCompleteText -notmatch 'Leaving active BitLocker protection enabled') {
        Add-SmokeFailure 'SetupComplete.ps1 should log when active BitLocker protection is detected and preserved.'
    }
}

function Assert-ServiceabilityGuardrails {
    $packagesPath = Join-Path $root 'src\engine\Private\Image\Packages.ps1'
    $packagesText = Get-Content -LiteralPath $packagesPath -Raw
    if ($packagesText -match '/ResetBase') {
        Add-SmokeFailure 'Default image cleanup must not use /ResetBase; it removes component rollback and is only acceptable in an explicit tiny-image mode.'
    }

    $unattendTemplate = Get-Content -LiteralPath (Join-Path $root 'config\autounattend.xml') -Raw
    if ($unattendTemplate -match '<Compact>\s*true\s*</Compact>' -or $unattendTemplate -match '\bCompactOS\b') {
        Add-SmokeFailure 'Default autounattend must not force Compact OS; WinMint is performance-first, not smallest-possible.'
    }

    $common = @{
        MountDir = 'C:\WinMint-Mount'
        IsoContents = 'C:\WinMint-Iso'
        AutounattendTemplate = $unattendTemplate
        ImageArch = 'amd64'
        TimeZone = 'UTC'
        TargetPCName = 'WinMint'
        TargetUser = 'dev'
        TargetPass = 'passw0rd!'
        EditionName = 'Windows 11 Home Single Language'
        EditionMode = 'Fixed'
        AutoWipeDisk = $false
        AutoLogon = $true
        HardwareBypass = $false
        InputLocale = 'en-US'
        SystemLocale = 'en-US'
        UILanguage = 'en-US'
        UILanguageFallback = 'en-US'
        UserLocale = 'en-US'
        ScriptRoot = $root
        AgentProfile = $null
        SetupProfile = $null
        DryRun = $true
    }
    $withAutoLogon = Install-Autounattend @common
    $xmlText = [string]$withAutoLogon.AutounattendXml
    if ($xmlText -match '<LogonCount>\s*9999999\s*</LogonCount>') {
        Add-SmokeFailure 'Generated autounattend must not use effectively infinite AutoLogon.'
    }
    if ($xmlText -notmatch '<LogonCount>\s*1\s*</LogonCount>') {
        Add-SmokeFailure 'Generated autounattend should use one automatic logon; FirstLogon handles retry state.'
    }
    if ($xmlText -match '<Key>\s*[A-Z0-9]{5}-') {
        Add-SmokeFailure 'Fixed-edition autounattend should select images with /IMAGE/NAME metadata, not generic setup keys.'
    }
    if ($xmlText -notmatch '<Key>\s*/IMAGE/NAME\s*</Key>' -or $xmlText -notmatch '<Value>\s*Windows 11 Home Single Language\s*</Value>') {
        Add-SmokeFailure 'Fixed Windows 11 Home Single Language autounattend should select the image with official ImageInstall metadata.'
    }
}

function Assert-ProtectedPlatformPackagesArePreserved {
    $allRemovalPrefixes = @(Get-WinMintEffectiveAppxRemovalPrefix -Settings @{
            RemoveAdvertising = $true
            RemoveGaming = $true
            RemoveCommunication = $true
            RemoveMicrosoftApps = $true
        })
    foreach ($protectedPrefix in @(
            'Microsoft.DesktopAppInstaller',
            'Microsoft.WindowsStore',
            'Microsoft.StorePurchaseApp',
            'Microsoft.SecHealthUI',
            'Microsoft.ScreenSketch',
            'Microsoft.Windows.Photos',
            'Microsoft.Paint',
            'Microsoft.YourPhone',
            'MicrosoftWindows.CrossDevice',
            'Microsoft.Edge',
            'Microsoft.EdgeWebView',
            'Microsoft.WebView2'
        )) {
        if ($allRemovalPrefixes -contains $protectedPrefix) {
            Add-SmokeFailure "Default AppX removal must preserve platform/useful package '$protectedPrefix'."
        }
    }
}

function Assert-MinimalAppxRemovalCatalogCoversPolicy {
    $allRemovalPrefixes = @(Get-WinMintEffectiveAppxRemovalPrefix -Settings @{
            RemoveAdvertising = $true
            RemoveGaming = $true
            RemoveCommunication = $true
            RemoveMicrosoftApps = $true
        })
    foreach ($expected in @(
            'Microsoft.Copilot',
            'MicrosoftWindows.Client.WebExperience',
            'Microsoft.GamingApp',
            'Microsoft.XboxGameOverlay',
            'Microsoft.XboxGamingOverlay',
            'Microsoft.XboxIdentityProvider',
            'Microsoft.XboxSpeechToTextOverlay',
            'Microsoft.Xbox.TCUI',
            'MSTeams',
            'MicrosoftTeams',
            'Clipchamp.Clipchamp',
            'Microsoft.MicrosoftSolitaireCollection',
            'Microsoft.Windows.DevHome',
            'Microsoft.OutlookForWindows',
            'Microsoft.PowerAutomateDesktop',
            'Microsoft.ZuneMusic',
            'Microsoft.ZuneVideo',
            'Microsoft.Office.OneNote',
            'Microsoft.RemoteDesktop',
            'Microsoft.RemoteDesktopPreview'
        )) {
        if ($allRemovalPrefixes -notcontains $expected) {
            Add-SmokeFailure "Expected Minimal AppX removal catalog to include '$expected'."
        }
    }
    foreach ($candidateOnly in @('McAfee', 'NortonLifeLock', 'ExpressVPN', 'Surfshark', 'Piriform.CCleaner')) {
        if ($allRemovalPrefixes -contains $candidateOnly) {
            Add-SmokeFailure "DMA-on default AppX removal must not include broad third-party/OEM candidate '$candidateOnly'."
        }
    }

    $catalogPath = Join-Path $root 'config\appx-removal.json'
    $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
    foreach ($groupName in @('consumerThirdParty', 'oemConsumer')) {
        if (@($catalog.candidateOnlyGroups) -notcontains $groupName) {
            Add-SmokeFailure "AppX removal catalog should keep '$groupName' as a candidate-only group for non-DMA/OEM drift."
        }
    }
    foreach ($candidateOnly in @('McAfee', 'NortonLifeLock', 'ExpressVPN', 'Surfshark', 'Piriform.CCleaner')) {
        if (@($catalog.groups.consumerThirdParty) -notcontains $candidateOnly -and @($catalog.groups.oemConsumer) -notcontains $candidateOnly) {
            Add-SmokeFailure "Candidate AppX catalog should retain non-default fallback prefix '$candidateOnly'."
        }
    }
}

function Assert-PhoneLinkAgentDefaults {
    $profile = New-WinMintAgentProfile -BuildConfig (New-WinMintBuildConfig -BuildProfile (New-SmokeBuildProfile))
    if ([bool]$profile.modules.phoneLink.enabled) {
        Add-SmokeFailure 'Phone Link must be disabled by default in the agent profile; users opt in explicitly.'
    }
    $optInSettings = New-SmokeBuildProfileSettings
    $optInSettings.PhoneLink = $true
    $optInProfile = New-WinMintAgentProfile -BuildConfig (New-WinMintBuildConfig -BuildProfile (New-WinMintBuildProfile -Settings $optInSettings))
    if (-not [bool]$optInProfile.modules.phoneLink.enabled) {
        Add-SmokeFailure 'Phone Link opt-in should enable the agent module.'
    }
    foreach ($setting in @('showInFileExplorer', 'crossDeviceCopyPaste', 'hideCrossDeviceHomeFolder')) {
        if ([bool]$profile.modules.phoneLink.$setting) {
            Add-SmokeFailure "Phone Link default profile should leave '$setting' disabled."
        }
        if (-not [bool]$optInProfile.modules.phoneLink.$setting) {
            Add-SmokeFailure "Phone Link opt-in profile should enable '$setting'."
        }
    }

    $agentPath = Join-Path $root 'src\agent\Modules\PhoneLink.ps1'
    $agentText = Get-Content -LiteralPath $agentPath -Raw
    foreach ($expected in @('CrossDevice', 'Hidden', 'System', 'EnableClipboardHistory', 'CloudClipboardAutomaticUpload')) {
        if ($agentText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Phone Link agent module should contain '$expected'."
        }
    }
}

function Assert-ConsumerUtilityPackagesNeverInRemovalList {
    $allRemovalPrefixes = @(Get-WinMintEffectiveAppxRemovalPrefix -Settings @{
            RemoveAdvertising = $true
            RemoveGaming = $true
            RemoveCommunication = $true
            RemoveMicrosoftApps = $true
        })
    foreach ($mustKeep in @(
            'Microsoft.WindowsCamera',
            'Microsoft.WindowsSoundRecorder',
            'Microsoft.MicrosoftStickyNotes',
            'Microsoft.WindowsAlarms',
            'Microsoft.WindowsNotepad',
            'Microsoft.DesktopAppInstaller',
            'Microsoft.WindowsStore',
            'Microsoft.StorePurchaseApp',
            'Microsoft.SecHealthUI',
            'Microsoft.ScreenSketch',
            'Microsoft.Windows.Photos',
            'Microsoft.Paint',
            'Microsoft.YourPhone',
            'MicrosoftWindows.CrossDevice',
            'Microsoft.Edge',
            'Microsoft.EdgeWebView',
            'Microsoft.WebView2'
        )) {
        foreach ($prefix in $allRemovalPrefixes) {
            if ($mustKeep -like "*$prefix*") {
                Add-SmokeFailure "AppX removal prefix '$prefix' must not match protected utility '$mustKeep'."
            }
        }
    }
}

function Assert-HomeFirstDefaultsAndPolicySurface {
    $defaultProfile = New-WinMintBuildProfile -Settings (New-SmokeBuildProfileSettings)
    $defaultConfig = New-WinMintBuildConfig -BuildProfile $defaultProfile

    if ([int]$defaultProfile.schemaVersion -ne 2) {
        Add-SmokeFailure 'Default generated profile must use schemaVersion 2.'
    }
    if ($defaultProfile.regional.uiLanguage -ne 'en-US' -or
        $defaultProfile.regional.uiLanguageFallback -ne 'en-US' -or
        $defaultProfile.regional.systemLocale -ne 'en-US' -or
        $defaultProfile.regional.userLocale -ne 'en-US' -or
        $defaultProfile.regional.inputLocale -ne 'en-US' -or
        [int]$defaultProfile.regional.homeLocationGeoId -ne 244) {
        Add-SmokeFailure 'Default generated profile must use en-US regional defaults and GeoID 244.'
    }
    if (-not [bool]$defaultProfile.tweaks.dmaInterop -or
        -not [bool]$defaultConfig.DmaInterop.Enabled -or
        $defaultConfig.SetupUserLocale -ne 'en-IE' -or
        [int]$defaultConfig.SetupHomeLocationGeoId -ne 68) {
        Add-SmokeFailure 'DMA interop must be default-on and use Ireland/en-IE/GeoID 68 for setup.'
    }
    if (-not [bool]$defaultProfile.privacy.location -or @($defaultConfig.RegistryTweaks) -contains 'location-disabled-policy') {
        Add-SmokeFailure 'Location services must default on and must not select the location-disabled policy.'
    }

    $fixedSettings = New-SmokeBuildProfileSettings
    $fixedSettings.EditionMode = 'Fixed'
    $fixedSettings.Edition = ''
    $fixedProfile = New-WinMintBuildProfile -Settings $fixedSettings
    if ($fixedProfile.target.edition -ne 'Windows 11 Home Single Language') {
        Add-SmokeFailure 'Fixed-edition generated profiles must default to Windows 11 Home Single Language.'
    }

    foreach ($expectedDefaultTweak in @(
            'home-privacy-policy', 'storage-sense-policy', 'modern-standby-policy', 'oobe-rehydration-policy', 'wpbt-policy',
            # Subtractive baseline: developer QoL is now baseline, and the default
            # build removes the Copilot+/AI feature surface, Recall, and the Game Bar.
            'developer-mode', 'gamebar-policy', 'windows-ai-features-removal', 'windows-ai-recall-policy'
        )) {
        if (@($defaultConfig.RegistryTweaks) -notcontains $expectedDefaultTweak) {
            Add-SmokeFailure "Home-first defaults must select '$expectedDefaultTweak'."
        }
    }
    foreach ($unexpectedDefaultTweak in @('dual-boot-clock-policy', 'gaming-performance-policy', 'desktopui-policy', 'location-disabled-policy')) {
        if (@($defaultConfig.RegistryTweaks) -contains $unexpectedDefaultTweak) {
            Add-SmokeFailure "Default Minimal policy must not select '$unexpectedDefaultTweak'."
        }
    }
    foreach ($unexpectedFeature in @('Microsoft-Windows-Sandbox', 'Containers-DisposableClientVM', 'Windows-Defender-ApplicationGuard')) {
        if (@($defaultConfig.Features) -contains $unexpectedFeature) {
            Add-SmokeFailure "Windows 11 Home baseline must not select Pro-only feature '$unexpectedFeature'."
        }
    }

    $locationOffSettings = New-SmokeBuildProfileSettings
    $locationOffSettings.PrivLocation = $false
    $locationOffConfig = New-WinMintBuildConfig -BuildProfile (New-WinMintBuildProfile -Settings $locationOffSettings)
    if (@($locationOffConfig.RegistryTweaks) -notcontains 'location-disabled-policy') {
        Add-SmokeFailure '-NoLocationServices/profile privacy.location=false must select location-disabled-policy.'
    }

    $dualBootSettings = New-SmokeBuildProfileSettings
    $dualBootSettings.DiskMode = 'DualBootReserved'
    $dualBootSettings.DualBootPreset = 'Balanced'
    $dualBootConfig = New-WinMintBuildConfig -BuildProfile (New-WinMintBuildProfile -Settings $dualBootSettings)
    if (@($dualBootConfig.RegistryTweaks) -notcontains 'dual-boot-clock-policy') {
        Add-SmokeFailure 'DualBootReserved builds must set RealTimeIsUniversal through dual-boot-clock-policy.'
    }

    $gamingSettings = New-SmokeBuildProfileSettings
    $gamingSettings.KeepGaming = $true
    $gamingConfig = New-WinMintBuildConfig -BuildProfile (New-WinMintBuildProfile -Settings $gamingSettings)
    if (@($gamingConfig.RegistryTweaks) -notcontains 'gaming-performance-policy') {
        Add-SmokeFailure '-KeepGaming must select gaming-performance-policy.'
    }
    if (@($gamingConfig.RegistryTweaks) -contains 'gamebar-policy') {
        Add-SmokeFailure '-KeepGaming must suppress the Game Bar removal policy.'
    }

    $desktopSettings = New-SmokeBuildProfileSettings
    $desktopSettings.DesktopUiDefault = $true
    $desktopConfig = New-WinMintBuildConfig -BuildProfile (New-WinMintBuildProfile -Settings $desktopSettings)
    if (@($desktopConfig.RegistryTweaks) -notcontains 'desktopui-policy') {
        Add-SmokeFailure 'DesktopUI profile must select desktopui-policy.'
    }

    $catalog = Get-Content -LiteralPath (Join-Path $root 'config\appx-removal.json') -Raw | ConvertFrom-Json
    foreach ($expectedPrefix in @('Microsoft.BingFinance', 'Microsoft.BingTranslator', 'Microsoft.Windows.AIHub', 'Microsoft.Windows.PeopleExperienceHost', 'Windows.CBSPreview')) {
        if (@($catalog.groups.coreMicrosoft) -notcontains $expectedPrefix) {
            Add-SmokeFailure "AppX core catalog must include '$expectedPrefix'."
        }
    }
    foreach ($expectedCandidate in @('SpotifyAB.SpotifyMusic', 'BytedancePte.Ltd.TikTok', '4DF9E0F8.Netflix', 'king.com', 'AD2F1837.HPAIExperienceCenter', 'DellInc.DellDigitalDelivery', 'E046963F.LenovoCompanion')) {
        if (@($catalog.groups.consumerThirdParty) -notcontains $expectedCandidate -and @($catalog.groups.oemConsumer) -notcontains $expectedCandidate) {
            Add-SmokeFailure "AppX candidate catalog must include '$expectedCandidate'."
        }
    }
    foreach ($mustPreserve in @('Microsoft.WindowsStore', 'Microsoft.DesktopAppInstaller', 'Microsoft.SecHealthUI', 'Microsoft.YourPhone', 'Microsoft.WindowsCamera', 'Microsoft.WindowsSoundRecorder', 'Microsoft.MicrosoftStickyNotes', 'Microsoft.WindowsAlarms', 'Microsoft.WindowsNotepad')) {
        if (@($catalog.preserve) -notcontains $mustPreserve) {
            Add-SmokeFailure "AppX preserve catalog must include '$mustPreserve'."
        }
    }

    $stagingText = Get-Content -LiteralPath (Join-Path $root 'src\engine\Private\Image\Staging.ps1') -Raw
    foreach ($expectedCapability in @('Browser.InternetExplorer', 'Microsoft.Windows.WordPad', 'MathRecognizer')) {
        if ($stagingText -notmatch [regex]::Escape($expectedCapability)) {
            Add-SmokeFailure "Capability removal should include '$expectedCapability'."
        }
    }
    foreach ($forbiddenCapability in @('Language.OCR', 'Language.Handwriting', 'Language.Speech', 'Language.TextToSpeech')) {
        if ($stagingText -match [regex]::Escape($forbiddenCapability)) {
            Add-SmokeFailure "Default capability removal must not include language feature '$forbiddenCapability'."
        }
    }
}

function Assert-LiveInstallAuditIsNonDestructive {
    $auditPath = Join-Path $root 'tools\audit\Audit-LiveInstall.ps1'
    if (-not (Test-Path -LiteralPath $auditPath)) {
        Add-SmokeFailure 'Expected tools\audit\Audit-LiveInstall.ps1 to exist.'
        return
    }
    $auditText = Get-Content -LiteralPath $auditPath -Raw
    foreach ($forbidden in @('Remove-AppxPackage', 'Remove-AppxProvisionedPackage', 'Remove-Item', 'reg.exe delete', 'Start-Process')) {
        if ($auditText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "Audit-LiveInstall.ps1 must be non-destructive and must not contain '$forbidden'."
        }
    }
}

function Assert-LiveInstallAuditCoversPlatformGuardrails {
    $auditText = Get-Content -LiteralPath (Join-Path $root 'tools\audit\Audit-LiveInstall.ps1') -Raw
    foreach ($expected in @(
            'Microsoft.WindowsStore',
            'Microsoft.DesktopAppInstaller',
            'winget.exe',
            'EdgeWebView',
            'WinDefend',
            'mpssvc',
            'wuauserv',
            'BITS',
            'WaaSMedicSvc',
            'Tcpip6',
            'hns',
            'tzautoupdate',
            'dmaInterop',
            'setupHomeLocationGeoId',
            'restoreTimeZoneId',
            'restoreHomeLocationGeoId'
        )) {
        if ($auditText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Audit-LiveInstall.ps1 should probe platform guardrail '$expected'."
        }
    }
}

function Assert-LiveInstallAuditUsesSetupProfilePrefixes {
    $auditText = Get-Content -LiteralPath (Join-Path $root 'tools\audit\Audit-LiveInstall.ps1') -Raw
    foreach ($expected in @('WinMintSetupProfile.json', 'appxRemovalPrefixes')) {
        if ($auditText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Audit-LiveInstall.ps1 should use setup profile value '$expected'."
        }
    }
}

function Assert-LiveInstallAuditIsStaged {
    $unattendText = Get-Content -LiteralPath (Join-Path $root 'src\engine\Private\Image\Unattend.ps1') -Raw
    if ($unattendText -notmatch [regex]::Escape('Audit-LiveInstall.ps1')) {
        Add-SmokeFailure 'Install-Autounattend should stage Audit-LiveInstall.ps1 with setup scripts.'
    }
    if ($unattendText -notmatch [regex]::Escape("Join-Path `$ScriptRoot 'src\setup'")) {
        Add-SmokeFailure 'Install-Autounattend must stage setup scripts from src\setup.'
    }
    if ($unattendText -match [regex]::Escape("Join-Path `$ScriptRoot 'scripts'")) {
        Add-SmokeFailure 'Install-Autounattend must not rely on the removed top-level scripts directory.'
    }
    foreach ($expected in @('SetupComplete.cmd', 'SetupComplete.ps1', 'Specialize.ps1', 'DefaultUser.ps1', 'FirstLogon.ps1')) {
        if ($unattendText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Install-Autounattend should stage '$expected'."
        }
    }
}

function Assert-DmaRestoreRunsBeforeOptionalFirstLogonWork {
    $firstLogonText = Get-Content -LiteralPath (Join-Path $root 'src\setup\FirstLogon.ps1') -Raw
    foreach ($expected in @('Restore-WinMintDmaRegionalDefaults', 'FirstLogon_RegionalRestore.json', 'Copy-UserInternationalSettingsToSystem', 'restoreLocationServices')) {
        if ($firstLogonText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon DMA restore should contain '$expected'."
        }
    }
    if ($firstLogonText -match [regex]::Escape('Get-WinMintFirstLogonNestedProfileValue -Profile')) {
        Add-SmokeFailure 'FirstLogon DMA restore must not call Get-WinMintFirstLogonNestedProfileValue with the old -Profile parameter.'
    }
    $restoreIndex = $firstLogonText.IndexOf('Restore-WinMintDmaRegionalDefaults')
    $oneDriveIndex = $firstLogonText.IndexOf('Invoke-WinMintFirstLogonOneDriveRemoval')
    $agentIndex = $firstLogonText.IndexOf('Launching WinMintAgent')
    if ($restoreIndex -lt 0 -or $oneDriveIndex -lt 0 -or $agentIndex -lt 0 -or -not ($restoreIndex -lt $oneDriveIndex -and $restoreIndex -lt $agentIndex)) {
        Add-SmokeFailure 'FirstLogon must restore DMA regional defaults before OneDrive cleanup and agent launch.'
    }
}

function Assert-DmaInteropUsesFixedIrelandRegion {
    $region = Resolve-WinMintDmaInteropSetupRegion
    if ($region.Country -ne 'Ireland' -or $region.Culture -ne 'en-IE' -or [int]$region.GeoId -ne 68) {
        Add-SmokeFailure "DMA interoperability must resolve Ireland/en-IE/GeoID 68, got $($region.Country)/$($region.Culture)/$($region.GeoId)."
    }

    $publicContractText = @(
        Get-Content -LiteralPath (Join-Path $root 'WinMint-CLI.ps1') -Raw
        Get-Content -LiteralPath (Join-Path $root 'src\engine\Private\Headless.ps1') -Raw
        Get-Content -LiteralPath (Join-Path $root 'schemas\winmint.buildprofile.schema.json') -Raw
    ) -join "`n"
    foreach ($forbidden in @('EeaCountry', 'EEACountry', 'DmaCountry', 'DMACountry', 'SetupCountry')) {
        if ($publicContractText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "DMA setup country must not be exposed as a public profile/CLI setting ('$forbidden')."
        }
    }
}

function Assert-LiveAuditDistinguishesDmaSetupFromVisibleRegion {
    $auditText = Get-Content -LiteralPath (Join-Path $root 'tools\audit\Audit-LiveInstall.ps1') -Raw
    foreach ($expected in @(
            'knownEeaSetupGeoId',
            'current.homeLocationGeoId',
            'restore.homeLocationGeoId',
            'locationServices',
            'ai-appx-provisioned-drift',
            'windows-update-service'
        )) {
        if ($auditText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Live audit should distinguish DMA setup/current visible region and AI/platform checks ('$expected')."
        }
    }
}

function Assert-AiRemovalCatalogAndGuardrails {
    $catalogPath = Join-Path $root 'config\ai-removal.json'
    if (-not (Test-Path -LiteralPath $catalogPath)) {
        Add-SmokeFailure 'Expected config\ai-removal.json to exist.'
        return
    }
    $catalogText = Get-Content -LiteralPath $catalogPath -Raw
    foreach ($expected in @(
            'MicrosoftWindows.Client.AIX',
            'MicrosoftWindows.Client.CoreAI',
            'Microsoft.Windows.Ai.Copilot.Provider',
            'Microsoft.Edge.GameAssist',
            'Microsoft.Office.ActionsServer',
            'Microsoft.WritingAssistant',
            'Microsoft.Windows.AIHub',
            'Office Actions Server'
        )) {
        if ($catalogText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "AI removal catalog should include '$expected'."
        }
    }

    $publicAiText = @(
        Get-Content -LiteralPath (Join-Path $root 'src\engine\Private\Image\AiRemoval.ps1') -Raw
        Get-WinMintSetupCompleteText
        Get-Content -LiteralPath (Join-Path $root 'tools\audit\Audit-LiveInstall.ps1') -Raw
    ) -join "`n"
    foreach ($forbidden in @('TrustedInstaller', 'IntegratedServicesRegionPolicySet.json', 'Remove-WindowsPackage', 'Remove-Package', 'Owners', 'DefVis')) {
        if ($publicAiText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "Serviceable AI removal path must not contain '$forbidden'."
        }
    }
    if ($publicAiText -match '\bRegister-ScheduledTask\b') {
        Add-SmokeFailure "Serviceable AI removal path must not register scheduled maintenance tasks."
    }
}

function Assert-RecoveryBundleIsOutputOnly {
    $reportsText = Get-Content -LiteralPath (Join-Path $root 'src\engine\Reports.ps1') -Raw
    foreach ($expected in @(
            'Save-WinMintRecoveryBundle',
            "Join-Path `$OutputDir 'recovery'",
            'Recover-WinMintAiPolicy.ps1',
            'Recover-WinMintDmaRegion.ps1',
            'WinMint-Recovery.json'
        )) {
        if ($reportsText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Recovery bundle output should include '$expected'."
        }
    }

    $setupStagingText = Get-Content -LiteralPath (Join-Path $root 'src\engine\Private\Image\Unattend.ps1') -Raw
    foreach ($forbidden in @('Recover-WinMintAiPolicy.ps1', 'Recover-WinMintDmaRegion.ps1', 'WinMint-Recovery.json')) {
        if ($setupStagingText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "Recovery bundle file '$forbidden' must not be staged into the installed OS."
        }
    }
}

function Assert-AgentRunsLiveInstallAudit {
    $profile = New-WinMintAgentProfile -BuildConfig (New-WinMintBuildConfig -BuildProfile (New-SmokeBuildProfile))
    if ([bool]$profile.modules.liveInstallAudit.enabled) {
        Add-SmokeFailure 'Live install audit must be disabled by default in the agent profile; users opt in explicitly.'
    }
    $optInSettings = New-SmokeBuildProfileSettings
    $optInSettings.LiveInstallAudit = $true
    $optInProfile = New-WinMintAgentProfile -BuildConfig (New-WinMintBuildConfig -BuildProfile (New-WinMintBuildProfile -Settings $optInSettings))
    if (-not [bool]$optInProfile.modules.liveInstallAudit.enabled) {
        Add-SmokeFailure 'Live install audit opt-in should enable the agent module.'
    }
    $agentModulePath = Join-Path $root 'src\agent\Modules\LiveInstallAudit.ps1'
    if (-not (Test-Path -LiteralPath $agentModulePath)) {
        Add-SmokeFailure 'Expected LiveInstallAudit agent module to exist.'
        return
    }
    $agentModuleText = Get-Content -LiteralPath $agentModulePath -Raw
    foreach ($expected in @('Invoke-WinMintAgentLiveInstallAuditBootstrap', 'liveInstallAudit', 'Audit-LiveInstall.ps1')) {
        if ($agentModuleText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "LiveInstallAudit agent module should contain '$expected'."
        }
    }
    $agentEntryText = Get-Content -LiteralPath (Join-Path $root 'src\agent\Start-WinMintAgent.ps1') -Raw
    $profilesIndex = $agentEntryText.IndexOf("Invoke-AgentProfileModule -StepName 'profiles'")
    $packageManagersIndex = $agentEntryText.IndexOf("Invoke-AgentProfileModule -StepName 'package-managers'")
    $editorsIndex = $agentEntryText.IndexOf("Invoke-AgentProfileModule -StepName 'editors'")
    $auditIndex = $agentEntryText.IndexOf("Invoke-AgentProfileModule -StepName 'liveInstallAudit'")
    $failedIndex = $agentEntryText.IndexOf('$failed = @')
    if ($profilesIndex -lt 0 -or $packageManagersIndex -lt 0 -or $editorsIndex -lt 0 -or $auditIndex -lt 0 -or $failedIndex -lt 0 -or
        -not ($profilesIndex -lt $packageManagersIndex -and $packageManagersIndex -lt $editorsIndex -and $editorsIndex -lt $auditIndex -and $auditIndex -lt $failedIndex)) {
        Add-SmokeFailure 'Start-WinMintAgent.ps1 should run liveInstallAudit during final validation before failed-step evaluation.'
    }
}

function Assert-NoMaintenancePayloadOrRegistration {
    $setupCompleteText = Get-WinMintSetupCompleteText
    $firstLogonText = Get-Content -LiteralPath (Join-Path $root 'src\setup\FirstLogon.ps1') -Raw
    $engineText = Get-Content -LiteralPath (Join-Path $root 'src\engine\Engine.ps1') -Raw
    $unattendText = Get-Content -LiteralPath (Join-Path $root 'src\engine\Private\Image\Unattend.ps1') -Raw
    $maintenancePayload = Join-Path $root 'src\setup\Maintain.ps1'

    if (Test-Path -LiteralPath $maintenancePayload) {
        Add-SmokeFailure 'Maintenance payload must not live under src\setup.'
    }

    foreach ($forbidden in @('WinMintSlim-Maintain', 'RegisterWinMintMaintainScheduledTask')) {
        if ($setupCompleteText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "SetupComplete.ps1 must not include maintenance task registration hook '$forbidden'."
        }
    }
    if ($firstLogonText -match [regex]::Escape("'Maintain.ps1'")) {
        Add-SmokeFailure 'FirstLogon cleanup must not preserve Maintain.ps1 on the installed system.'
    }
    if ($engineText -match [regex]::Escape("'Maintain.ps1'") -or
        $unattendText -match [regex]::Escape("'Maintain.ps1'")) {
        Add-SmokeFailure 'Maintain.ps1 must not be staged as a default setup artifact.'
    }
}

function Assert-ExternalReferenceAuditDocumentsSparkle {
    $strategyPath = Join-Path $root 'docs\Windows-Debloat-Strategy.md'
    $strategyText = Get-Content -LiteralPath $strategyPath -Raw
    if ($strategyText -notmatch 'Sparkle') {
        Add-SmokeFailure 'Windows-Debloat-Strategy.md should include Sparkle in the external tool lessons.'
    }
    foreach ($expectedUrl in @('https://docs.getsparkle.net/', 'https://github.com/parcoil/sparkle')) {
        if ($strategyText -notmatch [regex]::Escape($expectedUrl)) {
            Add-SmokeFailure "Windows-Debloat-Strategy.md should cite Sparkle source '$expectedUrl'."
        }
    }
}

function Assert-WslFirstDefaultsAndGuards {
    $defaultProfile = New-WinMintBuildProfile -Settings (New-SmokeBuildProfileSettings)
    $defaultDistros = @($defaultProfile.development.wsl.distros)
    if ($defaultDistros.Count -ne 0 -or [bool]$defaultProfile.development.wsl.enabled) {
        Add-SmokeFailure 'WSL must stay unselected until a distro is explicitly selected.'
    }

    $optOutSettings = New-SmokeBuildProfileSettings
    $optOutSettings.Wsl2Distros = @()
    $optOutProfile = New-WinMintBuildProfile -Settings $optOutSettings
    if (@($optOutProfile.development.wsl.distros).Count -ne 0 -or [bool]$optOutProfile.development.wsl.enabled) {
        Add-SmokeFailure 'Explicit empty Wsl2Distros must opt out of WSL default distro selection.'
    }

    $customSettings = New-SmokeBuildProfileSettings
    $customSettings.Wsl2Distros = @('Debian', 'archlinux', 'FedoraLinux')
    $customProfile = New-WinMintBuildProfile -Settings $customSettings
    $customDistros = @($customProfile.development.wsl.distros)
    foreach ($distro in @('Debian', 'archlinux', 'FedoraLinux')) {
        if ($customDistros -notcontains $distro) {
            Add-SmokeFailure "Expected custom WSL distro '$distro' to be preserved."
        }
    }
    if ($customDistros -contains 'Ubuntu') {
        Add-SmokeFailure 'Custom WSL distro selection must not force Ubuntu.'
    }

    $versionedFedoraSettings = New-SmokeBuildProfileSettings
    $versionedFedoraSettings.Wsl2Distros = @('FedoraLinux-44')
    $versionedFedoraProfile = New-WinMintBuildProfile -Settings $versionedFedoraSettings
    if (@($versionedFedoraProfile.development.wsl.distros) -notcontains 'FedoraLinux-44') {
        Add-SmokeFailure 'Versioned Fedora WSL distro selections must be preserved in the build profile.'
    }

    $guiStatePath = Join-Path $root 'apps\gui\src\state.rs'
    $guiStateText = Get-Content -LiteralPath $guiStatePath -Raw
    if ($guiStateText -notmatch 'selected_groups:\s*vec!\["Minimal"\]') {
        Add-SmokeFailure 'GPUI must default to Minimal profile group only.'
    }

    $wslModulePath = Join-Path $root 'src\agent\Modules\Wsl.ps1'
    $wslModuleText = Get-Content -LiteralPath $wslModulePath -Raw
    foreach ($expected in @('dnsTunneling=true', 'autoProxy=true', 'localhostForwarding=true', 'firewall=true', 'autoMemoryReclaim=gradual', 'sparseVhd=true')) {
        if ($wslModuleText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "WSL module should generate .wslconfig setting '$expected'."
        }
    }
    if ($wslModuleText -match 'networkingMode=mirrored') {
        Add-SmokeFailure 'WSL-first default must not force mirrored networking.'
    }
    if ($wslModuleText -match "\^FedoraLinux-\\d\+\$'\s*\{\s*return 'FedoraLinux'") {
        Add-SmokeFailure 'WSL module must not collapse explicit FedoraLinux-44 style requests to latest FedoraLinux.'
    }

    $strategyText = Get-Content -LiteralPath (Join-Path $root 'docs\Windows-Debloat-Strategy.md') -Raw
    foreach ($guard in @('WinMint is WSL2-first', 'Ubuntu LTS', '/home/<user>/code', 'networkingMode=nat')) {
        if ($strategyText -notmatch [regex]::Escape($guard)) {
            Add-SmokeFailure "WSL strategy should document '$guard'."
        }
    }
}

function Assert-LogNoiseInvariants {
    $pipelinePath = Join-Path $root 'src\engine\Private\Pipeline.ps1'
    $displayPath = Join-Path $root 'src\engine\Private\Console\Display.ps1'

    $pipelineText = Get-Content -LiteralPath $pipelinePath -Raw
    $targetLicenseSummaryCount = ([regex]::Matches(
        $pipelineText,
        [regex]::Escape("Edition mode: target license. Servicing")
    )).Count
    if ($targetLicenseSummaryCount -ne 1) {
        Add-SmokeFailure "Expected one target-license service summary log, found $targetLicenseSummaryCount."
    }

    $displayText = Get-Content -LiteralPath $displayPath -Raw
    if ($displayText -match '\$timer\.Elapsed\.TotalSeconds\s+-ge\s+1') {
        Add-SmokeFailure 'Invoke-Action must not print duration summaries for every action over one second.'
    }
    if ($displayText -notmatch 'WinMintActionTimingVisibleThresholdSeconds') {
        Add-SmokeFailure 'Expected Invoke-Action timing summaries to use a visible-duration threshold.'
    }
}

function Assert-WinPEDriverInjectionDefaultsToSetupOnly {
    $catalogPath = Join-Path $root 'src\engine\Private\Catalog.ps1'
    $stagingPath = Join-Path $root 'src\engine\Private\Image\Staging.ps1'
    $catalogText = Get-Content -LiteralPath $catalogPath -Raw
    $stagingText = Get-Content -LiteralPath $stagingPath -Raw

    if ($catalogText -notmatch '\$script:BootWimDriverMountIndexes\s*=\s*@\(2\)') {
        Add-SmokeFailure 'Expected default WinPE driver injection to target boot.wim index 2 only.'
    }
    if ($stagingText -match '\$forDrivers\s*=\s*@\(1,\s*2\)') {
        Add-SmokeFailure 'Expected staging readiness not to inject drivers into boot.wim indexes 1 and 2 by default.'
    }
    if ($stagingText -notmatch '\$forDrivers\s*=\s*@\(\s*@\(2\)\s*\|\s*Where-Object') {
        Add-SmokeFailure 'Expected setup-only boot.wim index selection to stay array-wrapped for StrictMode-safe Count access.'
    }
    if ($stagingText -notmatch 'Setup-only') {
        Add-SmokeFailure 'Expected staging log to make setup-only WinPE driver mode visible.'
    }
}

function Assert-CopilotPlusUsesFullAiRemovalPolicy {
    # Subtractive model: the default build removes the Edge noise surface
    # (edge-policy-minimal, always on), the Copilot+/Windows AI feature surface
    # (windows-ai-features-removal, kept only with -KeepCopilot), and Recall
    # (windows-ai-recall-policy, always on as a security baseline).
    $edge = $script:RegistryTweaks | Where-Object id -eq 'edge-policy-minimal' | Select-Object -First 1
    $aiFeatures = $script:RegistryTweaks | Where-Object id -eq 'windows-ai-features-removal' | Select-Object -First 1
    $recall = $script:RegistryTweaks | Where-Object id -eq 'windows-ai-recall-policy' | Select-Object -First 1
    if (-not $edge -or -not $aiFeatures -or -not $recall) {
        Add-SmokeFailure 'Expected edge-policy-minimal, windows-ai-features-removal, and windows-ai-recall-policy registry tweaks to exist.'
        return
    }
    foreach ($expected in @('EdgeShoppingAssistantEnabled', 'ShowMicrosoftRewards', 'WebWidgetAllowed', 'CryptoWalletEnabled', 'HideFirstRunExperience', 'EdgeEnhanceImagesEnabled')) {
        if (@($edge.set | Where-Object name -eq $expected).Count -eq 0) {
            Add-SmokeFailure "Expected Edge noise policy to set $expected."
        }
    }
    foreach ($expected in @(
            'HubsSidebarEnabled',
            'StandaloneHubsSidebarEnabled',
            'DisableSettingsAgent',
            'TurnOffWindowsCopilot',
            'CopilotPageContext',
            'EdgeEntraCopilotPageContext',
            'GenAILocalFoundationalModelSettings',
            'NewTabPageBingChatEnabled',
            'BuiltInAIAPIsEnabled',
            'DisableAIFeatures',
            'LetAppsAccessSystemAIModels',
            'LetAppsAccessGenerativeAI',
            'EnableCopilot'
        )) {
        if (@($aiFeatures.set | Where-Object name -eq $expected).Count -eq 0) {
            Add-SmokeFailure "Expected default AI feature removal policy to set $expected."
        }
    }
    foreach ($expected in @('DisableAIDataAnalysis', 'DisableClickToDo', 'AllowRecallEnablement', 'TurnOffSavingSnapshots')) {
        if (@($recall.set | Where-Object name -eq $expected).Count -eq 0) {
            Add-SmokeFailure "Expected Recall removal policy to set $expected."
        }
    }
    # Curation: by default the AI feature removal applies; -KeepCopilot suppresses
    # it, but Recall removal applies on every build regardless.
    $defaultSelected = @(Get-WinMintSelectedRegistryTweaks -Context (New-WinMintTweakContext -KeepCopilot $false))
    $keepCopilotSelected = @(Get-WinMintSelectedRegistryTweaks -Context (New-WinMintTweakContext -KeepCopilot $true))
    if ($defaultSelected -notcontains 'windows-ai-features-removal') {
        Add-SmokeFailure 'windows-ai-features-removal must apply by default (KeepCopilot off).'
    }
    if ($keepCopilotSelected -contains 'windows-ai-features-removal') {
        Add-SmokeFailure 'windows-ai-features-removal must be suppressed when -KeepCopilot is selected.'
    }
    if ($defaultSelected -notcontains 'windows-ai-recall-policy' -or $keepCopilotSelected -notcontains 'windows-ai-recall-policy') {
        Add-SmokeFailure 'Recall removal policy must apply on every build, including when -KeepCopilot is selected.'
    }
}

function Assert-OneDriveRemovalPolicyIsComplete {
    $policy = $script:RegistryTweaks | Where-Object id -eq 'onedrive-policy' | Select-Object -First 1
    if (-not $policy) {
        Add-SmokeFailure 'Expected onedrive-policy registry tweak to exist.'
        return
    }
    foreach ($expected in @(
            'DisableFileSync',
            'DisableFileSyncNGSC',
            'DisablePersonalSync',
            'DisableLibrariesDefaultSaveToOneDrive',
            'System.IsPinnedToNameSpaceTree',
            'Desktop',
            'Personal',
            'My Pictures',
            '{374DE290-123F-4565-9164-39C4925E467B}'
        )) {
        if (@($policy.set | Where-Object name -eq $expected).Count -eq 0) {
            Add-SmokeFailure "Expected OneDrive removal policy to set $expected."
        }
    }
    $values = @($policy.set | ForEach-Object { [string]$_.value })
    foreach ($forbidden in @('OneDrive\Documents', 'OneDrive\Desktop', 'OneDrive\Pictures')) {
        if (@($values | Where-Object { $_ -like "*$forbidden*" }).Count -gt 0) {
            Add-SmokeFailure "OneDrive removal policy must not point known folders at $forbidden."
        }
    }
    if (@($policy.set | Where-Object { [string]$_.path -like '*\Shell Folders' -and [string]$_.value -like 'C:\Users\Default\*' }).Count -gt 0) {
        Add-SmokeFailure 'OneDrive removal policy must not write literal C:\Users\Default shell folder values.'
    }

    $firstLogonPath = Join-Path $root 'src\setup\FirstLogon.ps1'
    $firstLogonText = Get-Content -LiteralPath $firstLogonPath -Raw
    $setupCompleteText = Get-WinMintSetupCompleteText
    $stagingText = Get-Content -LiteralPath (Join-Path $root 'src\engine\Private\Image\Staging.ps1') -Raw
    $pipelineText = Get-Content -LiteralPath (Join-Path $root 'src\engine\Private\Pipeline.ps1') -Raw
    foreach ($expected in @(
            'FirstLogon_OneDriveAudit.json',
            'FirstLogon_KnownFolders.json',
            'OneDriveSetup.exe.bak',
            'takeown.exe /f $setupFile',
            'icacls.exe $setupFile',
            'Remove-Item -LiteralPath $setupFile',
            'Active Setup\Installed Components',
            'StartupApproved\Run',
            'SyncRootManager',
            'App Paths',
            'registryResidue',
            'runResidue',
            'Unregister-ScheduledTask',
            "oneDriveAudit['compliant']"
        )) {
        if ($firstLogonText -notlike "*$expected*") {
            Add-SmokeFailure "Expected FirstLogon OneDrive cleanup to include $expected."
        }
    }
    foreach ($expected in @(
            'OneDriveSetup.exe.bak',
            'takeown.exe /f $setupFile',
            'icacls.exe $setupFile',
            'Remove-Item -LiteralPath $setupFile',
            'Active Setup\Installed Components',
            'StartupApproved\Run',
            'SyncRootManager',
            'App Paths',
            'Unregister-ScheduledTask'
        )) {
        if ($setupCompleteText -notlike "*$expected*") {
            Add-SmokeFailure "Expected SetupComplete OneDrive cleanup to include $expected."
        }
    }
    foreach ($expected in @(
            'Remove-WinMintOneDriveSetupStub',
            'Windows\System32\OneDriveSetup.exe',
            'Windows\SysWOW64\OneDriveSetup.exe',
            'oneDriveSetupStubs',
            'users can reinstall OneDrive later'
        )) {
        if ($stagingText -notlike "*$expected*") {
            Add-SmokeFailure "Expected offline OneDrive setup-stub removal to include $expected."
        }
    }
    if ($pipelineText -notlike '*Remove-WinMintOneDriveSetupStub -MountDir $mountDir*') {
        Add-SmokeFailure 'Expected ISO pipeline to remove OneDrive setup stubs from the offline image.'
    }
}

function Assert-CursorInstallUsesModernRegistryContract {
    $catalogPath = Join-Path $root 'src\engine\Private\Catalog.ps1'
    $assetsPath = Join-Path $root 'src\engine\Private\Image\Assets.ps1'
    $assetsText = Get-Content -LiteralPath $assetsPath -Raw

    $expectedOrder = @(
        'Arrow.cur', 'Help.cur', 'Work.ani', 'Busy.ani', 'Cross.cur', 'IBeam.cur', 'Handwriting.cur', 'Unavailable.cur',
        'SizeNS.cur', 'SizeWE.cur', 'SizeNWSE.cur', 'SizeNESW.cur', 'Move.cur', 'Alternate.cur', 'Link.cur',
        'Pin.cur', 'Person.cur'
    )
    if (@($script:Win11IsoCursorSchemeOrder).Count -ne 17 -or
        (@(Compare-Object -ReferenceObject $expectedOrder -DifferenceObject $script:Win11IsoCursorSchemeOrder -SyncWindow 0).Count -ne 0)) {
        Add-SmokeFailure 'Windows 11 Modern cursor scheme must use the modern 17-slot Windows cursor order.'
    }

    $expectedNames = @(
        'Arrow', 'Help', 'AppStarting', 'Wait', 'Crosshair', 'IBeam', 'NWPen', 'No',
        'SizeNS', 'SizeWE', 'SizeNWSE', 'SizeNESW', 'SizeAll', 'UpArrow', 'Hand', 'Pin', 'Person'
    )
    $actualNames = @($script:Win11IsoCursorRegistryPairs | ForEach-Object { [string]$_.Name })
    if (@(Compare-Object -ReferenceObject $expectedNames -DifferenceObject $actualNames -SyncWindow 0).Count -ne 0) {
        Add-SmokeFailure 'Cursor registry values must only use documented Windows cursor slot names.'
    }

    foreach ($forbiddenName in @('precisionhair', 'Grab', 'Grabbing', 'Pan', 'Zoom-in', 'Zoom-out')) {
        if ($actualNames -contains $forbiddenName) {
            Add-SmokeFailure "Cursor registry values must not include nonstandard cursor slot name: $forbiddenName."
        }
    }
    foreach ($forbiddenHook in @('CursorShadow', 'InstallHinfSection', 'rundll32', 'SystemParametersInfo', 'Active Setup')) {
        if ($assetsText -match [regex]::Escape($forbiddenHook)) {
            Add-SmokeFailure "Cursor installation must not rely on nonstandard cursor hooks or side effects: $forbiddenHook."
        }
    }
    if ($assetsText -notmatch '/v "\$schemeName" /t REG_EXPAND_SZ') {
        Add-SmokeFailure 'Cursor scheme list must be written as REG_EXPAND_SZ because it uses %SystemRoot% paths.'
    }
}

function Assert-RegistryTweakMetadataAndRollback {
    $publicPath = Join-Path $root 'config\tweaks.json'
    $public = Get-Content -LiteralPath $publicPath -Raw | ConvertFrom-Json
    $publicTweaks = @($public.tweaks)
    $publicIds = @($publicTweaks | ForEach-Object { [string]$_.id })
    $executableIds = @($script:RegistryTweaks | ForEach-Object { [string]$_.id })

    foreach ($group in @($script:RegistryTweaks)) {
        $id = [string]$group.id
        if ($publicIds -notcontains $id) {
            Add-SmokeFailure "Executable registry tweak '$id' must have public metadata in config\tweaks.json."
        }
        foreach ($field in @('id', 'description', 'scope', 'risk', 'reversible', 'phase', 'intent')) {
            $value = Get-WinMintProfileSetting $group $field $null
            if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) {
                Add-SmokeFailure "Registry tweak '$id' must define metadata field '$field'."
            }
        }
        if ([bool](Get-WinMintProfileSetting $group 'reversible' $false)) {
            $rollbackOps = @(
                foreach ($entry in @(Get-WinMintProfileSetting $group 'set' @())) {
                    if ($null -ne (Get-WinMintProfileSetting $entry 'undo' $null)) { $entry }
                }
                foreach ($entry in @(Get-WinMintProfileSetting $group 'remove' @())) {
                    if ($null -ne (Get-WinMintProfileSetting $entry 'restore' $null)) { $entry }
                }
            )
            if ($rollbackOps.Count -eq 0) {
                Add-SmokeFailure "Reversible registry tweak '$id' must include at least partial rollback metadata."
            }
        }
    }

    foreach ($publicTweak in $publicTweaks) {
        $id = [string]$publicTweak.id
        $docOnly = [bool](Get-WinMintProfileSetting $publicTweak 'documentationOnly' $false)
        if ($executableIds -notcontains $id -and -not $docOnly) {
            Add-SmokeFailure "Public tweak '$id' must map to an executable tweak or be marked documentationOnly."
        }
        foreach ($field in @('id', 'description', 'scope', 'risk', 'reversible', 'phase', 'intent')) {
            $value = Get-WinMintProfileSetting $publicTweak $field $null
            if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) {
                Add-SmokeFailure "Public tweak '$id' must define metadata field '$field'."
            }
        }
    }

    $hardware = $script:RegistryTweaks | Where-Object id -eq 'hardware-bypass' | Select-Object -First 1
    if (-not $hardware) {
        Add-SmokeFailure 'Expected hardware-bypass registry tweak to exist.'
    }
    elseif ([string]$hardware.risk -ne 'medium') {
        Add-SmokeFailure 'hardware-bypass must remain medium risk.'
    }

    $defaultConfig = New-WinMintBuildConfig -BuildProfile (New-SmokeBuildProfile)
    if (@($defaultConfig.RegistryTweaks) -contains 'hardware-bypass') {
        Add-SmokeFailure 'hardware-bypass must remain opt-in and absent from default registry tweaks.'
    }
    if (@($defaultConfig.RegistryTweaks) -contains 'uac-no-secure-desktop') {
        Add-SmokeFailure 'Default registry tweaks must not disable UAC secure desktop.'
    }
    if (@($script:RegistryTweaks | Where-Object id -eq 'uac-no-secure-desktop').Count -gt 0) {
        Add-SmokeFailure 'uac-no-secure-desktop must not remain as an executable tweak.'
    }
    foreach ($forbiddenUacName in @('EnableLUA', 'ConsentPromptBehaviorAdmin', 'PromptOnSecureDesktop')) {
        if (@($script:RegistryTweaks | ForEach-Object { @($_.set) } | Where-Object name -eq $forbiddenUacName).Count -gt 0) {
            Add-SmokeFailure "WinMint default tweak catalog must not stamp UAC value '$forbiddenUacName'."
        }
    }
}

function Assert-SetupRegistryStampsAreIdempotent {
    $defaultUserPath = Join-Path $root 'src\setup\DefaultUser.ps1'
    $specializePath = Join-Path $root 'src\setup\Specialize.ps1'
    $defaultUserText = Get-Content -LiteralPath $defaultUserPath -Raw
    $specializeText = Get-Content -LiteralPath $specializePath -Raw

    foreach ($expected in @(
            'function Set-DefaultUserRegistryValue',
            'function Set-DefaultUserRegistryDefaultValue',
            'function Remove-DefaultUserRegistryValue',
            'function Invoke-DefaultUserRegistrySet',
            'LaunchTo',
            'Start_TrackProgs',
            'SubscribedContent-310093Enabled',
            'SubscribedContent-338388Enabled',
            'SubscribedContent-338389Enabled',
            'SubscribedContent-353698Enabled',
            'SoftLandingEnabled',
            'SystemPaneSuggestionsEnabled',
            'ScoobeSystemSettingEnabled'
        )) {
        if ($defaultUserText -notlike "*$expected*") {
            Add-SmokeFailure "DefaultUser.ps1 should idempotently stamp '$expected'."
        }
    }

    foreach ($expected in @(
            'function Set-SpecializeRegistryValue',
            'function Invoke-SpecializeRegistrySet',
            'DisableSoftLanding',
            'CEIPEnable',
            'AITEnable',
            'DisableInventory',
            'SettingsPageVisibility',
            'hide:home'
        )) {
        if ($specializeText -notlike "*$expected*") {
            Add-SmokeFailure "Specialize.ps1 should idempotently stamp '$expected'."
        }
    }

    foreach ($forbidden in @('ConsentPromptBehaviorAdmin', 'EnableLUA', 'DisableWindowsConsumerFeatures')) {
        if ($defaultUserText -like "*$forbidden*" -or $specializeText -like "*$forbidden*") {
            Add-SmokeFailure "Setup registry stamps must not include '$forbidden'."
        }
    }
}
