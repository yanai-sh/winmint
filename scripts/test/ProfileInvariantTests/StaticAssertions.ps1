#Requires -Version 7.3

function Assert-StaticUiFlowInvariants {
    $statePath = Join-Path $root 'src\WinWS.UI\State\WinWSUiState.ps1'
    $xamlPath = Join-Path $root 'src\WinWS.UI\Views\MainWindow.xaml'
    $profileAdapterPath = Join-Path $root 'src\WinWS.UI\Services\ProfileAdapter.ps1'
    $themePath = Join-Path $root 'src\WinWS.UI\Services\Theme.ps1'

    $missingRewriteFiles = @()
    foreach ($path in @($statePath, $xamlPath, $profileAdapterPath, $themePath)) {
        if (-not (Test-Path -LiteralPath $path)) {
            Add-SmokeFailure "Expected UI rewrite file to exist: $path"
            $missingRewriteFiles += $path
        }
    }
    if ($missingRewriteFiles.Count -gt 0) { return }

    $stateText = Get-Content -LiteralPath $statePath -Raw
    $xamlText = Get-Content -LiteralPath $xamlPath -Raw
    $profileAdapterText = Get-Content -LiteralPath $profileAdapterPath -Raw
    $themeText = Get-Content -LiteralPath $themePath -Raw
    $stages = @('Start', 'Machine', 'Disk', 'Profile', 'Workstation', 'Launch')

    if ($stateText -notmatch '(?s)enum\s+WinWSUiStage\s*\{(?<Body>.*?)\}') {
        Add-SmokeFailure 'Expected WinWSUiState.ps1 to define enum WinWSUiStage.'
    } else {
        $stageBody = $Matches.Body
        foreach ($stage in $stages) {
            if ($stageBody -notmatch "(?m)^\s*$([regex]::Escape($stage))\b") {
                Add-SmokeFailure "Expected WinWSUiStage enum to contain '$stage'."
            }
        }
    }

    foreach ($stage in $stages) {
        if ($xamlText -notmatch "x:Name=`"Stage$stage`"") {
            Add-SmokeFailure "Expected MainWindow.xaml to contain Stage$stage."
        }
    }

    if ($xamlText -notmatch 'x:Name="StageStart"') {
        Add-SmokeFailure 'WinMint-UI.ps1 requires cinematic shell root StageStart in MainWindow.xaml.'
    }

    foreach ($requiredControl in @(
            'BtnNext', 'BtnBack', 'BtnBrowseIso', 'TxtIsoPath', 'TxtIsoStatus', 'TxtIsoArchitecture',
            'RbTargetThisPc', 'RbTargetDifferentPc', 'RbDriverDefault', 'RbDriverThisPc',
            'RbDriverCustom', 'TxtDriverPath', 'BtnDriverBrowse',
            'RbDiskManual', 'RbDiskAuto', 'ChkDiskWipeConfirm',
            'TxtComputerName', 'TxtAccountName', 'PwdPassword', 'PwdConfirm', 'ChkShellWindhawk',
            'ChkShellYasb', 'ChkShellKomorebi', 'ChkWslUbuntu', 'ChkWslDebian', 'ChkWslArch',
            'ChkWslFedora', 'ChkEditorNeovim', 'ChkEditorVSCodium', 'ChkEditorCursor', 'ChkEditorZed',
            'BtnStartBuild', 'BuildProgress', 'BuildStatusText', 'LogPanel'
        )) {
        if ($xamlText -notmatch "x:Name=`"$requiredControl`"") {
            Add-SmokeFailure "Expected MainWindow.xaml to contain control '$requiredControl'."
        }
    }

    foreach ($editionName in @('Windows 11 Home', 'Windows 11 Pro', 'Windows 11 Home Single Language')) {
        if ($profileAdapterText -notmatch [regex]::Escape($editionName)) {
            Add-SmokeFailure "Expected ProfileAdapter.ps1 to map fixed edition '$editionName'."
        }
    }

    if ($themeText -notmatch 'function\s+Set-Theme\b') {
        Add-SmokeFailure 'Expected Theme.ps1 to define Set-Theme.'
    }

    foreach ($forbidden in @('Tumbleweed', 'openSUSE')) {
        if ($stateText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "WinWSUiState.ps1 must not contain '$forbidden'."
        }
        if ($xamlText -match [regex]::Escape($forbidden)) {
            Add-SmokeFailure "MainWindow.xaml must not contain '$forbidden'."
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
    $headlessPath = Join-Path $root 'src\WinWS\Private\Headless.ps1'
    $enginePath = Join-Path $root 'src\WinWS\Engine.ps1'
    $cliText = Get-Content -LiteralPath $cliPath -Raw
    $headlessText = Get-Content -LiteralPath $headlessPath -Raw
    $engineText = Get-Content -LiteralPath $enginePath -Raw

    if ($cliText -notmatch "ContainsKey\('DryRun'\)") {
        Add-SmokeFailure 'WinMint-CLI.ps1 must route -DryRun through headless mode so tests never open the interactive ISO prompt.'
    }
    if ($headlessText -match 'Test-WinWSAdministrator\)\s+-and\s+-not\s+\$DryRun') {
        Add-SmokeFailure 'Headless elevation guard must not exempt -DryRun; UUP prep and ISO inspection still require admin.'
    }
    if ($headlessText -match 'Test-WinWSAdministrator\)\s+-and\s+-not\s+\$ValidateOnly') {
        Add-SmokeFailure 'Headless elevation guard must not exempt -ValidateOnly; validation still probes DISM/source/driver state.'
    }
    if ($engineText -match 'Test-WinWSAdministrator\)\s+-and\s+-not\s+\$DryRun') {
        Add-SmokeFailure 'Engine elevation guard must not exempt -DryRun.'
    }
    if ($headlessText -notmatch 'including -DryRun, -ValidateOnly, UUP source prep, and driver checks') {
        Add-SmokeFailure 'Headless elevation error should explain that dry-run, validate-only, source prep, and driver checks all require admin.'
    }
}

function Assert-HardwareBypassUnattendGeneration {
    $template = Get-Content -LiteralPath (Join-Path $root 'config\autounattend.xml') -Raw
    $common = @{
        MountDir = 'C:\WinWS-Mount'
        IsoContents = 'C:\WinWS-Iso'
        AutounattendTemplate = $template
        ImageArch = 'amd64'
        TimeZone = 'UTC'
        TargetPCName = 'WinWS'
        TargetUser = 'dev'
        TargetPass = ''
        EditionName = 'Windows 11 Pro'
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

    $bypass = Install-Autounattend @common -HardwareBypass:$true
    foreach ($valueName in @('BypassTPMCheck', 'BypassSecureBootCheck', 'BypassCPUCheck', 'BypassRAMCheck', 'BypassStorageCheck')) {
        if ([string]$bypass.AutounattendXml -notmatch [regex]::Escape($valueName)) {
            Add-SmokeFailure "Expected generated hardware-bypass autounattend to include $valueName."
        }
    }
}

function Assert-MicrosoftOobeUnattendGeneration {
    $common = @{
        MountDir = 'C:\Mount'
        IsoContents = 'C:\ISO'
        AutounattendTemplate = (Get-Content -LiteralPath (Join-Path (Get-WinWSRepositoryRoot) 'config\autounattend.xml') -Raw)
        ImageArch = 'arm64'
        TimeZone = 'Israel Standard Time'
        TargetPCName = 'SL7'
        TargetUser = 'Yanai'
        AccountMode = 'MicrosoftOobe'
        TargetPass = ''
        EditionName = 'Windows 11 Pro'
        EditionMode = 'TargetLicense'
        AutoWipeDisk = $true
        AutoLogon = $false
        HardwareBypass = $false
        InputLocale = 'en-US;he-IL'
        SystemLocale = 'he-IL'
        UILanguage = 'en-US'
        UILanguageFallback = 'en-US'
        UserLocale = 'he-IL'
        ScriptRoot = (Get-WinWSRepositoryRoot)
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
        AutounattendTemplate = (Get-Content -LiteralPath (Join-Path (Get-WinWSRepositoryRoot) 'config\autounattend.xml') -Raw)
        ImageArch = 'amd64'
        TimeZone = 'UTC'
        TargetPCName = 'WinWS'
        TargetUser = 'dev'
        AccountMode = 'Local'
        TargetPass = ''
        EditionName = 'Windows 11 Pro'
        EditionMode = 'TargetLicense'
        AutoWipeDisk = $false
        AutoLogon = $false
        HardwareBypass = $false
        InputLocale = 'en-US'
        SystemLocale = 'en-US'
        UILanguage = 'en-US'
        UILanguageFallback = 'en-US'
        UserLocale = 'en-US'
        ScriptRoot = (Get-WinWSRepositoryRoot)
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
    $setupCompletePath = Join-Path $root 'scripts\setup\SetupComplete.ps1'
    $setupCompleteText = Get-Content -LiteralPath $setupCompletePath -Raw
    if ($setupCompleteText -match '\bDisable-BitLocker\b') {
        Add-SmokeFailure 'SetupComplete.ps1 must not silently disable BitLocker; WinWS should only prevent surprise auto-encryption.'
    }
    if ($setupCompleteText -notmatch 'Leaving active BitLocker protection enabled') {
        Add-SmokeFailure 'SetupComplete.ps1 should log when active BitLocker protection is detected and preserved.'
    }
}

function Assert-ServiceabilityGuardrails {
    $packagesPath = Join-Path $root 'src\WinWS\Private\Image\Packages.ps1'
    $packagesText = Get-Content -LiteralPath $packagesPath -Raw
    if ($packagesText -match '/ResetBase') {
        Add-SmokeFailure 'Default image cleanup must not use /ResetBase; it removes component rollback and is only acceptable in an explicit tiny-image mode.'
    }

    $unattendTemplate = Get-Content -LiteralPath (Join-Path $root 'config\autounattend.xml') -Raw
    if ($unattendTemplate -match '<Compact>\s*true\s*</Compact>' -or $unattendTemplate -match '\bCompactOS\b') {
        Add-SmokeFailure 'Default autounattend must not force Compact OS; WinWS is performance-first, not smallest-possible.'
    }

    $common = @{
        MountDir = 'C:\WinWS-Mount'
        IsoContents = 'C:\WinWS-Iso'
        AutounattendTemplate = $unattendTemplate
        ImageArch = 'amd64'
        TimeZone = 'UTC'
        TargetPCName = 'WinWS'
        TargetUser = 'dev'
        TargetPass = 'passw0rd!'
        EditionName = 'Windows 11 Pro'
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
}

function Assert-ProtectedPlatformPackagesArePreserved {
    $allRemovalPrefixes = @(Get-WinWSEffectiveAppxRemovalPrefix -Settings @{
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
    $allRemovalPrefixes = @(Get-WinWSEffectiveAppxRemovalPrefix -Settings @{
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
            'Microsoft.RemoteDesktopPreview',
            'McAfee',
            'NortonLifeLock',
            'ExpressVPN',
            'Surfshark',
            'Piriform.CCleaner'
        )) {
        if ($allRemovalPrefixes -notcontains $expected) {
            Add-SmokeFailure "Expected Minimal AppX removal catalog to include '$expected'."
        }
    }
}

function Assert-PhoneLinkAgentDefaults {
    $profile = New-WinWSAgentProfile -BuildConfig (New-WinWSBuildConfig -BuildProfile (New-SmokeBuildProfile))
    if (-not [bool]$profile.modules.phoneLink.enabled) {
        Add-SmokeFailure 'Phone Link must be enabled by default in the agent profile.'
    }
    foreach ($setting in @('showInFileExplorer', 'crossDeviceCopyPaste', 'hideCrossDeviceHomeFolder')) {
        if (-not [bool]$profile.modules.phoneLink.$setting) {
            Add-SmokeFailure "Phone Link default profile should enable '$setting'."
        }
    }

    $agentPath = Join-Path $root 'src\WinWS.Agent\Modules\PhoneLink.ps1'
    $agentText = Get-Content -LiteralPath $agentPath -Raw
    foreach ($expected in @('CrossDevice', 'Hidden', 'System', 'EnableClipboardHistory', 'CloudClipboardAutomaticUpload')) {
        if ($agentText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Phone Link agent module should contain '$expected'."
        }
    }
}

function Assert-ConsumerUtilityPackagesNeverInRemovalList {
    $allRemovalPrefixes = @(Get-WinWSEffectiveAppxRemovalPrefix -Settings @{
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

function Assert-LiveInstallAuditIsNonDestructive {
    $auditPath = Join-Path $root 'scripts\audit\Audit-LiveInstall.ps1'
    if (-not (Test-Path -LiteralPath $auditPath)) {
        Add-SmokeFailure 'Expected scripts\audit\Audit-LiveInstall.ps1 to exist.'
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
    $auditText = Get-Content -LiteralPath (Join-Path $root 'scripts\audit\Audit-LiveInstall.ps1') -Raw
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
            'hns'
        )) {
        if ($auditText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Audit-LiveInstall.ps1 should probe platform guardrail '$expected'."
        }
    }
}

function Assert-LiveInstallAuditUsesSetupProfilePrefixes {
    $auditText = Get-Content -LiteralPath (Join-Path $root 'scripts\audit\Audit-LiveInstall.ps1') -Raw
    foreach ($expected in @('WinWSSetupProfile.json', 'appxRemovalPrefixes')) {
        if ($auditText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "Audit-LiveInstall.ps1 should use setup profile value '$expected'."
        }
    }
}

function Assert-LiveInstallAuditIsStaged {
    $unattendText = Get-Content -LiteralPath (Join-Path $root 'src\WinWS\Private\Image\Unattend.ps1') -Raw
    if ($unattendText -notmatch [regex]::Escape('Audit-LiveInstall.ps1')) {
        Add-SmokeFailure 'Install-Autounattend should stage Audit-LiveInstall.ps1 with setup scripts.'
    }
}

function Assert-AgentRunsLiveInstallAudit {
    $profile = New-WinWSAgentProfile -BuildConfig (New-WinWSBuildConfig -BuildProfile (New-SmokeBuildProfile))
    if (-not [bool]$profile.modules.liveInstallAudit.enabled) {
        Add-SmokeFailure 'Live install audit must be enabled by default in the agent profile.'
    }
    $agentModulePath = Join-Path $root 'src\WinWS.Agent\Modules\LiveInstallAudit.ps1'
    if (-not (Test-Path -LiteralPath $agentModulePath)) {
        Add-SmokeFailure 'Expected LiveInstallAudit agent module to exist.'
        return
    }
    $agentModuleText = Get-Content -LiteralPath $agentModulePath -Raw
    foreach ($expected in @('Invoke-WinWSAgentLiveInstallAuditBootstrap', 'liveInstallAudit', 'Audit-LiveInstall.ps1')) {
        if ($agentModuleText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "LiveInstallAudit agent module should contain '$expected'."
        }
    }
    $agentEntryText = Get-Content -LiteralPath (Join-Path $root 'src\WinWS.Agent\Start-WinWSAgent.ps1') -Raw
    if ($agentEntryText -notmatch "Invoke-AgentProfileModule -StepName 'profiles'[\s\S]*Invoke-AgentProfileModule -StepName 'liveInstallAudit'[\s\S]*Invoke-AgentProfileModule -StepName 'package-managers'") {
        Add-SmokeFailure 'Start-WinWSAgent.ps1 should run liveInstallAudit after profiles and before package managers.'
    }
}

function Assert-MaintainFallbackDoesNotRemovePlatformApps {
    $maintainPath = Join-Path $root 'scripts\setup\Maintain.ps1'
    $maintainText = Get-Content -LiteralPath $maintainPath -Raw
    foreach ($protectedPrefix in @('Microsoft.YourPhone', 'MicrosoftWindows.CrossDevice')) {
        if ($maintainText -match [regex]::Escape("'$protectedPrefix'")) {
            Add-SmokeFailure "Maintain.ps1 default prefix list must not include protected '$protectedPrefix'."
        }
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
    $defaultProfile = New-WinWSBuildProfile -Settings (New-SmokeBuildProfileSettings)
    $defaultDistros = @($defaultProfile.development.wsl.distros)
    if (@($defaultProfile.profileGroups) -notcontains 'Developer') {
        Add-SmokeFailure 'Smoke profile should include the Developer group.'
    }
    if ($defaultDistros.Count -ne 0 -or [bool]$defaultProfile.development.wsl.enabled) {
        Add-SmokeFailure 'Developer group must leave WSL unselected until a distro is explicitly selected.'
    }

    $optOutSettings = New-SmokeBuildProfileSettings
    $optOutSettings.Wsl2Distros = @()
    $optOutProfile = New-WinWSBuildProfile -Settings $optOutSettings
    if (@($optOutProfile.development.wsl.distros).Count -ne 0 -or [bool]$optOutProfile.development.wsl.enabled) {
        Add-SmokeFailure 'Explicit empty Wsl2Distros must opt out of WSL default distro selection.'
    }

    $customSettings = New-SmokeBuildProfileSettings
    $customSettings.Wsl2Distros = @('Debian', 'archlinux', 'FedoraLinux')
    $customProfile = New-WinWSBuildProfile -Settings $customSettings
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
    $versionedFedoraProfile = New-WinWSBuildProfile -Settings $versionedFedoraSettings
    if (@($versionedFedoraProfile.development.wsl.distros) -notcontains 'FedoraLinux-44') {
        Add-SmokeFailure 'Versioned Fedora WSL distro selections must be preserved in the build profile.'
    }

    $uiPath = Join-Path $root 'src\WinWS.UI\Views\MainWindow.xaml'
    $uiText = Get-Content -LiteralPath $uiPath -Raw
    if ($uiText -match 'x:Name="ChkWslUbuntu"[\s\S]*?IsChecked="True"') {
        Add-SmokeFailure 'UI must not preselect Ubuntu WSL by default.'
    }

    $wslModulePath = Join-Path $root 'src\WinWS.Agent\Modules\Wsl.ps1'
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
    foreach ($guard in @('WinWS is WSL2-first', 'Ubuntu LTS', '/home/<user>/code', 'networkingMode=nat')) {
        if ($strategyText -notmatch [regex]::Escape($guard)) {
            Add-SmokeFailure "WSL strategy should document '$guard'."
        }
    }
}

function Assert-LogNoiseInvariants {
    $pipelinePath = Join-Path $root 'src\WinWS\Private\Pipeline.ps1'
    $displayPath = Join-Path $root 'src\WinWS\Private\Console\Display.ps1'

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
    if ($displayText -notmatch 'WinWSActionTimingVisibleThresholdSeconds') {
        Add-SmokeFailure 'Expected Invoke-Action timing summaries to use a visible-duration threshold.'
    }
}

function Assert-WinPEDriverInjectionDefaultsToSetupOnly {
    $catalogPath = Join-Path $root 'src\WinWS\Private\Catalog.ps1'
    $stagingPath = Join-Path $root 'src\WinWS\Private\Image\Staging.ps1'
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

function Assert-EdgePolicyPreservesCopilotSidebar {
    $minimal = $script:RegistryTweaks | Where-Object id -eq 'edge-policy-minimal' | Select-Object -First 1
    $copilotPlus = $script:RegistryTweaks | Where-Object id -eq 'edge-policy-copilotplus' | Select-Object -First 1
    if (-not $minimal -or -not $copilotPlus) {
        Add-SmokeFailure 'Expected both edge-policy-minimal and edge-policy-copilotplus registry tweaks to exist.'
        return
    }
    foreach ($expectedStrict in @('HubsSidebarEnabled', 'StandaloneHubsSidebarEnabled', 'WebWidgetAllowed', 'EdgeEnhanceImagesEnabled')) {
        if (@($minimal.set | Where-Object name -eq $expectedStrict).Count -eq 0) {
            Add-SmokeFailure "Expected Minimal Edge policy to set $expectedStrict."
        }
        if (@($copilotPlus.set | Where-Object name -eq $expectedStrict).Count -gt 0) {
            Add-SmokeFailure "CopilotPlus Edge policy must not disable $expectedStrict."
        }
    }
    foreach ($expected in @('EdgeShoppingAssistantEnabled', 'ShowMicrosoftRewards', 'WebWidgetAllowed', 'CryptoWalletEnabled', 'HideFirstRunExperience')) {
        if (@($minimal.set | Where-Object name -eq $expected).Count -eq 0) {
            Add-SmokeFailure "Expected Edge noise policy to set $expected."
        }
    }
    foreach ($expected in @('EdgeShoppingAssistantEnabled', 'ShowMicrosoftRewards', 'CryptoWalletEnabled', 'HideFirstRunExperience')) {
        if (@($copilotPlus.set | Where-Object name -eq $expected).Count -eq 0) {
            Add-SmokeFailure "Expected CopilotPlus Edge noise policy to set $expected."
        }
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

    $firstLogonPath = Join-Path $root 'scripts\setup\FirstLogon.ps1'
    $setupCompletePath = Join-Path $root 'scripts\setup\SetupComplete.ps1'
    $maintainPath = Join-Path $root 'scripts\setup\Maintain.ps1'
    $firstLogonText = Get-Content -LiteralPath $firstLogonPath -Raw
    $setupCompleteText = Get-Content -LiteralPath $setupCompletePath -Raw
    $maintainText = Get-Content -LiteralPath $maintainPath -Raw
    $stagingText = Get-Content -LiteralPath (Join-Path $root 'src\WinWS\Private\Image\Staging.ps1') -Raw
    $pipelineText = Get-Content -LiteralPath (Join-Path $root 'src\WinWS\Private\Pipeline.ps1') -Raw
    foreach ($expected in @(
            'FirstLogon_OneDriveAudit.json',
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
            'Invoke-MaintOneDriveRemoval',
            'DisableFileSyncNGSC',
            'OneDriveSetup.exe.bak',
            'Active Setup\Installed Components',
            'StartupApproved\Run',
            'SyncRootManager',
            'App Paths',
            'Unregister-ScheduledTask'
        )) {
        if ($maintainText -notlike "*$expected*") {
            Add-SmokeFailure "Expected Maintain OneDrive cleanup to include $expected."
        }
    }
    foreach ($expected in @(
            'Remove-WinWSOneDriveSetupStub',
            'Windows\System32\OneDriveSetup.exe',
            'Windows\SysWOW64\OneDriveSetup.exe',
            'oneDriveSetupStubs',
            'users can reinstall OneDrive later'
        )) {
        if ($stagingText -notlike "*$expected*") {
            Add-SmokeFailure "Expected offline OneDrive setup-stub removal to include $expected."
        }
    }
    if ($pipelineText -notlike '*Remove-WinWSOneDriveSetupStub -MountDir $mountDir*') {
        Add-SmokeFailure 'Expected ISO pipeline to remove OneDrive setup stubs from the offline image.'
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
            $value = Get-WinWSProfileSetting $group $field $null
            if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) {
                Add-SmokeFailure "Registry tweak '$id' must define metadata field '$field'."
            }
        }
        if ([bool](Get-WinWSProfileSetting $group 'reversible' $false)) {
            $rollbackOps = @(
                foreach ($entry in @(Get-WinWSProfileSetting $group 'set' @())) {
                    if ($null -ne (Get-WinWSProfileSetting $entry 'undo' $null)) { $entry }
                }
                foreach ($entry in @(Get-WinWSProfileSetting $group 'remove' @())) {
                    if ($null -ne (Get-WinWSProfileSetting $entry 'restore' $null)) { $entry }
                }
            )
            if ($rollbackOps.Count -eq 0) {
                Add-SmokeFailure "Reversible registry tweak '$id' must include at least partial rollback metadata."
            }
        }
    }

    foreach ($publicTweak in $publicTweaks) {
        $id = [string]$publicTweak.id
        $docOnly = [bool](Get-WinWSProfileSetting $publicTweak 'documentationOnly' $false)
        if ($executableIds -notcontains $id -and -not $docOnly) {
            Add-SmokeFailure "Public tweak '$id' must map to an executable tweak or be marked documentationOnly."
        }
        foreach ($field in @('id', 'description', 'scope', 'risk', 'reversible', 'phase', 'intent')) {
            $value = Get-WinWSProfileSetting $publicTweak $field $null
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

    $defaultConfig = New-WinWSBuildConfig -BuildProfile (New-SmokeBuildProfile)
    if (@($defaultConfig.RegistryTweaks) -contains 'hardware-bypass') {
        Add-SmokeFailure 'hardware-bypass must remain opt-in and absent from default registry tweaks.'
    }
    if (@($defaultConfig.RegistryTweaks) -notcontains 'uac-no-secure-desktop') {
        Add-SmokeFailure 'Default registry tweaks should keep UAC prompts but disable secure-desktop dimming.'
    }
    $uac = $script:RegistryTweaks | Where-Object id -eq 'uac-no-secure-desktop' | Select-Object -First 1
    if (-not $uac) {
        Add-SmokeFailure 'Expected uac-no-secure-desktop registry tweak to exist.'
    }
    elseif (@($uac.set | Where-Object { $_.name -eq 'ConsentPromptBehaviorAdmin' -or $_.name -eq 'EnableLUA' }).Count -gt 0) {
        Add-SmokeFailure 'UAC dimming tweak must not disable UAC consent or EnableLUA.'
    }
}

function Assert-SetupRegistryStampsAreIdempotent {
    $defaultUserPath = Join-Path $root 'scripts\setup\DefaultUser.ps1'
    $specializePath = Join-Path $root 'scripts\setup\Specialize.ps1'
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
