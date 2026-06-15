#Requires -Version 7.3

function Get-WinMintSetupCompleteText {
    # SetupComplete is now a thin orchestrator plus per-concern modules under
    # src\runtime\setup\SetupComplete\. Content assertions must span both.
    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add((Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\SetupComplete.ps1') -Raw))
    $moduleDir = Join-Path $root 'src\runtime\setup\SetupComplete'
    if (Test-Path -LiteralPath $moduleDir) {
        foreach ($module in @(Get-ChildItem -LiteralPath $moduleDir -Filter '*.ps1' -File | Sort-Object Name)) {
            $parts.Add((Get-Content -LiteralPath $module.FullName -Raw))
        }
    }
    return ($parts.ToArray() -join "`n")
}

function Get-WinMintFirstLogonText {
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($relativePath in @(
        'src\runtime\setup\FirstLogon.ps1',
        'src\runtime\setup\FirstLogon.Support.ps1',
        'src\runtime\setup\FirstLogon.Transaction.ps1',
        'src\runtime\setup\FirstLogon.Runtime.ps1'
    )) {
        $path = Join-Path $root $relativePath
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $parts.Add((Get-Content -LiteralPath $path -Raw))
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
    foreach ($requiredField in @('architecture', 'computer_name', 'account_name', 'keep', 'edition', 'toolkit', 'desktop_layers')) {
        if ($stateText -notmatch "\b$([regex]::Escape($requiredField))\b") {
            Add-SmokeFailure "Expected BuildIntent to contain '$requiredField'."
        }
    }

    if ($intentText -notmatch 'winmint_core::profile') {
        Add-SmokeFailure 'GPUI intent bridge must use winmint-core profile helpers.'
    }
    if ($coreProfileText -notmatch 'pub struct KeepFlags') {
        Add-SmokeFailure 'winmint-core must own the keep-flag GUI intent input contract.'
    }
    foreach ($requiredKey in @('ISOPath', 'KeepEdge', 'KeepGaming', 'KeepCopilot', 'Edition', 'InstallWindhawk', 'InstallNilesoft', 'Browsers', 'Wsl2Distros')) {
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
    $cliVerbPath = Join-Path $root 'src\runtime\image\Cli.ps1'
    $headlessPath = Join-Path $root 'src\runtime\image\Private\Headless.ps1'
    $enginePath = Join-Path $root 'src\runtime\image\Engine.ps1'
    $cliVerbText = Get-Content -LiteralPath $cliVerbPath -Raw
    $headlessText = Get-Content -LiteralPath $headlessPath -Raw
    $engineText = Get-Content -LiteralPath $enginePath -Raw

    # build/validate run through Invoke-WinMintProfileRun, which must gate on
    # elevation before doing any work (including -DryRun and -ValidateOnly).
    if ($headlessText -notmatch 'Resolve-WinMintCliElevation') {
        Add-SmokeFailure 'Invoke-WinMintProfileRun must call Resolve-WinMintCliElevation so build and validate always require admin.'
    }
    if ($cliVerbText -notmatch 'function Resolve-WinMintCliElevation') {
        Add-SmokeFailure 'Cli.ps1 must define Resolve-WinMintCliElevation as the single elevation gate.'
    }
    if ($headlessText -match 'Test-WinMintAdministrator\)\s+-and\s+-not\s+\$DryRun') {
        Add-SmokeFailure 'Elevation guard must not exempt -DryRun; UUP prep and ISO inspection still require admin.'
    }
    if ($headlessText -match 'Test-WinMintAdministrator\)\s+-and\s+-not\s+\$ValidateOnly') {
        Add-SmokeFailure 'Elevation guard must not exempt -ValidateOnly; validation still probes DISM/source/driver state.'
    }
    if ($engineText -match 'Test-WinMintAdministrator\)\s+-and\s+-not\s+\$DryRun') {
        Add-SmokeFailure 'Engine elevation guard must not exempt -DryRun.'
    }
    # The elevation error must name -DryRun so it is clear dry-run is not exempt.
    if ($cliVerbText -notmatch 'require an elevated shell, including -DryRun') {
        Add-SmokeFailure 'Elevation error should explain that even -DryRun requires an elevated shell.'
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

    $keyed = $common.Clone()
    $keyed.EditionName = 'Windows 11 Home'
    $keyed.EditionMode = 'Fixed'
    $keyed.ProductKey = 'YTMG3-N6DKC-DKB77-7M9GH-8HVX7'
    $withKey = Install-Autounattend @keyed -HardwareBypass:$false
    if ([string]$withKey.AutounattendXml -notmatch '<Key>\s*YTMG3-N6DKC-DKB77-7M9GH-8HVX7\s*</Key>') {
        Add-SmokeFailure 'Expected -ProductKey to inject the generic key into UserData/ProductKey/Key.'
    }

    # RunSynchronousCommand <Path> has a ~259-char WCM limit; exceeding it makes
    # Windows Setup reject the answer file in the specialize pass (0x80220005),
    # which boot-loops the install with "restarted unexpectedly".
    $unattendXml = [xml]$plain.AutounattendXml
    $nsRsc = [System.Xml.XmlNamespaceManager]::new($unattendXml.NameTable)
    $nsRsc.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
    foreach ($pathNode in $unattendXml.SelectNodes('//u:RunSynchronousCommand/u:Path', $nsRsc)) {
        $pathText = [string]$pathNode.InnerText
        if ($pathText.Length -gt 259) {
            Add-SmokeFailure "RunSynchronousCommand <Path> is $($pathText.Length) chars (> 259 limit); Setup will reject specialize: '$($pathText.Substring(0, 50))...'"
        }
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
    $pipelineText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\Pipeline.ps1') -Raw
    if ($pipelineText -notmatch '\$imageMatches\.Count\s+-eq\s+1') {
        Add-SmokeFailure 'Fixed edition wildcard matching must only proceed when exactly one install image matches.'
    }
    if ($pipelineText -match 'ImageName\s+-like\s+"\*\$EditionName\*"\s*\}\s*\|\s*Select-Object\s+-First\s+1') {
        Add-SmokeFailure 'Fixed edition selection must not choose the first loose wildcard match; Home and Home Single Language must stay unambiguous.'
    }
}

function Assert-HyperVProfileIsProAndUnattended {
    $profilePath = Join-Path $root 'tests\profiles\hyper-v-install-arm64.json'
    $profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json

    if ([string]$profile.profileName -ne 'Hyper-V Test') {
        Add-SmokeFailure 'Hyper-V test profile must use profileName Hyper-V Test so FirstLogon retains VM diagnostics.'
    }
    if ([string]$profile.target.edition -ne 'Windows 11 Pro') {
        Add-SmokeFailure 'Hyper-V test profile must target Windows 11 Pro.'
    }
    if ([string]$profile.target.productKey -ne 'VK7JG-NPHTM-C97JM-9MPGT-3V66T') {
        Add-SmokeFailure 'Hyper-V test profile must use the Pro generic key.'
    }
    if ([string]$profile.identity.accountMode -ne 'Local') {
        Add-SmokeFailure 'Hyper-V test profile must use a local account for unattended install.'
    }
    if (-not [bool]$profile.identity.autoLogon) {
        Add-SmokeFailure 'Hyper-V test profile must enable autoLogon.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$profile.identity.password)) {
        Add-SmokeFailure 'Hyper-V test profile must include a local-account password.'
    }
    if (-not [bool]$profile.identity.passwordSet -or -not [bool]$profile.identity.passwordIncluded) {
        Add-SmokeFailure 'Hyper-V test profile must mark the password as set and included.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$profile.identity.computerName)) {
        Add-SmokeFailure 'Hyper-V test profile must set an explicit computer name.'
    }
    if (@($profile.development.editors) -notcontains 'cursor' -or @($profile.development.editors) -notcontains 'neovim') {
        Add-SmokeFailure 'Hyper-V test profile must select Cursor and Neovim editors.'
    }
    foreach ($browser in @('zen-browser', 'helium')) {
        if (@($profile.development.browsers) -notcontains $browser) {
            Add-SmokeFailure "Hyper-V test profile must select browser '$browser'."
        }
    }
    foreach ($distro in @('Ubuntu', 'NixOS-WSL')) {
        if (@($profile.development.wsl.distros) -notcontains $distro) {
            Add-SmokeFailure "Hyper-V test profile must select WSL distro '$distro'."
        }
    }
    if (@($profile.development.wsl.distros).Count -ne 2) {
        Add-SmokeFailure 'Hyper-V test profile must select exactly Ubuntu and NixOS-WSL.'
    }
    if (@($profile.desktop.layers) -notcontains 'nilesoft') {
        Add-SmokeFailure 'Hyper-V test profile must select the Nilesoft shell layer.'
    }
    if ([string]$profile.features.launcher -ne 'None') {
        Add-SmokeFailure 'Hyper-V test profile must not select a launcher for the Nilesoft/browser/editor VM acceptance pass.'
    }
}

function Assert-SurfaceProfileUsesStandardHome {
    $profilePath = Join-Path $root 'config\build-profiles\yanai-sl7-microsoft-oobe.json'
    $profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json

    if ([string]$profile.target.editionMode -ne 'Fixed' -or [string]$profile.target.edition -ne 'Windows 11 Home') {
        Add-SmokeFailure 'Surface Laptop 7 profile must target fixed standard Windows 11 Home, not Home Single Language or target-license selection.'
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
    if ($xml -notmatch '<HideWirelessSetupInOOBE>\s*true\s*</HideWirelessSetupInOOBE>') {
        Add-SmokeFailure 'Expected local account mode to hide the network page for unattended installs.'
    }
    if ($xml -notmatch '<settings pass="specialize">[\s\S]*<ComputerName>WinMint</ComputerName>') {
        Add-SmokeFailure 'Expected local unattended answer file to stamp ComputerName during specialize.'
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
    $packagesPath = Join-Path $root 'src\runtime\image\Private\Image\Packages.ps1'
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
    # Auto sign-in must survive the install reboots until the FirstLogon agent completes,
    # but the staged image must NOT bake in an effectively-infinite autologon. Expect a
    # small, bounded LogonCount; FirstLogon makes autologon persistent at runtime and
    # disables it + wipes the password the moment the agent run succeeds.
    if ($xmlText -match '<LogonCount>\s*(\d+)\s*</LogonCount>') {
        $logonCount = [int]$Matches[1]
        if ($logonCount -lt 1 -or $logonCount -gt 20) {
            Add-SmokeFailure "Generated autounattend AutoLogon count should be a small bounded value (1-20); got $logonCount."
        }
    }
    else {
        Add-SmokeFailure 'Generated autounattend should set a bounded AutoLogon LogonCount.'
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
            'Microsoft.WindowsCalculator',
            'MicrosoftCorporationII.QuickAssist',
            'Microsoft.WindowsSoundRecorder',
            'Microsoft.MicrosoftStickyNotes',
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

    $agentPath = Join-Path $root 'src\runtime\firstlogon\Modules\PhoneLink.ps1'
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

    if ([int]$defaultProfile.schemaVersion -ne 3) {
        Add-SmokeFailure 'Default generated profile must use schemaVersion 3.'
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
    if ($fixedProfile.target.edition -ne 'Windows 11 Home') {
        Add-SmokeFailure 'Fixed-edition generated profiles must default to Windows 11 Home.'
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
    foreach ($mustPreserve in @('Microsoft.WindowsStore', 'Microsoft.DesktopAppInstaller', 'Microsoft.SecHealthUI', 'Microsoft.YourPhone', 'Microsoft.WindowsCamera', 'Microsoft.WindowsAlarms', 'Microsoft.WindowsNotepad')) {
        if (@($catalog.preserve) -notcontains $mustPreserve) {
            Add-SmokeFailure "AppX preserve catalog must include '$mustPreserve'."
        }
    }

    $stagingText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\Image\Staging.ps1') -Raw
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
    $setupPayloadText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\Image\SetupPayloadStaging.ps1') -Raw
    if ($setupPayloadText -notmatch [regex]::Escape('Audit-LiveInstall.ps1')) {
        Add-SmokeFailure 'Setup payload staging should stage Audit-LiveInstall.ps1 with setup scripts.'
    }
    if ($setupPayloadText -notmatch [regex]::Escape("Join-Path `$ScriptRoot 'src\runtime\setup'")) {
        Add-SmokeFailure 'Setup payload staging must stage setup scripts from src\runtime\setup.'
    }
    if ($setupPayloadText -match [regex]::Escape("Join-Path `$ScriptRoot 'scripts'")) {
        Add-SmokeFailure 'Setup payload staging must not rely on the removed top-level scripts directory.'
    }
    foreach ($expected in @('SetupComplete.cmd', 'SetupComplete.ps1', 'Specialize.ps1', 'DefaultUser.ps1', 'FirstLogon.ps1', 'FirstLogon.Support.ps1', 'FirstLogon.Transaction.ps1', 'FirstLogon.Runtime.ps1')) {
        if ($setupPayloadText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Setup payload staging should stage '$expected'."
        }
    }
}

function Assert-DmaRestoreRunsBeforeOptionalFirstLogonWork {
    $firstLogonText = Get-WinMintFirstLogonText
    foreach ($expected in @('Restore-WinMintDmaRegionalDefaults', 'FirstLogon_RegionalRestore.json', 'Copy-UserInternationalSettingsToSystem', 'restoreLocationServices', 'New-WinMintFirstLogonTransactionPlan', 'FirstLogon.Transaction.ps1')) {
        if ($firstLogonText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon DMA restore should contain '$expected'."
        }
    }
    if ($firstLogonText -match [regex]::Escape('Get-WinMintFirstLogonNestedProfileValue -Profile')) {
        Add-SmokeFailure 'FirstLogon DMA restore must not call Get-WinMintFirstLogonNestedProfileValue with the old -Profile parameter.'
    }
    $firstLogonRuntimeText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\FirstLogon.Runtime.ps1') -Raw
    $restoreIndex = $firstLogonRuntimeText.IndexOf('Restore-WinMintDmaRegionalDefaults')
    $oneDriveIndex = $firstLogonRuntimeText.IndexOf('Invoke-WinMintFirstLogonOneDriveRemoval')
    $agentIndex = $firstLogonRuntimeText.IndexOf('Invoke-WinMintFirstLogonAgentLaunch')
    if ($restoreIndex -lt 0 -or $oneDriveIndex -lt 0 -or $agentIndex -lt 0 -or -not ($restoreIndex -lt $oneDriveIndex -and $restoreIndex -lt $agentIndex)) {
        Add-SmokeFailure 'FirstLogon must restore DMA regional defaults before OneDrive cleanup and agent launch.'
    }
}

function Assert-FirstLogonDefaultsToVisibleConsole {
    $firstLogonText = Get-WinMintFirstLogonText
    $defaultUserText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\DefaultUser.ps1') -Raw
    foreach ($expected in @(
        'return ''Console''',
        'Resolve-WinMintWindowsTerminalHost',
        'Wait-WinMintWindowsTerminalHost',
        'Start-WinMintFirstLogonAgentInTerminal',
        'Waiting for Windows Terminal before launching WinMintAgent.',
        'new-tab',
        'WinMint FirstLogon',
        'WindowStyle Normal',
        'WindowStyle Hidden',
        'Set-WinMintFirstLogonWindowsTerminalDefault',
        'DelegationConsole',
        'DelegationTerminal',
        '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}',
        '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}'
    )) {
        if ($firstLogonText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon agent mode wiring should contain '$expected'."
        }
    }
    foreach ($expected in @('Set-DefaultUserWindowsTerminalDelegation', 'HKU\.DEFAULT', 'HKU\DefaultUser', 'DelegationConsole', 'DelegationTerminal')) {
        if ($defaultUserText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Default user setup should set Windows Terminal as the default terminal host with '$expected'."
        }
    }
    if ($firstLogonText -match [regex]::Escape('return ''Headless''') -and $firstLogonText -match [regex]::Escape('Default to a visible progress console')) {
        # Expected: the file still supports opt-in headless mode, but the auto/default
        # path must resolve to the visible console.
        return
    }
    if ($firstLogonText -notmatch [regex]::Escape('Default to a visible progress console')) {
        Add-SmokeFailure 'FirstLogon default mode should be a visible progress console.'
    }
}

function Assert-FirstLogonDemoHarnessIsNonMutating {
    $demoPath = Join-Path $root 'tools\firstlogon\Show-WinMintFirstLogonDemo.ps1'
    if (-not (Test-Path -LiteralPath $demoPath -PathType Leaf)) {
        Add-SmokeFailure 'Expected tools\firstlogon\Show-WinMintFirstLogonDemo.ps1 to exist.'
        return
    }

    $demoText = Get-Content -LiteralPath $demoPath -Raw
    $consoleText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Agent.Console.ps1') -Raw
    $agentStartText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Start-WinMintAgent.ps1') -Raw
    $setupPayloadText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\Image\SetupPayloadStaging.ps1') -Raw
    foreach ($expected in @(
        "[ValidateSet('Success', 'Warnings', 'Failure', 'LongRun')]",
        'WinMintFirstLogonDemo-',
        'Agent.Console.ps1',
        'Show-AgentPlan',
        'Show-AgentFinalSummary',
        'Show-DemoRunOverview',
        'Show-DemoArtifacts',
        'Initialize-DemoUtf8Console',
        'wt.exe',
        'UseWindowsTerminal',
        'ForceSixel',
        'NoPause'
    )) {
        if ($demoText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon demo harness should contain '$expected'."
        }
    }
    foreach ($expected in @(
        'Get-SpectreImage',
        'AgentConsoleSplashImagePath',
        'AgentConsoleForceSixel',
        'AgentConsoleSplashMaxWidth',
        'Show-AgentSplashImage',
        'Format-SpectreAligned',
        "Format = 'Sixel'",
        'Force = $true',
        '$env:WT_SESSION',
        'Out-SpectreHost'
    )) {
        if ($consoleText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon console should support image splash rendering with '$expected'."
        }
    }
    if ($agentStartText -notmatch [regex]::Escape('Assets\Brand\winmint_logo_wordmark.png')) {
        Add-SmokeFailure 'FirstLogon agent should point the console splash at the staged WinMint logo wordmark PNG.'
    }
    foreach ($expected in @('assets\brand\winmint_hero.png', 'Assets\Brand', 'winmint_logo_wordmark.png', 'Staged WinMint logo wordmark PNG')) {
        if ($setupPayloadText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "ISO staging should include the FirstLogon splash asset with '$expected'."
        }
    }

    foreach ($forbidden in @(
        'Start-WinMintAgent.ps1',
        'Agent.Runtime.ps1',
        'Set-WinMintFirstLogonAutoLogonPersistent',
        'Clear-WinMintFirstLogonRetry',
        'Invoke-WinMintFirstLogonAppxCleanup',
        'Invoke-WinMintFirstLogonOneDriveRemoval',
        '$env:LOCALAPPDATA\WinMint'
    )) {
        if ($demoText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "FirstLogon demo harness must not call or target mutating setup path '$forbidden'."
        }
    }

    foreach ($forbiddenPattern in @(
        '(?m)^\s*&\s*(winget|wsl|schtasks|reg)(\.exe)?\b',
        '(?m)^\s*Start-Process\s+.*\b(winget|wsl|schtasks|reg)(\.exe)?\b'
    )) {
        if ($demoText -match $forbiddenPattern) {
            Add-SmokeFailure "FirstLogon demo harness must not execute installer or setup commands matching '$forbiddenPattern'."
        }
    }
}

function Assert-FirstLogonPinsSelectedAppsToStart {
    $firstLogonText = Get-WinMintFirstLogonText
    foreach ($expected in @(
        'Set-WinMintFirstLogonStartPins',
        'Resolve-WinMintFirstLogonAppExecutable',
        'Resolve-WinMintFirstLogonStartShortcut',
        'Get-WinMintFirstLogonPackageDisplayNames',
        'New-WinMintFirstLogonStartShortcut',
        'desktopAppLink',
        'ConfigureStartPins',
        'Start pins applied',
        'Zen Browser',
        'Helium',
        'Cursor',
        '$cliOnlyAppIds'
    )) {
        if ($firstLogonText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon should pin selected browsers/editors to Start with '$expected'."
        }
    }
    if ($firstLogonText -match [regex]::Escape('Microsoft\Windows\Start Menu\Programs\WinMint')) {
        Add-SmokeFailure 'FirstLogon must not create a WinMint Start Menu helper folder for Start pins.'
    }
    if ($firstLogonText -match 'New-WinMintFirstLogonStartShortcut[\s\S]{0,240}neovim') {
        Add-SmokeFailure 'FirstLogon must not create or pin Neovim shortcuts; Neovim is CLI-only.'
    }
}

function Assert-FirstLogonFinalizesTerminalProfiles {
    $firstLogonText = Get-WinMintFirstLogonText
    foreach ($expected in @(
        'Set-WinMintFirstLogonTerminalProfiles',
        'New-WinMintFirstLogonTerminalPowerShellProfile',
        'New-WinMintFirstLogonTerminalWslProfile',
        'Repair-WinMintFirstLogonTerminalIcons',
        'Windows.Terminal.WindowsPowerShell',
        'Windows Terminal profiles finalized',
        'NixOS',
        'ubuntu.png',
        'fedora.png',
        'archlinux.png',
        'nixos.png'
    )) {
        if ($firstLogonText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon should finalize Terminal profiles after generated stock profiles appear with '$expected'."
        }
    }
    foreach ($forbiddenIcon in @('ubuntu.svg', 'fedora.svg', 'archlinux.svg', 'nixos.svg')) {
        if ($firstLogonText -match [regex]::Escape($forbiddenIcon)) {
            Add-SmokeFailure "FirstLogon Windows Terminal profiles must use staged PNG icons, not '$forbiddenIcon'."
        }
    }
    if ($firstLogonText -match '\$agentExitCode\s+-eq\s+0[\s\S]{0,240}Set-WinMintFirstLogonTerminalProfiles') {
        Add-SmokeFailure 'FirstLogon Terminal profile finalization must not be gated on a fully successful agent exit code.'
    }
    if ($firstLogonText -match '\$agentExitCode\s+-eq\s+0[\s\S]{0,320}Set-WinMintFirstLogonStartPins') {
        Add-SmokeFailure 'FirstLogon Start pin finalization must not be gated on a fully successful agent exit code.'
    }
}

function Assert-AgentLiveInstallFailuresAreWarnings {
    $agentText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Agent.Runtime.ps1') -Raw
    $consoleText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Agent.Console.ps1') -Raw
    foreach ($expected in @(
        '$blockingSteps',
        'FailurePolicy',
        'warningSteps',
        'completed with warnings',
        'failed (non-blocking)',
        'Wait-AgentConsoleBeforeClose -Failed $false -Warnings'
    )) {
        if ($agentText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Agent should treat live install failures as warnings with '$expected'."
        }
    }
    foreach ($expected in @('param([bool]$Failed, [bool]$Warnings)', 'finished with warnings')) {
        if ($consoleText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Agent console should report warning-only completion with '$expected'."
        }
    }
    if ($agentText -match [regex]::Escape('$advisorySteps = @(''liveInstallAudit'', ''phone-link'')')) {
        Add-SmokeFailure 'Agent must not limit non-blocking failures to only liveInstallAudit and phone-link.'
    }
    foreach ($expected in @(
        'Remove-AgentDesktopShortcuts',
        'CommonDesktopDirectory',
        "Filter '*.lnk'",
        'Removed desktop shortcuts created by installers.'
    )) {
        if ($agentText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Agent should remove live installer-created desktop shortcuts with '$expected'."
        }
    }
}

function Assert-SetupCompleteRegistersFirstLogonFallback {
    $setupCompleteText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\SetupComplete.ps1') -Raw
    $firstLogonText = Get-WinMintFirstLogonText

    foreach ($expected in @(
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'WinMintFirstLogon',
        'FirstLogon.ps1',
        'Registered HKLM RunOnce fallback for FirstLogon.ps1 under PowerShell 7.'
    )) {
        if ($setupCompleteText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "SetupComplete should register FirstLogon fallback with '$expected'."
        }
    }

    foreach ($expected in @(
        'Clear-WinMintFirstLogonRetry',
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'WinMintFirstLogon'
    )) {
        if ($firstLogonText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon should clean FirstLogon RunOnce fallback after success with '$expected'."
        }
    }
}

function Assert-SetupCompleteDoesNotDeleteWindowsOld {
    $setupCompleteText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\SetupComplete.ps1') -Raw
    if ($setupCompleteText -match [regex]::Escape('C:\Windows.old')) {
        Add-SmokeFailure 'SetupComplete must not delete C:\Windows.old; clean-install/destructive behavior must stay explicit.'
    }
}

function Assert-EdgeRemovalIntentDoesNotDependOnDma {
    $settings = New-SmokeBuildProfileSettings
    $settings.DmaInterop = $false
    $settings.KeepEdge = $false
    $config = New-WinMintBuildConfig -BuildProfile (New-WinMintBuildProfile -Settings $settings)
    $setupProfile = New-WinMintSetupProfile -BuildConfig $config
    if (-not [bool]$setupProfile.edge.removeEdge) {
        Add-SmokeFailure 'Edge removal intent should be recorded whenever KeepEdge is false, even when DMA interop is off.'
    }
    $unattendText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\Image\Unattend.ps1') -Raw
    if ($unattendText -match [regex]::Escape('$removeEdgeBrowser = ((-not [bool]$BuildConfig.Keep.Edge) -and [bool]$BuildConfig.DmaInterop.Enabled)')) {
        Add-SmokeFailure 'New-WinMintSetupProfile must not couple Edge removal intent to DMA interop.'
    }
    $edgeText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\SetupComplete\Edge.ps1') -Raw
    foreach ($expected in @(
        'Invoke-ScEdgeNormalUninstall',
        '--uninstall',
        '--system-level',
        '--force-uninstall',
        'supported app uninstaller'
    )) {
        if ($edgeText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "SetupComplete Edge removal should use the normal supported uninstaller with '$expected'."
        }
    }
    foreach ($forbidden in @('WINMINT_ENABLE_EXPERIMENTAL_EDGE_REMOVAL', 'Remove-ScRegistryTree')) {
        if ($edgeText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "SetupComplete Edge removal must not use hidden env gates or policy/file cleanup hooks: '$forbidden'."
        }
    }
}

function Assert-AutoTimeZoneUpdaterFollowsLocationServices {
    $firstLogonText = Get-WinMintFirstLogonText
    foreach ($expected in @(
        'if (-not $restoreLocationServices)',
        'Disabled Auto Time Zone Updater because location services are off.',
        'Enabled Auto Time Zone Updater because location services are on.',
        'ConsentStore\location',
        'SensorPermissionState',
        "'Allow'",
        "'Deny'"
    )) {
        if ($firstLogonText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon Auto Time Zone Updater handling should include '$expected'."
        }
    }
    if ($firstLogonText -match [regex]::Escape('Disabled Auto Time Zone Updater after DMA setup.')) {
        Add-SmokeFailure 'FirstLogon must not unconditionally disable Auto Time Zone Updater after DMA setup.'
    }
    $specializeText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\Specialize.ps1') -Raw
    if ($specializeText -notmatch [regex]::Escape('$restoreLocationServices') -or
        $specializeText -notmatch [regex]::Escape('if (-not $restoreLocationServices)') -or
        $specializeText -match [regex]::Escape("Set-WinHomeLocation -GeoId `$dmaSetupGeoId -ErrorAction Stop`r`n            Disable-SpecializeAutoTimeZone")) {
        Add-SmokeFailure 'Specialize must not unconditionally disable Auto Time Zone Updater when location services are expected on.'
    }
    $auditText = Get-Content -LiteralPath (Join-Path $root 'tools\audit\Audit-LiveInstall.ps1') -Raw
    foreach ($expected in @('dma-auto-time-zone-disabled', 'Location services are expected on, but Auto Time Zone Updater is disabled.')) {
        if ($auditText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Live audit Auto Time Zone Updater handling should include '$expected'."
        }
    }
}

function Assert-DmaInteropUsesFixedIrelandRegion {
    $region = Resolve-WinMintDmaInteropSetupRegion
    if ($region.Country -ne 'Ireland' -or $region.Culture -ne 'en-IE' -or [int]$region.GeoId -ne 68) {
        Add-SmokeFailure "DMA interoperability must resolve Ireland/en-IE/GeoID 68, got $($region.Country)/$($region.Culture)/$($region.GeoId)."
    }

    $publicContractText = @(
        Get-Content -LiteralPath (Join-Path $root 'WinMint-CLI.ps1') -Raw
        Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\Headless.ps1') -Raw
        Get-Content -LiteralPath (Join-Path $root 'schemas\winmint.buildprofile.schema.json') -Raw
    ) -join "`n"
    foreach ($forbidden in @('EeaCountry', 'EEACountry', 'DmaCountry', 'DMACountry', 'SetupCountry')) {
        if ($publicContractText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "DMA setup country must not be exposed as a public profile/CLI setting ('$forbidden')."
        }
    }
}

function Assert-BuildProfileSchemaOwnsBrowserContract {
    $schemaPath = Join-Path $root 'schemas\winmint.buildprofile.schema.json'
    $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    $development = $schema.properties.development

    function Assert-BuildProfileSchemaEnum {
        param(
            [Parameter(Mandatory)][object[]]$Actual,
            [Parameter(Mandatory)][object[]]$Expected,
            [Parameter(Mandatory)][string]$Name
        )

        $actualText = @($Actual | ForEach-Object { [string]$_ })
        $expectedText = @($Expected | ForEach-Object { [string]$_ })
        if (($actualText -join "`n") -ne ($expectedText -join "`n")) {
            Add-SmokeFailure "BuildProfile schema enum '$Name' must match the backend option catalog. Actual: [$($actualText -join ', ')] Expected: [$($expectedText -join ', ')]"
        }
    }

    if (@($development.required) -notcontains 'browsers') {
        Add-SmokeFailure 'BuildProfile schema must require profile.development.browsers as a first-class contract field.'
    }

    $browserSchema = $development.properties.browsers
    if (-not [bool]$browserSchema.uniqueItems) {
        Add-SmokeFailure 'BuildProfile schema must require profile.development.browsers to be unique.'
    }
    foreach ($browserId in @('zen-browser', 'helium', 'librewolf', 'brave', 'edge')) {
        if (@($browserSchema.items.enum) -notcontains $browserId) {
            Add-SmokeFailure "BuildProfile schema must allow canonical browser id '$browserId'."
        }
    }
    Assert-BuildProfileSchemaEnum -Actual $schema.properties.source.properties.architecture.enum -Expected (Get-WinMintOptionValues -Name ProfileArchitecture) -Name 'profile.source.architecture'
    Assert-BuildProfileSchemaEnum -Actual $schema.properties.target.properties.device.enum -Expected (Get-WinMintOptionValues -Name TargetDevice) -Name 'profile.target.device'
    Assert-BuildProfileSchemaEnum -Actual $schema.properties.target.properties.formFactor.enum -Expected (Get-WinMintOptionValues -Name FormFactor) -Name 'profile.target.formFactor'
    Assert-BuildProfileSchemaEnum -Actual $schema.properties.target.properties.editionMode.enum -Expected (Get-WinMintOptionValues -Name EditionMode) -Name 'profile.target.editionMode'
    Assert-BuildProfileSchemaEnum -Actual $schema.properties.target.properties.diskMode.enum -Expected (Get-WinMintOptionValues -Name DiskMode) -Name 'profile.target.diskMode'
    Assert-BuildProfileSchemaEnum -Actual $schema.properties.target.properties.diskLayout.properties.mode.enum -Expected (Get-WinMintOptionValues -Name DiskMode) -Name 'profile.target.diskLayout.mode'
    Assert-BuildProfileSchemaEnum -Actual $schema.properties.target.properties.diskLayout.properties.preset.enum -Expected (Get-WinMintOptionValues -Name DiskLayoutPreset) -Name 'profile.target.diskLayout.preset'
    Assert-BuildProfileSchemaEnum -Actual $schema.properties.identity.properties.accountMode.enum -Expected (Get-WinMintOptionValues -Name AccountMode) -Name 'profile.identity.accountMode'
    Assert-BuildProfileSchemaEnum -Actual $schema.properties.drivers.properties.source.enum -Expected (Get-WinMintOptionValues -Name DriverSource) -Name 'profile.drivers.source'
    Assert-BuildProfileSchemaEnum -Actual @($schema.properties.desktop.properties.cursorPack.const) -Expected (Get-WinMintOptionValues -Name DesktopCursorPack) -Name 'profile.desktop.cursorPack'
    Assert-BuildProfileSchemaEnum -Actual $schema.properties.desktop.properties.layers.items.enum -Expected (Get-WinMintOptionValues -Name DesktopLayer) -Name 'profile.desktop.layers[]'
    Assert-BuildProfileSchemaEnum -Actual $development.properties.editors.items.enum -Expected (Get-WinMintOptionValues -Name Editor) -Name 'profile.development.editors[]'
    Assert-BuildProfileSchemaEnum -Actual $development.properties.browsers.items.enum -Expected (Get-WinMintOptionValues -Name Browser) -Name 'profile.development.browsers[]'
    Assert-BuildProfileSchemaEnum -Actual $development.properties.wsl.properties.distros.items.enum -Expected (Get-WinMintOptionValues -Name WslDistro) -Name 'profile.development.wsl.distros[]'
    Assert-BuildProfileSchemaEnum -Actual $schema.properties.features.properties.launcher.enum -Expected (Get-WinMintOptionValues -Name Launcher) -Name 'profile.features.launcher'
    Assert-BuildProfileSchemaEnum -Actual $schema.properties.updates.properties.mode.enum -Expected (Get-WinMintOptionValues -Name UpdateMode) -Name 'profile.updates.mode'
    Assert-BuildProfileSchemaEnum -Actual @($schema.properties.updates.properties.targetFeatureVersion.const) -Expected (Get-WinMintOptionValues -Name UpdateTargetFeatureVersion) -Name 'profile.updates.targetFeatureVersion'
    Assert-BuildProfileSchemaEnum -Actual @($schema.properties.updates.properties.releaseCadence.const) -Expected (Get-WinMintOptionValues -Name UpdateReleaseCadence) -Name 'profile.updates.releaseCadence'
    Assert-BuildProfileSchemaEnum -Actual $schema.properties.removals.properties.aiPolicy.enum -Expected (Get-WinMintOptionValues -Name AiPolicy) -Name 'profile.removals.aiPolicy'

    $wslEnabledSchema = $development.properties.wsl.properties.enabled
    if ($wslEnabledSchema.const -ne $true) {
        Add-SmokeFailure 'BuildProfile schema must require profile.development.wsl.enabled to stay true in v3.'
    }

    $conditionalJson = $schema.allOf | ConvertTo-Json -Depth 30 -Compress
    foreach ($expected in @('"contains":{"const":"edge"}', '"required":["keep"]', '"edge":{"const":true}')) {
        if ($conditionalJson -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "BuildProfile schema must enforce edge browser selection implies keep.edge=true ('$expected')."
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
        Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\Image\AiRemoval.ps1') -Raw
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
    $manifestText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\Manifest.ps1') -Raw
    foreach ($expected in @(
            'Save-WinMintRecoveryBundle',
            "Join-Path `$OutputDir 'recovery'",
            'Recover-WinMintAiPolicy.ps1',
            'Recover-WinMintDmaRegion.ps1',
            'WinMint-Recovery.json'
        )) {
        if ($manifestText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Recovery bundle output should include '$expected'."
        }
    }

    $setupStagingText = @(
        Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\Image\Unattend.ps1') -Raw
        Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\Image\SetupPayloadStaging.ps1') -Raw
    ) -join [Environment]::NewLine
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
    $agentModulePath = Join-Path $root 'src\runtime\firstlogon\Modules\LiveInstallAudit.ps1'
    if (-not (Test-Path -LiteralPath $agentModulePath)) {
        Add-SmokeFailure 'Expected LiveInstallAudit agent module to exist.'
        return
    }
    $agentModuleText = Get-Content -LiteralPath $agentModulePath -Raw
    foreach ($expected in @('Invoke-WinMintAgentLiveInstallAuditBootstrap', 'liveInstallAudit', 'Audit-LiveInstall.ps1', '-IncludeInventory')) {
        if ($agentModuleText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "LiveInstallAudit agent module should contain '$expected'."
        }
    }
    $auditScriptText = Get-Content -LiteralPath (Join-Path $root 'tools\audit\Audit-LiveInstall.ps1') -Raw
    foreach ($expected in @('IncludeInventory', 'debugInventory', 'Get-AuditServiceInventory', 'Get-AuditScheduledTaskInventory', 'Get-AuditStartupInventory')) {
        if ($auditScriptText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Live install audit should expose debug inventory through the opt-in report with '$expected'."
        }
    }
    $agentEntryText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Agent.Runtime.ps1') -Raw
    foreach ($expected in @(
        'New-WinMintAgentRuntimeStepPlan',
        'FailurePolicy',
        '''blocking''',
        '''advisory''',
        'finalValidation',
        '$blockingSteps = @($runtimePlan'
    )) {
        if ($agentEntryText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Agent runtime should expose plan-driven ordering and failure policy with '$expected'."
        }
    }
    $profilesIndex = $agentEntryText.IndexOf("Add-AgentRuntimeStep -StepName 'profiles'")
    $packageManagersIndex = $agentEntryText.IndexOf("Add-AgentRuntimeStep -StepName 'package-managers'")
    $editorsIndex = $agentEntryText.IndexOf("Add-AgentRuntimeStep -StepName 'editors'")
    $auditIndex = $agentEntryText.IndexOf("Add-AgentRuntimeStep -StepName 'liveInstallAudit'")
    $failedIndex = $agentEntryText.IndexOf('$failed = @')
    if ($profilesIndex -lt 0 -or $packageManagersIndex -lt 0 -or $editorsIndex -lt 0 -or $auditIndex -lt 0 -or $failedIndex -lt 0 -or
        -not ($profilesIndex -lt $packageManagersIndex -and $packageManagersIndex -lt $editorsIndex -and $editorsIndex -lt $auditIndex -and $auditIndex -lt $failedIndex)) {
        Add-SmokeFailure 'Agent step runtime should run liveInstallAudit during final validation before failed-step evaluation.'
    }
}

function Assert-GitBootstrapDoesNotInstallFullGitByDefault {
    $agentProfile = New-WinMintAgentProfile -BuildConfig (New-WinMintBuildConfig -BuildProfile (New-SmokeBuildProfile))
    if ([bool]$agentProfile.modules.git.enabled) {
        Add-SmokeFailure 'Git bootstrap must remain disabled by default; users configure Git themselves unless a future FirstLogon dependency requires it.'
    }

    $gitModuleText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Modules\Git.ps1') -Raw
    if ($gitModuleText -notmatch 'MinGit') {
        Add-SmokeFailure 'Git module scaffold should document MinGit as the only acceptable FirstLogon Git dependency.'
    }
    foreach ($forbidden in @('Git.Git', 'GitForWindows', 'usr\bin\bash.exe')) {
        if ($gitModuleText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "Git module must not install or depend on full Git for Windows/Git Bash: '$forbidden'."
        }
    }

    $packagesText = Get-Content -LiteralPath (Join-Path $root 'config\packages.json') -Raw
    foreach ($forbidden in @('Git.Git', 'GitForWindows')) {
        if ($packagesText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "Package catalog must not default to full Git for Windows: '$forbidden'."
        }
    }
}

function Assert-StarshipPromptUsesNerdFontTerminalDefaults {
    $packagesText = Get-Content -LiteralPath (Join-Path $root 'config\packages.json') -Raw
    if ($packagesText -notmatch '(?s)"displayName"\s*:\s*"Starship".*"source"\s*:\s*"scoop"') {
        Add-SmokeFailure 'Starship catalog entry must be Scoop-owned.'
    }

    $packageManagerText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Modules\PackageManagers.ps1') -Raw
    foreach ($expected in @(
            'Install-AgentManifestTool -ToolId ''starship''',
            'preset'', ''nerd-font-symbols''',
            'Invoke-Expression (&starship init powershell)',
            'Get-WinMintAgentStarshipConfigPath',
            'Cascadia Code NF'
        )) {
        if ($packageManagerText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Starship package-manager bootstrap should contain '$expected'."
        }
    }

    $firstLogonText = Get-WinMintFirstLogonText
    $wslText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Modules\Wsl.ps1') -Raw
    foreach ($expected in @(
            'profiles.defaults.font.face',
            'profiles.defaults.colorScheme',
            'profiles.defaults.bellStyle',
            'centerOnLaunch',
            'Cascadia Code NF'
        )) {
        if ($firstLogonText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon terminal finalizer should enforce '$expected'."
        }
        if ($wslText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "WSL terminal profile updater should preserve '$expected'."
        }
    }
}

function Assert-AgentWingetUsesDefaultInstallerSelection {
    $runtimeText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Agent.Runtime.ps1') -Raw
    $packageManagerText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Modules\PackageManagers.ps1') -Raw
    $packagesText = Get-Content -LiteralPath (Join-Path $root 'config\packages.json') -Raw

    foreach ($expected in @(
        'Start-Process -FilePath $FilePath',
        'winget.exe',
        '--architecture'
    )) {
        if ($runtimeText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Agent runtime should invoke winget directly with '$expected'."
        }
    }
    foreach ($expected in @(
        'Invoke-WinMintAgentWingetUpgradeAll',
        '''upgrade''',
        '''--all''',
        '''--accept-source-agreements''',
        '''--accept-package-agreements''',
        'package-manager:winget-upgrade-all'
    )) {
        if ($packageManagerText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Package manager bootstrap should run and track winget upgrade --all with '$expected'."
        }
    }

    foreach ($forbidden in @(
        'Invoke-AgentLimitedUserCommand',
        'Join-AgentCommandLine',
        'ConvertTo-AgentPowerShellLiteral',
        '/RL LIMITED',
        '/RP $password',
        'WinMintAgentLimited',
        '--scope',
        '--ignore-dependencies',
        'installScope',
        'ignoreDependencies'
    )) {
        if ($runtimeText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "Agent runtime should not carry brittle winget override '$forbidden'."
        }
        if ($packagesText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "Package catalog should not carry brittle winget override '$forbidden'."
        }
    }
}

function Assert-OfficialUpdatePayloadAcquisition {
    $moduleText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\UpdatePayloads.ps1') -Raw
    $engineText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Engine.ps1') -Raw
    $entryText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\WinMint.ps1') -Raw
    foreach ($expected in @(
        'catalog.update.microsoft.com/Search.aspx',
        'catalog.update.microsoft.com/DownloadDialog.aspx',
        'ConvertFrom-WinMintCatalogBase64Sha256',
        'Save-WinMintVerifiedDownload',
        'Invoke-WinMintUpdatePayloadDownload',
        'Start-BitsTransfer',
        'definitionupdates.microsoft.com/packages?package=dismpackage',
        'Get-AuthenticodeSignature',
        'UpdatePayloadManifest.json',
        'Optional preview update acquisition is not allowed'
    )) {
        if ($moduleText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Official update payload acquisition should contain '$expected'."
        }
    }
    if ($engineText -notmatch 'Invoke-WinMintStable25H2UpdatePayloadAcquisition') {
        Add-SmokeFailure 'Engine must acquire official Stable25H2 payloads before enforcing update payload preflight.'
    }
    if ($entryText -notmatch 'Private\\UpdatePayloads\.ps1') {
        Add-SmokeFailure 'WinMint.ps1 must dot-source the update payload acquisition module.'
    }
}

function Assert-ElevationChecksUseInstanceMarshalSize {
    foreach ($relativePath in @(
        'src\runtime\setup\FirstLogon.Support.ps1',
        'src\runtime\firstlogon\Agent.Runtime.ps1'
    )) {
        $text = Get-Content -LiteralPath (Join-Path $root $relativePath) -Raw
        if ($text -match 'Marshal\]::SizeOf\(\[WinMint\.TokenElevation\+TOKEN_ELEVATION\]\)') {
            Add-SmokeFailure "$relativePath should marshal the TOKEN_ELEVATION instance, not the RuntimeType."
        }
        if ($text -notmatch [regex]::Escape('$size = [System.Runtime.InteropServices.Marshal]::SizeOf($elevation)')) {
            Add-SmokeFailure "$relativePath should compute TOKEN_ELEVATION size from the struct instance."
        }
    }
}

function Assert-NoMaintenancePayloadOrRegistration {
    $setupCompleteText = Get-WinMintSetupCompleteText
    $firstLogonText = Get-WinMintFirstLogonText
    $engineText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Engine.ps1') -Raw
    $setupPayloadText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\Image\SetupPayloadStaging.ps1') -Raw
    $maintenancePayload = Join-Path $root 'src\runtime\setup\Maintain.ps1'

    if (Test-Path -LiteralPath $maintenancePayload) {
        Add-SmokeFailure 'Maintenance payload must not live under src\runtime\setup.'
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
        $setupPayloadText -match [regex]::Escape("'Maintain.ps1'")) {
        Add-SmokeFailure 'Maintain.ps1 must not be staged as a default setup artifact.'
    }
}

function Assert-FirstLogonFailsClosedWhenElevationIsUnavailable {
    $firstLogonText = Get-WinMintFirstLogonText
    foreach ($expected in @(
        'Stop-WinMintFirstLogonUnelevated',
        "failure'] = 'notElevated'",
        'Set-WinMintFirstLogonRetry',
        'Set-WinMintFirstLogonAutoLogonPersistent',
        "Remove-Item -LiteralPath (Join-Path `$logDir 'FirstLogon_self-elevation.flag')",
        'exit 1',
        'aborting before machine-wide setup so RunOnce can retry'
    )) {
        if ($firstLogonText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon should fail closed when elevation is unavailable with '$expected'."
        }
    }
    foreach ($forbidden in @(
        'continuing with the standard token',
        'some machine-wide operations may fail'
    )) {
        if ($firstLogonText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "FirstLogon must not continue unelevated after self-elevation failure: '$forbidden'."
        }
    }
}

function Assert-FirstLogonRecoveryIsBounded {
    $firstLogonText = Get-WinMintFirstLogonText
    foreach ($expected in @(
        '$script:WinMintFirstLogonMaxAttempts = 3',
        'New-WinMintFirstLogonRunState',
        'Clear-WinMintFirstLogonRecovery',
        "recovery'] = 'exhausted'",
        'DefaultPassword',
        'AutoLogonCount',
        'retry cap reached'
    )) {
        if ($firstLogonText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon recovery/autologon must be bounded with '$expected'."
        }
    }
}

function Assert-FirstLogonCleanupOnlyDeletesWinMintOwnedPayload {
    $firstLogonText = Get-WinMintFirstLogonText
    $setupCompleteText = Get-WinMintSetupCompleteText
    foreach ($expected in @(
        'WinMintAgent',
        'WinMintSetupProfile.json',
        'WinMintSetupPlan.json',
        'SetupComplete.ps1',
        'Audit-LiveInstall.ps1',
        'WinMint-owned setup payloads'
    )) {
        if ($firstLogonText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon cleanup should explicitly remove WinMint-owned payload '$expected'."
        }
    }
    foreach ($expected in @('cleanupSpec', 'Resolve-WinMintCleanupPath', '-EncodedCommand', 'Resolve-WinMintPowerShellHost')) {
        if ($firstLogonText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon cleanup should use a constrained PowerShell cleanup helper with '$expected'."
        }
    }
    foreach ($expected in @(
        'Test-WinMintFirstLogonRetainDiagnosticState',
        "profileName -eq 'Hyper-V Test'",
        'retainDiagnosticState',
        'Hyper-V test diagnostic state retained'
    )) {
        if ($firstLogonText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon cleanup should retain diagnostic state for Hyper-V test builds with '$expected'."
        }
    }
    foreach ($expected in @(
        'WinMint post-install complete',
        'Enable-ComputerRestore',
        'Checkpoint-Computer',
        'MODIFY_SETTINGS',
        'final post-install restore point'
    )) {
        if ($firstLogonText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon final cleanup should create the post-install restore point with '$expected'."
        }
    }
    if ($setupCompleteText -match 'Checkpoint-Computer|Invoke-ScRestorePoint|Post-install \(SetupComplete\)') {
        Add-SmokeFailure 'SetupComplete must not create the restore point before FirstLogon finishes.'
    }
    foreach ($forbidden in @('cmd.exe', 'del /f', 'rmdir /s')) {
        if ($firstLogonText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "FirstLogon cleanup must not use shell-string deletion through '$forbidden'."
        }
    }
    if ($firstLogonText -match '\$directoryTargets\s*=\s*@\(\s*\r?\n\s*\$payloadDir\s*(?:,|\r?\n|\))') {
        Add-SmokeFailure 'FirstLogon cleanup must not include the whole Setup\Scripts payloadDir as a directory target.'
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
    if ($defaultDistros.Count -ne 0 -or -not [bool]$defaultProfile.development.wsl.enabled) {
        Add-SmokeFailure 'WSL must stay enabled by default even when no distro is selected.'
    }

    $emptySettings = New-SmokeBuildProfileSettings
    $emptySettings.Wsl2Distros = @()
    $emptyProfile = New-WinMintBuildProfile -Settings $emptySettings
    if (@($emptyProfile.development.wsl.distros).Count -ne 0 -or -not [bool]$emptyProfile.development.wsl.enabled) {
        Add-SmokeFailure 'Explicit empty Wsl2Distros must preserve the WSL2 baseline without adding a distro.'
    }

    $customSettings = New-SmokeBuildProfileSettings
    $customSettings.Wsl2Distros = @('Ubuntu', 'Fedora', 'archlinux', 'NixOS-WSL', 'Pengwin')
    $customProfile = New-WinMintBuildProfile -Settings $customSettings
    $customDistros = @($customProfile.development.wsl.distros)
    foreach ($distro in @('Ubuntu', 'FedoraLinux', 'archlinux', 'NixOS-WSL', 'pengwin')) {
        if ($customDistros -notcontains $distro) {
            Add-SmokeFailure "Expected custom WSL distro '$distro' to be preserved."
        }
    }
    $versionedFedoraSettings = New-SmokeBuildProfileSettings
    $versionedFedoraSettings.Wsl2Distros = @('FedoraLinux-44')
    $versionedFedoraProfile = New-WinMintBuildProfile -Settings $versionedFedoraSettings
    if (@($versionedFedoraProfile.development.wsl.distros) -notcontains 'FedoraLinux') {
        Add-SmokeFailure 'Versioned Fedora WSL distro selections must normalize to the latest FedoraLinux token.'
    }

    $guiStatePath = Join-Path $root 'apps\gui\src\state.rs'
    $guiStateText = Get-Content -LiteralPath $guiStatePath -Raw
    if ($guiStateText -notmatch 'keep:\s*KeepFlags::default\(\)') {
        Add-SmokeFailure 'GPUI BuildIntent must default to the subtractive keep-flag state (remove everything).'
    }
    if ($guiStateText -notmatch 'edition:\s*"Host"') {
        Add-SmokeFailure 'GPUI BuildIntent must default the edition selector to host detection.'
    }
    if ($coreProfileText -match 'wsl_ubuntu:\s*true' -or
        $coreProfileText -match 'wsl_fedora:\s*true' -or
        $coreProfileText -match 'wsl_archlinux:\s*true' -or
        $coreProfileText -match 'wsl_nixos_wsl:\s*true' -or
        $coreProfileText -match 'wsl_pengwin:\s*true' -or
        $coreProfileText -match 'nilesoft:\s*true' -or
        $guiStateText -match 'zed:\s*true' -or
        $guiStateText -match 'neovim:\s*true') {
        Add-SmokeFailure 'GPUI BuildIntent must not preselect editors or a WSL distro by default.'
    }

    $wslModulePath = Join-Path $root 'src\runtime\firstlogon\Modules\Wsl.ps1'
    $wslModuleText = Get-Content -LiteralPath $wslModulePath -Raw
    foreach ($expected in @(
        'dnsTunneling=true',
        'autoProxy=true',
        'localhostForwarding=true',
        'firewall=true',
        'autoMemoryReclaim=gradual',
        'sparseVhd=true',
        'Install-WinMintWindowsTerminalWslProfiles',
        'Get-WinMintWslTerminalIconPath',
        'New-WinMintWslTerminalProfile',
        'New-WinMintWindowsTerminalPowerShellProfile',
        'Windows.Terminal.WindowsPowerShell',
        'LocalState',
        'Icons',
        'ubuntu.png',
        'fedora.png',
        'archlinux.png',
        'nixos.png',
        'pengwin.png'
    )) {
        if ($wslModuleText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "WSL module should generate .wslconfig setting '$expected'."
        }
    }
    foreach ($expected in @('--update', '--web-download', 'Updating the WSL runtime.', 'Setting WSL 2 as the default version.')) {
        if ($wslModuleText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "WSL module should handle the runtime update path '$expected'."
        }
    }
    foreach ($expected in @(
        'Test-WinMintHyperVGuestWithoutNestedVirtualization',
        'Install-WinMintWindowsTerminalWslProfiles -Distros $distros',
        'ExposeVirtualizationExtensions $true',
        'WSL2 distro installation skipped',
        'nested virtualization is not exposed'
    )) {
        if ($wslModuleText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "WSL module should explain nested Hyper-V virtualization failures with '$expected'."
        }
    }
    if ($wslModuleText -notmatch 'WSL2 configured; no distro selected') {
        Add-SmokeFailure 'WSL module should explicitly handle the no-distro baseline.'
    }
    $updateIndex = $wslModuleText.IndexOf('Update-WinMintWslRuntime -WslPath $wsl.Source')
    $installIndex = $wslModuleText.IndexOf("Invoke-AgentNative -FilePath `$wsl.Source -ArgumentList @('--install', '--no-launch', '-d', `$distro)")
    $nixosInstallIndex = $wslModuleText.IndexOf('Install-WinMintNixOsWslDistribution -WslPath $wsl.Source')
    if ($updateIndex -lt 0 -or $installIndex -lt 0 -or $updateIndex -gt $installIndex) {
        Add-SmokeFailure 'WSL runtime update must occur before distro install attempts.'
    }
    if ($updateIndex -lt 0 -or $nixosInstallIndex -lt 0 -or $updateIndex -gt $nixosInstallIndex) {
        Add-SmokeFailure 'WSL runtime update must occur before the NixOS WSL installer path.'
    }
    foreach ($expected in @('nixos.aarch64.wsl', 'Get-AgentProcessorArchitecture', 'Architecture = (Get-AgentProcessorArchitecture)')) {
        if ($wslModuleText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "NixOS-WSL release selection should be architecture-aware with '$expected'."
        }
    }
    foreach ($forbiddenIcon in @('ubuntu.svg', 'fedora.svg', 'archlinux.svg', 'nixos.svg')) {
        if ($wslModuleText -match [regex]::Escape($forbiddenIcon)) {
            Add-SmokeFailure "WSL module Windows Terminal profiles must use staged PNG icons, not '$forbiddenIcon'."
        }
    }
    if ($wslModuleText -match 'networkingMode=mirrored') {
        Add-SmokeFailure 'WSL-first default must not force mirrored networking.'
    }
    $vmHarnessText = Get-Content -LiteralPath (Join-Path $root 'tools\vm\New-WinMintTestVm.ps1') -Raw
    if ($vmHarnessText -notmatch 'ExposeVirtualizationExtensions\s+\$true') {
        Add-SmokeFailure 'Hyper-V test VM harness must expose virtualization extensions for nested WSL2.'
    }
    foreach ($expected in @(
        'if ($NoConnect) { $SwitchName = '''' }',
        'if ($SwitchName -and -not $DelayNetworkUntilFirstLogon)'
    )) {
        if ($vmHarnessText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Hyper-V test VM harness should keep -NoConnect from attaching a VM network switch with '$expected'."
        }
    }
    $buildAndTestText = Get-Content -LiteralPath (Join-Path $root 'tools\vm\Build-And-TestVm.ps1') -Raw
    foreach ($expected in @(
        '$buildStartedAt',
        '$builtIso.FullName',
        "IsoPath   = `$builtIso.FullName",
        '$profileJson.identity.accountName',
        '$profileJson.identity.password',
        "GuestUser'] = `$guestUser",
        "GuestPassword'] = `$guestPassword"
    )) {
        if ($buildAndTestText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Build-And-TestVm.ps1 should boot the just-built ISO and use profile credentials with '$expected'."
        }
    }
    $strategyText = Get-Content -LiteralPath (Join-Path $root 'docs\Windows-Debloat-Strategy.md') -Raw
    foreach ($guard in @('WinMint is WSL2-first', 'Ubuntu LTS', '/home/<user>/code', 'networkingMode=nat')) {
        if ($strategyText -notmatch [regex]::Escape($guard)) {
            Add-SmokeFailure "WSL strategy should document '$guard'."
        }
    }
}

function Assert-LogNoiseInvariants {
    $pipelinePath = Join-Path $root 'src\runtime\image\Private\Pipeline.ps1'
    $displayPath = Join-Path $root 'src\runtime\image\Private\Console\Display.ps1'

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
    $catalogPath = Join-Path $root 'src\runtime\image\Private\Catalog.ps1'
    $stagingPath = Join-Path $root 'src\runtime\image\Private\Image\Staging.ps1'
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
    foreach ($expected in @('EdgeShoppingAssistantEnabled', 'ShowMicrosoftRewards', 'WebWidgetAllowed', 'CryptoWalletEnabled', 'HideFirstRunExperience', 'EdgeEnhanceImagesEnabled', 'BackgroundModeEnabled', 'StartupBoostEnabled', 'NewTabPageContentEnabled')) {
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
    foreach ($expected in @('DisableAIDataAnalysis', 'DisableClickToDo', 'AllowRecallEnablement', 'AllowRecallExport', 'TurnOffSavingSnapshots')) {
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

    $firstLogonText = Get-WinMintFirstLogonText
    $setupCompleteText = Get-WinMintSetupCompleteText
    $stagingText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\Image\Staging.ps1') -Raw
    $offlineOneDriveManifestText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\Manifest.ps1') -Raw
    $offlineOneDriveText = $stagingText + "`n" + $offlineOneDriveManifestText
    $pipelineText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\Pipeline.ps1') -Raw
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
        if ($offlineOneDriveText -notlike "*$expected*") {
            Add-SmokeFailure "Expected offline OneDrive setup-stub removal to include $expected."
        }
    }
    if ($pipelineText -notlike '*Remove-WinMintOneDriveSetupStub -MountDir $mountDir*') {
        Add-SmokeFailure 'Expected ISO pipeline to remove OneDrive setup stubs from the offline image.'
    }
}

function Assert-CursorInstallUsesModernRegistryContract {
    $catalogPath = Join-Path $root 'src\runtime\image\Private\Catalog.ps1'
    $assetsPath = Join-Path $root 'src\runtime\image\Private\Image\Assets.ps1'
    $assetsText = Get-Content -LiteralPath $assetsPath -Raw
    $firstLogonText = Get-WinMintFirstLogonText

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
    foreach ($expected in @('HKLM\peNTUSER', 'Control Panel\Cursors\Schemes', 'Default user cursor scheme applied')) {
        if ($assetsText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Cursor installation must write the Windows 11 user-scheme contract field '$expected'."
        }
    }
    if ($assetsText -notmatch '/v "\$schemeName" /t REG_EXPAND_SZ') {
        Add-SmokeFailure 'Cursor scheme list must be written as REG_EXPAND_SZ because it uses %SystemRoot% paths.'
    }
    foreach ($expected in @('Set-WinMintFirstLogonCursorScheme', 'HKCU\Control Panel\Cursors\Schemes', 'HKCU\Control Panel\Cursors', 'SPI_SETCURSORS', 'Live user cursor scheme applied')) {
        if ($firstLogonText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon should apply the cursor scheme to the live user profile with '$expected'."
        }
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

    $cloudContent = $script:RegistryTweaks | Where-Object id -eq 'cloud-content-policy' | Select-Object -First 1
    if (-not $cloudContent) {
        Add-SmokeFailure 'Expected cloud-content-policy registry tweak to exist.'
    }
    else {
        foreach ($expected in @(
                'DisableCloudOptimizedContent',
                'DisableConsumerAccountStateContent',
                'DisableSoftLanding',
                'DisableWindowsConsumerFeatures',
                'DisableWindowsSpotlightFeatures',
                'DisableWindowsSpotlightOnActionCenter',
                'DisableWindowsSpotlightOnSettings',
                'DisableWindowsSpotlightWindowsWelcomeExperience',
                'DisableShareAppPromotions',
                'DisableInlineCompose'
            )) {
            if (@($cloudContent.set | Where-Object name -eq $expected).Count -eq 0) {
                Add-SmokeFailure "Cloud content policy should stamp '$expected'."
            }
        }
        if (@($defaultConfig.RegistryTweaks) -notcontains 'cloud-content-policy') {
            Add-SmokeFailure 'cloud-content-policy must apply by default.'
        }
    }

    $explorer = $script:RegistryTweaks | Where-Object id -eq 'explorer-qol' | Select-Object -First 1
    if (-not $explorer) {
        Add-SmokeFailure 'Expected explorer-qol registry tweak to exist.'
    }
    else {
        foreach ($expected in @(
                @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'HideFileExt'; value = '0' },
                @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'Hidden'; value = '1' },
                @{ path = 'zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'LaunchTo'; value = '2' },
                @{ path = 'zNTUSER\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}'; name = 'System.IsPinnedToNameSpaceTree'; value = '0' }
            )) {
            $match = @($explorer.set | Where-Object {
                    [string]$_.path -eq [string]$expected.path -and
                    [string]$_.name -eq [string]$expected.name -and
                    [string]$_.value -eq [string]$expected.value
                })
            if ($match.Count -eq 0) {
                Add-SmokeFailure "Explorer QoL tweak must stamp $($expected.name) at $($expected.path)."
            }
        }
        if (@($explorer.set | Where-Object { [string]$_.path -like '*{f874310e-b6b7-47dc-bc84-b9e6b38f5903}*' }).Count -gt 0) {
            Add-SmokeFailure 'Explorer QoL tweak must not hide Home from the navigation pane.'
        }
    }
}

function Assert-SetupRegistryStampsAreIdempotent {
    $defaultUserPath = Join-Path $root 'src\runtime\setup\DefaultUser.ps1'
    $specializePath = Join-Path $root 'src\runtime\setup\Specialize.ps1'
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
            'ScoobeSystemSettingEnabled',
            'TaskbarMn',
            'ShowCopilotButton',
            'Start_AccountNotifications',
            'EnableAutoTray',
            'RotatingLockScreenEnabled',
            'RotatingLockScreenOverlayEnabled'
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
            'hide:home',
            'DeliveryOptimization',
            'DODownloadMode'
        )) {
        if ($specializeText -notlike "*$expected*") {
            Add-SmokeFailure "Specialize.ps1 should idempotently stamp '$expected'."
        }
    }
    if ($specializeText -notmatch 'DODownloadMode[\s\S]{0,220}-Data\s+0') {
        Add-SmokeFailure 'Specialize.ps1 should set DODownloadMode to 0 to disable Delivery Optimization peer-to-peer.'
    }

    foreach ($forbidden in @('ConsentPromptBehaviorAdmin', 'EnableLUA', 'DisableWindowsConsumerFeatures')) {
        if ($defaultUserText -like "*$forbidden*" -or $specializeText -like "*$forbidden*") {
            Add-SmokeFailure "Setup registry stamps must not include '$forbidden'."
        }
    }
}

function Assert-DefaultUserTaskbarPinsIncludeTerminal {
    $defaultUserPath = Join-Path $root 'src\runtime\setup\DefaultUser.ps1'
    $defaultUserText = Get-Content -LiteralPath $defaultUserPath -Raw
    if ($defaultUserText -notmatch 'Microsoft\.Windows\.Explorer') {
        Add-SmokeFailure 'DefaultUser taskbar layout must keep File Explorer pinned.'
    }
    if ($defaultUserText -notmatch 'Microsoft\.WindowsTerminal_8wekyb3d8bbwe!App') {
        Add-SmokeFailure 'DefaultUser taskbar layout must pin Windows Terminal.'
    }
    if ($defaultUserText -match 'stock pins .*re-pins only File Explorer') {
        Add-SmokeFailure 'DefaultUser taskbar pin comment must mention Windows Terminal as a baseline pin.'
    }
}

function Assert-WinMintBloomWallpaperCoversDesktopAndLockScreen {
    $unattendText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\Image\Unattend.ps1') -Raw
    $specializeText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\Specialize.ps1') -Raw
    $defaultUserText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\DefaultUser.ps1') -Raw
    $firstLogonText = Get-WinMintFirstLogonText

    foreach ($expected in @(
        'assets\runtime\wallpaper\img0.jpg',
        'assets\runtime\wallpaper\img100.jpg',
        'Windows\Web\Wallpaper\Windows\WinMint-Bloom.jpg',
        'Windows\Web\Screen\WinMint-Lock.jpg',
        'LockScreenImage',
        'WallpaperStyle',
        'TileWallpaper',
        'user.bmp'
    )) {
        if ($unattendText -notmatch [regex]::Escape($expected) -and
            $specializeText -notmatch [regex]::Escape($expected) -and
            $defaultUserText -notmatch [regex]::Escape($expected) -and
            $firstLogonText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Desktop/lock/account imagery should be staged through stock Windows locations: '$expected'."
        }
    }
    foreach ($forbidden in @(
        'Windows\Web\Wallpaper\WinMint',
        'WinMint-Bloom-OLED.png',
        'WslIcons',
        'AccountPictures',
        'SetUserTile'
    )) {
        if ($unattendText -match [regex]::Escape($forbidden) -or
            $specializeText -match [regex]::Escape($forbidden) -or
            $defaultUserText -match [regex]::Escape($forbidden) -or
            $firstLogonText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "Installed system imagery must not create WinMint-specific system folders or names: '$forbidden'."
        }
    }

    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $expectedPictures = @{
            'user.bmp' = 448
            'user.png' = 448
            'user-192.png' = 192
            'user-48.png' = 48
            'user-40.png' = 40
            'user-32.png' = 32
        }
        foreach ($name in $expectedPictures.Keys) {
            $path = Join-Path $root "assets\runtime\accountpicture\$name"
            if (-not (Test-Path -LiteralPath $path)) {
                Add-SmokeFailure "Default account picture asset is missing: $name."
                continue
            }
            $image = [System.Drawing.Image]::FromFile($path)
            try {
                $size = [int]$expectedPictures[$name]
                if ($image.Width -ne $size -or $image.Height -ne $size) {
                    Add-SmokeFailure "Default account picture '$name' should be ${size}x${size}; got $($image.Width)x$($image.Height)."
                }
            }
            finally {
                $image.Dispose()
            }
        }
    }
    catch {
        Add-SmokeFailure "Default account picture dimensions could not be verified: $($_.Exception.Message)"
    }
}

function Assert-WindowsTerminalDefaultsPwsh7NoLogo {
    $settingsPath = Join-Path $root 'assets\runtime\windows-terminal\settings.json'
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        Add-SmokeFailure 'Windows Terminal settings asset is missing.'
        return
    }
    $settingsText = Get-Content -LiteralPath $settingsPath -Raw
    foreach ($expected in @(
        'PowerShell',
        'defaultProfile',
        '-NoLogo',
        'pwsh.exe',
        'Cascadia Code NF',
        'One Half Dark',
        'bellStyle',
        'centerOnLaunch',
        '"font"',
        'disabledProfileSources',
        'Windows.Terminal.PowershellCore',
        'Windows.Terminal.Azure',
        'Windows.Terminal.SSH',
        'Windows.Terminal.Wsl',
        'Windows.Terminal.WindowsPowerShell'
    )) {
        if ($settingsText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Windows Terminal settings should contain '$expected'."
        }
    }
    foreach ($forbidden in @('"hidden": true', 'Command Prompt', 'Windows PowerShell', 'Azure Cloud Shell')) {
        if ($settingsText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "Windows Terminal settings should not contain stock profile '$forbidden'."
        }
    }
    try {
        $settings = $settingsText | ConvertFrom-Json
        if ([string]$settings.profiles.defaults.colorScheme -ne 'One Half Dark') {
            Add-SmokeFailure 'Windows Terminal default profile color scheme should be One Half Dark.'
        }
        if ([string]$settings.profiles.defaults.bellStyle -ne 'none') {
            Add-SmokeFailure 'Windows Terminal audible bell should be disabled by default.'
        }
        if (-not [bool]$settings.centerOnLaunch) {
            Add-SmokeFailure 'Windows Terminal should be centered on launch by default.'
        }
        $profiles = @($settings.profiles.list)
        if ($profiles.Count -ne 1 -or [string]$profiles[0].name -ne 'PowerShell') {
            Add-SmokeFailure 'Windows Terminal settings should ship exactly one base profile named PowerShell.'
        }
    }
    catch {
        Add-SmokeFailure "Windows Terminal settings should be valid JSON: $($_.Exception.Message)"
    }
}

function Assert-PowerShell7IsBundledAndRequired {
    $packagesText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\Image\Packages.ps1') -Raw
    foreach ($expected in @(
        'function Assert-OfflinePowerShell7Staged',
        'Resolve-WinMintGitHubReleasePayload',
        'PowerShell/PowerShell',
        'PowerShell-\d+\.\d+\.\d+-',
        'PowerShell 7 staged in the offline image',
        'PowerShell 7 is missing from the offline image',
        'PowerShell 7 staging failed; build cannot continue'
    )) {
        if ($packagesText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Offline PowerShell 7 staging should contain '$expected'."
        }
    }
    if ($packagesText -match 'fall back to Windows PowerShell') {
        Add-SmokeFailure 'PowerShell 7 staging must fail the build instead of falling back to Windows PowerShell.'
    }

    $pipelineText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\Pipeline.ps1') -Raw
    if ($pipelineText -notmatch 'Assert-OfflinePowerShell7Staged\s+-MountDir\s+\$mountDir') {
        Add-SmokeFailure 'Service WIM pipeline must assert bundled PowerShell 7 after servicing or serviced-WIM cache restore.'
    }

    $cacheText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\IntermediatesCache.ps1') -Raw
    if ($cacheText -notmatch '\$script:WinMintServicedWimCacheSchemaVersion\s*=\s*9') {
        Add-SmokeFailure 'Serviced-WIM cache schema should be bumped after adding the bundled PowerShell 7 image invariant.'
    }

    $setupCompleteCmd = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\SetupComplete.cmd') -Raw
    foreach ($expected in @(
        '%ProgramFiles%\PowerShell\7\pwsh.exe',
        'PowerShell 7 is required',
        'exit /b 1'
    )) {
        if ($setupCompleteCmd -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "SetupComplete.cmd should require staged PowerShell 7 with '$expected'."
        }
    }
    if ($setupCompleteCmd -match 'powershell\.exe[\s\S]{0,160}SetupComplete\.ps1') {
        Add-SmokeFailure 'SetupComplete.cmd must not run SetupComplete.ps1 under Windows PowerShell when PowerShell 7 is missing.'
    }

    $setupCompleteText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\SetupComplete.ps1') -Raw
    foreach ($expected in @(
        "Join-Path `$env:ProgramFiles 'PowerShell\7\pwsh.exe'",
        'PowerShell 7 is required for FirstLogon',
        '-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File',
        'under PowerShell 7'
    )) {
        if ($setupCompleteText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "SetupComplete.ps1 should register FirstLogon under PowerShell 7 with '$expected'."
        }
    }
    if ($setupCompleteText -match 'runOnceCommand\s*=\s*"powershell\.exe') {
        Add-SmokeFailure 'SetupComplete.ps1 must not register FirstLogon RunOnce under Windows PowerShell.'
    }

    $firstLogonRuntimeText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\FirstLogon.Runtime.ps1') -Raw
    foreach ($expected in @(
        'PowerShell 7 is bundled into the image and is required',
        'PowerShell 7 is required for FirstLogon',
        'PowerShell 7 re-launch failed',
        'return 1'
    )) {
        if ($firstLogonRuntimeText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon runtime should fail closed around PowerShell 7 with '$expected'."
        }
    }
    if ($firstLogonRuntimeText -match 'continuing under Windows PowerShell') {
        Add-SmokeFailure 'FirstLogon runtime must not continue under Windows PowerShell after PowerShell 7 handoff fails.'
    }

    $firstLogonSupportText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\FirstLogon.Support.ps1') -Raw
    foreach ($expected in @(
        'function Resolve-WinMintPowerShellHost',
        'PowerShell 7 is required for WinMint FirstLogon'
    )) {
        if ($firstLogonSupportText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "FirstLogon host resolution should require PowerShell 7 with '$expected'."
        }
    }

    $agentRuntimeText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Agent.Runtime.ps1') -Raw
    foreach ($expected in @(
        'function Resolve-AgentPowerShellHost',
        'PowerShell 7 is required for WinMint Agent'
    )) {
        if ($agentRuntimeText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Agent host resolution should require PowerShell 7 with '$expected'."
        }
    }
}

function Assert-PSScriptAnalyzerHonorsProjectSettings {
    $validationCoreText = Get-Content -LiteralPath (Join-Path $root 'tools\validation\Modules\Core.ps1') -Raw
    foreach ($expected in @(
        'PSScriptAnalyzerSettings.psd1',
        '$analyzerArgs.Settings = $settings',
        "@('Error', 'Warning')"
    )) {
        if ($validationCoreText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Validation analyzer pass should honor project settings and warning fallback with '$expected'."
        }
    }
    if ($validationCoreText -match [regex]::Escape('@{ Path = $target; Recurse = $true; Severity = @(''Error'') }')) {
        Add-SmokeFailure 'Validation analyzer pass must not force errors-only severity when project settings request warnings.'
    }
}

function Assert-XdgDefaultsAreStaged {
    $defaultUserPath = Join-Path $root 'src\runtime\setup\DefaultUser.ps1'
    $defaultUserText = Get-Content -LiteralPath $defaultUserPath -Raw
    $firstLogonText = Get-WinMintFirstLogonText
    foreach ($expected in @(
        'XDG_CONFIG_HOME',
        'XDG_DATA_HOME',
        'XDG_STATE_HOME',
        'XDG_CACHE_HOME',
        'XDG_RUNTIME_DIR',
        '%USERPROFILE%\.config',
        '%USERPROFILE%\.local\share',
        '%USERPROFILE%\.local\state',
        '%USERPROFILE%\.cache',
        '%USERPROFILE%\bin',
        '%USERPROFILE%\.local\bin',
        '%LOCALAPPDATA%\Temp\xdg-runtime'
    )) {
        if ($defaultUserText -notmatch [regex]::Escape($expected) -and $firstLogonText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "XDG defaults should stage '$expected'."
        }
    }
    foreach ($expected in @(
        'Add-WinMintFirstLogonUserPath',
        'bin',
        '.local\bin',
        'EnableClipboardHistory',
        'CloudClipboardAutomaticUpload',
        'Set-WinMintFirstLogonQuietUxDefaults',
        'Windows.SystemToast.BackupReminder',
        'Windows.SystemToast.Suggested',
        'TaskbarMn',
        'ShowCopilotButton',
        'Start_AccountNotifications',
        'EnableAutoTray',
        'RotatingLockScreenEnabled',
        'RotatingLockScreenOverlayEnabled'
    )) {
        if ($defaultUserText -notmatch [regex]::Escape($expected) -and $firstLogonText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Default profile and FirstLogon should stage user QoL default '$expected'."
        }
    }
    if ($defaultUserText -match [regex]::Escape('%LOCALAPPDATA%\Temp\WinMint\xdg-runtime') -or
        $firstLogonText -match [regex]::Escape('Temp\WinMint\xdg-runtime')) {
        Add-SmokeFailure 'XDG_RUNTIME_DIR must not leave a WinMint-named temp folder behind.'
    }
}
