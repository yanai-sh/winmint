#Requires -Version 7.6
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:WinMintRepositoryRoot = $root

. (Join-Path $root 'src\runtime\image\Core.ps1')
. (Join-Path $root 'src\runtime\image\Private\Config\OptionCatalog.ps1')
. (Join-Path $root 'src\runtime\image\Private\Config\Profile.ps1')
. (Join-Path $root 'src\runtime\image\Private\Catalog.ps1')
. (Join-Path $root 'src\runtime\image\Private\Image\Tweaks\TweakRegistry.ps1')
. (Join-Path $root 'src\runtime\image\Private\Image\AiRemoval.ps1')
. (Join-Path $root 'src\runtime\image\Private\IntermediatesCache.ps1')
. (Join-Path $root 'src\runtime\image\Private\Manifest.ps1')
. (Join-Path $root 'src\runtime\image\Engine.ps1')
. (Join-Path $root 'src\runtime\image\Reports.ps1')
. (Join-Path $root 'src\runtime\image\Private\WslSelection.ps1')
. (Join-Path $root 'src\runtime\image\Private\Runtime.ps1')
. (Join-Path $root 'src\runtime\image\Private\PayloadStore.ps1')
. (Join-Path $root 'src\runtime\image\Private\UpdatePayloads.ps1')
. (Join-Path $root 'src\runtime\image\Private\Image\Drivers.ps1')
. (Join-Path $root 'src\runtime\image\Private\Image\Packages.ps1')
. (Join-Path $root 'src\runtime\image\Private\Media.ps1')
. (Join-Path $root 'src\runtime\image\Private\Image\Tweaks.ps1')
. (Join-Path $root 'src\runtime\image\Private\Image\SetupPayloadStaging.ps1')
. (Join-Path $root 'src\runtime\image\Private\Image\Unattend.ps1')
. (Join-Path $root 'src\runtime\image\Private\InstallPlan.ps1')
. (Join-Path $root 'src\runtime\image\Private\Pipeline.Console.ps1')
. (Join-Path $root 'src\runtime\image\Private\Headless.ps1')
. (Join-Path $root 'src\runtime\image\Cli.ps1')
. (Join-Path $root 'tools\vm\WinMint-VmAcceptanceProfile.ps1')

$failures = [System.Collections.Generic.List[string]]::new()

if (-not (Get-Command Write-SectionHeader -ErrorAction SilentlyContinue)) {
    function Write-SectionHeader { param([string]$Title) [void]$Title }
}
if (-not (Get-Command Log -ErrorAction SilentlyContinue)) {
    function Log { param([string]$Message) [void]$Message }
}
if (-not (Get-Command LogOK -ErrorAction SilentlyContinue)) {
    function LogOK { param([string]$Message) [void]$Message }
}
if (-not (Get-Command LogWarn -ErrorAction SilentlyContinue)) {
    function LogWarn { param([string]$Message) [void]$Message }
}
if (-not (Get-Command LogVerbose -ErrorAction SilentlyContinue)) {
    function LogVerbose { param([string]$Message) [void]$Message }
}
if (-not (Get-Command Write-SpectreKeyValueTable -ErrorAction SilentlyContinue)) {
    function Write-SpectreKeyValueTable { param([object[]]$Rows) [void]$Rows }
}
if (-not (Get-Command Test-WinMintAdministrator -ErrorAction SilentlyContinue)) {
    function Test-WinMintAdministrator { return $true }
}

function Add-SmokeFailure {
    param([string]$Message)
    $failures.Add($Message) | Out-Null
    Write-Error $Message -ErrorAction Continue
}

foreach ($part in @(
    '..\TestFixtures.ps1',
    'StaticAssertions.ps1',
    'ProfileAssertions.ps1'
)) {
    . (Join-Path $PSScriptRoot "ProfileInvariantTests\$part")
}

Assert-PayloadCopyPreservesRootAndFolders
Assert-MountedImagePathIgnoresInvalidRecords
Assert-OscdimgSelectionPrefersNativeHostArchitecture
Assert-IsoBootUsesNoPromptEfiWhenAvailable
Assert-BuildResultContractAcceptsPipelineOutput
Assert-StartBuildReturnsSingleResultContract
Assert-ManifestPayloadsAreDeduplicated
Assert-FormFactorAndPowerProfile
Assert-TweakAuditArtifactsAreWritten
Assert-XdgDefaultsAreStaged
Assert-CachedDownloadResolver
Assert-OfflinePayloadCacheStatus
Assert-ImageUpdateProfileContract
Assert-UpdatePayloadHashHelpers
Assert-OfficialUpdatePayloadAcquisition
Assert-StaticUiFlowInvariants
Assert-HardwareBypassIsExplicit
Assert-ElevationRequiredForAllRuns
Assert-HardwareBypassUnattendGeneration
Assert-HyperVProfileIsProAndUnattended
Assert-GitHubApiReachabilityContract
Assert-TrackedHardwareBuildProfiles
Assert-FixedEditionSelectionIsUnambiguous
Assert-MicrosoftOobeUnattendGeneration
Assert-LocalAccountUnattendGeneration
Assert-SetupCompleteDoesNotDecryptBitLocker
Assert-ServiceabilityGuardrails
Assert-ProtectedPlatformPackagesArePreserved
Assert-MinimalAppxRemovalCatalogCoversPolicy
Assert-HomeFirstDefaultsAndPolicySurface
Assert-PhoneLinkAgentDefaults
Assert-PhoneLinkAppxRemovedByDefault
Assert-ConsumerUtilityPackagesNeverInRemovalList
Assert-LiveInstallAuditIsNonDestructive
Assert-LiveInstallAuditCoversPlatformGuardrails
Assert-LiveInstallAuditUsesSetupProfilePrefixes
Assert-LiveInstallAuditIsStaged
Assert-OfflineFontAllowlist
Assert-DmaRestoreRunsBeforeOptionalFirstLogonWork
Assert-DmaInteropUsesFixedIrelandRegion
Assert-BuildProfileSchemaOwnsBrowserContract
Assert-LiveAuditDistinguishesDmaSetupFromVisibleRegion
Assert-AiRemovalCatalogAndGuardrails
Assert-RecoveryBundleIsOutputOnly
Assert-AgentRunsLiveInstallAudit
Assert-GitBootstrapDoesNotInstallFullGitByDefault
Assert-StarshipPromptUsesNerdFontTerminalDefaults
Assert-AgentWingetUsesDefaultInstallerSelection
Assert-ElevationChecksUseInstanceMarshalSize
Assert-WinMintRuntimeCommonContracts
Assert-FirstLogonFailsClosedWhenElevationIsUnavailable
Assert-FirstLogonElevationGuaranteeIsSingleton
Assert-FirstLogonRecoveryIsBounded
Assert-FirstLogonCleanupOnlyDeletesWinMintOwnedPayload
Assert-NoMaintenancePayloadOrRegistration
Assert-ExternalReferenceAuditDocumentsSparkle
Assert-WslFirstDefaultsAndGuards
Assert-LogNoiseInvariants
Assert-WinPEDriverInjectionDefaultsToSetupOnly
Assert-CopilotPlusUsesFullAiRemovalPolicy
Assert-OneDriveRemovalPolicyIsComplete
Assert-DefaultUserTaskbarPinsIncludeTerminal
Assert-WindowsTerminalDefaultsPwsh7NoLogo
Assert-PowerShell7IsBundledAndRequired
Assert-SetupAndFirstLogonCatalogsAreExplicit
Assert-WinMintBloomWallpaperCoversDesktopAndLockScreen
Assert-FirstLogonDefaultsToVisibleConsole
Assert-SetupShellNativeDesign
Assert-WinMintVmManagedAcceptanceContract
Assert-WinMintVmPostSetupCheckpointContract
Assert-FirstLogonDemoHarnessIsNonMutating
Assert-FirstLogonPinsSelectedAppsToStart
Assert-FirstLogonFinalizesTerminalProfiles
Assert-AgentLiveInstallFailuresAreWarnings
Assert-AgentConsolePresentationSeam
Assert-SetupCompleteRegistersFirstLogonFallback
Assert-SetupCompleteDoesNotDeleteWindowsOld
Assert-EdgeRemovalIntentDoesNotDependOnDma
Assert-AutoTimeZoneUpdaterFollowsLocationServices
Assert-PSScriptAnalyzerHonorsProjectSettings
Assert-CursorInstallUsesModernRegistryContract
Assert-RegistryTweakMetadataAndRollback
Assert-SetupRegistryStampsAreIdempotent
Assert-HeadlessConsoleProfileContract
Assert-HeadlessCliContracts
Assert-HeadlessSourceAndDriverInputContracts
Assert-UiBridgeBuildProfileContract

$profile = New-SmokeBuildProfile
$result = Test-WinMintBuildProfile -BuildProfile $profile
if (-not $result.Passed) {
    Add-SmokeFailure "Expected generated profile to pass validation, got: $($result.Failures -join '; ')"
}
if ([int]$profile.schemaVersion -ne 4) { Add-SmokeFailure 'Expected generated profiles to use schemaVersion 4.' }
if (-not [bool]$profile.posture.setup.dmaInterop) { Add-SmokeFailure 'Expected generated profiles to enable DMA interop by default.' }
if ([string]$profile.privacy.locationServices -ne 'enabled') { Add-SmokeFailure 'Expected generated profiles to enable location services by default.' }
if ($profile.regional.userLocale -ne 'en-US' -or [int]$profile.regional.homeLocationGeoId -ne 244) {
    Add-SmokeFailure 'Expected generated profiles to default visible region to en-US/GeoID 244.'
}
$config = New-WinMintBuildConfig -BuildProfile $profile
if ($config.AppxPackages -notcontains 'Microsoft.Copilot' -or $config.AppxPackages -notcontains 'MicrosoftWindows.Client.WebExperience') {
    Add-SmokeFailure 'Expected Minimal setup option to remove Copilot and WebExperience packages.'
}
$setupProfile = New-WinMintInstallPlanSetupProfile -BuildConfig $config
if ($setupProfile.setupComplete.Contains('preserveMicrosoftCopilot')) {
    Add-SmokeFailure 'Deprecated setupComplete.preserveMicrosoftCopilot must not be generated.'
}
if (-not $setupProfile.setupComplete.removeRecall) {
    Add-SmokeFailure 'Expected Minimal setup option to remove Recall.'
}
if (-not [bool]$setupProfile.edge.removeEdge -or [bool]$setupProfile.edge.keepEdge) {
    Add-SmokeFailure 'Expected default setup profile to request Edge removal intent unless KeepEdge is selected.'
}
if ($setupProfile.edge.Contains('aggressiveExperimental')) {
    Add-SmokeFailure 'Edge removal must not be controlled by an environment-variable experimental gate.'
}

# Subtractive model: -KeepCopilot suppresses the non-Recall AI feature policy so
# a Copilot+ PC keeps app-local AI and the Copilot app surface, but Recall stays
# removed on every build as a security baseline.
$settings = New-SmokeBuildProfileSettings
$settings.KeepCopilot = $true
$profile = New-WinMintBuildProfile -Settings $settings
if (-not [bool]$profile.keep.copilot) { Add-SmokeFailure 'Expected KeepCopilot to flow into profile.keep.copilot.' }
$config = New-WinMintBuildConfig -BuildProfile $profile
if (-not [bool]$config.Keep.Copilot) { Add-SmokeFailure 'Expected KeepCopilot to flow into build config Keep.Copilot.' }
if ($config.AppxPackages -contains 'Microsoft.Copilot' -or $config.AppxPackages -contains 'Microsoft.Windows.AIHub') {
    Add-SmokeFailure 'Expected KeepCopilot to keep the Copilot app and AI hub AppX packages.'
}
if ($config.AppxPackages -notcontains 'MicrosoftWindows.Client.WebExperience') {
    Add-SmokeFailure 'Expected KeepCopilot to still remove the WebExperience package.'
}
if ($config.RegistryTweaks -notcontains 'edge-policy-minimal') { Add-SmokeFailure 'Expected the strict Edge noise policy to apply even with KeepCopilot.' }
if ($config.RegistryTweaks -contains 'windows-ai-features-removal') { Add-SmokeFailure 'Expected KeepCopilot to suppress the AI feature removal policy.' }
if ($config.RegistryTweaks -notcontains 'windows-ai-recall-policy') { Add-SmokeFailure 'Expected Recall removal policy to apply even with KeepCopilot.' }
$setupProfile = New-WinMintInstallPlanSetupProfile -BuildConfig $config
if ($setupProfile.setupComplete.Contains('preserveMicrosoftCopilot')) {
    Add-SmokeFailure 'Deprecated setupComplete.preserveMicrosoftCopilot must not be generated.'
}
if (-not $setupProfile.setupComplete.removeRecall) {
    Add-SmokeFailure 'Expected KeepCopilot builds to still remove Recall.'
}
if ($setupProfile.aiRemoval.policy -ne 'ServiceableFull') {
    Add-SmokeFailure 'Expected AI removal policy to remain ServiceableFull by default.'
}

$profile = New-WinMintBuildProfile -Settings (New-SmokeBuildProfileSettings)
$config = New-WinMintBuildConfig -BuildProfile $profile
if ($config.CursorPackKind -ne 'Windows11Modern') { Add-SmokeFailure 'Expected Windows11Modern cursor pack in build config.' }
if ($config.Tweaks.UpdatePolicy -ne 'All') { Add-SmokeFailure 'Expected All update policy in build config.' }
if ([string]$config.Updates.Mode -ne 'None') { Add-SmokeFailure 'Expected offline image updates to be disabled by default.' }
if ($config.ExportHostDrivers) { Add-SmokeFailure 'Expected host driver export to be disabled for drivers.source None.' }
if ($config.RegistryTweaks -contains 'hardware-bypass') { Add-SmokeFailure 'hardware-bypass must not be in the default registry tweaks for a standard build.' }
if ($config.RegistryTweaks -notcontains 'edge-policy-minimal') { Add-SmokeFailure 'Expected Minimal builds to use the strict Edge policy.' }
if ($config.RegistryTweaks -contains 'edge-policy-copilotplus') { Add-SmokeFailure 'Minimal builds must not use the CopilotPlus Edge policy.' }
$setupProfile = New-WinMintInstallPlanSetupProfile -BuildConfig $config
if (-not $setupProfile.privacy.telemetryHardening) { Add-SmokeFailure 'Expected default setup profile telemetry hardening to be enabled.' }
if (-not $setupProfile.privacy.location) { Add-SmokeFailure 'Location services must default to enabled for the laptop-first Home baseline.' }
if (-not [bool]$setupProfile.regional.dmaInterop.enabled -or $setupProfile.regional.dmaInterop.setupCountry -ne 'Ireland' -or [int]$setupProfile.regional.dmaInterop.setupHomeLocationGeoId -ne 68) {
    Add-SmokeFailure 'DMA interop must default on and use the Ireland setup latch.'
}
$agentProfile = New-WinMintInstallPlanAgentProfile -BuildConfig $config
if (@($config.Editors).Count -ne 0) {
    Add-SmokeFailure 'Expected the default build to leave editor options unselected.'
}
if ($config.Features -notcontains 'Microsoft-Windows-Subsystem-Linux' -or
    $config.Features -notcontains 'VirtualMachinePlatform') {
    Add-SmokeFailure 'Expected the default build to include WSL2 and Virtual Machine Platform as a baseline.'
}
if (-not [bool]$agentProfile.modules.wsl.enabled -or @($agentProfile.modules.wsl.distros).Count -ne 0) {
    Add-SmokeFailure 'Expected the default build to keep the FirstLogon WSL module enabled with no distro selected.'
}

$profile = New-WinMintBuildProfile -Settings @{
    Profile = 'Minimal'
    ProfileGroups = @('Minimal')
    ISOPath = (Get-WinMintTestIsoFixturePath)
    Architecture = 'arm64'
    ComputerName = 'WinMint'
    AccountName = 'dev'
    DriverSource = 'None'
    DriverPath = ''
}
$config = New-WinMintBuildConfig -BuildProfile $profile
$agentProfile = New-WinMintInstallPlanAgentProfile -BuildConfig $config
if (-not $agentProfile.modules.packageManagers.enabled) {
    Add-SmokeFailure 'Expected package managers to be enabled for the baseline Scoop + MinGit bootstrap.'
}

$profile = New-SmokeBuildProfile
$profile.development.editors = @()
$profile.desktop.layers = @('standard', 'yasb')
$config = New-WinMintBuildConfig -BuildProfile $profile
$agentProfile = New-WinMintInstallPlanAgentProfile -BuildConfig $config
if (-not $agentProfile.modules.packageManagers.enabled) {
    Add-SmokeFailure 'Expected package managers to be enabled when the YASB layer is selected.'
}
if (-not $agentProfile.modules.shell.yasb) {
    Add-SmokeFailure 'Expected YASB shell layer to flow into the agent profile.'
}
if ($agentProfile.modules.shell.whkd) {
    Add-SmokeFailure 'Expected YASB not to enable whkd without Komorebi.'
}

$profile = New-SmokeBuildProfile
$profile.development.editors = @()
$profile.desktop.layers = @('standard', 'komorebi')
$config = New-WinMintBuildConfig -BuildProfile $profile
$agentProfile = New-WinMintInstallPlanAgentProfile -BuildConfig $config
if (-not $agentProfile.modules.packageManagers.enabled) {
    Add-SmokeFailure 'Expected package managers to be enabled when the Komorebi layer is selected.'
}
if (-not $agentProfile.modules.shell.komorebi) {
    Add-SmokeFailure 'Expected Komorebi shell layer to flow into the agent profile.'
}
if (-not $agentProfile.modules.shell.whkd) {
    Add-SmokeFailure 'Expected Komorebi to enable whkd in the agent profile.'
}

$profile = New-SmokeBuildProfile
$profile.development.editors = @()
$profile.desktop.layers = @('standard', 'windhawk')
$config = New-WinMintBuildConfig -BuildProfile $profile
$agentProfile = New-WinMintInstallPlanAgentProfile -BuildConfig $config
if (-not $agentProfile.modules.packageManagers.enabled) {
    Add-SmokeFailure 'Expected package managers to be enabled when the Windhawk layer is selected.'
}
if (-not $agentProfile.modules.windhawk.enabled) {
    Add-SmokeFailure 'Expected Windhawk layer to flow into the agent profile.'
}

$settings = New-SmokeBuildProfileSettings
$settings.EditorCursor = $false
$settings.EditorVSCode = $false
$settings.EditorZed = $false
$settings.EditorAntigravity = $false
$settings.EditorNeovim = $false
$profile = New-WinMintBuildProfile -Settings $settings
if (@($profile.development.editors).Count -ne 0) {
    Add-SmokeFailure 'Expected explicit false editor flags to disable profile default editors.'
}

$settings = New-SmokeBuildProfileSettings
$settings.BrowserZen = $false
$settings.BrowserHelium = $false
$settings.BrowserFirefoxDeveloperEdition = $false
$settings.BrowserBrave = $false
$settings.BrowserEdge = $false
$profile = New-WinMintBuildProfile -Settings $settings
if (@($profile.development.browsers).Count -ne 0) {
    Add-SmokeFailure 'Expected explicit false browser flags to disable profile default browsers.'
}

$settings = New-SmokeBuildProfileSettings
$settings.InstallNilesoft = $true
$profile = New-WinMintBuildProfile -Settings $settings
if (@($profile.desktop.layers) -notcontains 'nilesoft') {
    Add-SmokeFailure 'Expected InstallNilesoft to flow into the build profile desktop layers.'
}

$settings = New-SmokeBuildProfileSettings
$settings.Wsl2Distros = @('Ubuntu', 'Fedora', 'archlinux', 'NixOS-WSL', 'Pengwin')
$profile = New-WinMintBuildProfile -Settings $settings
if (@($profile.development.wsl.distros) -notcontains 'Ubuntu' -or
    @($profile.development.wsl.distros) -notcontains 'FedoraLinux' -or
    @($profile.development.wsl.distros) -notcontains 'archlinux' -or
    @($profile.development.wsl.distros) -notcontains 'NixOS-WSL' -or
    @($profile.development.wsl.distros) -notcontains 'pengwin') {
    Add-SmokeFailure 'Expected WSL distro suggestions to normalize into canonical build-profile tokens.'
}
$config = New-WinMintBuildConfig -BuildProfile $profile
if ($config.Wsl2Distros -notcontains 'NixOS-WSL' -or $config.Wsl2Distros -notcontains 'FedoraLinux') {
    Add-SmokeFailure 'Expected canonical WSL selections to flow into the build config.'
}
$agentProfile = New-WinMintInstallPlanAgentProfile -BuildConfig $config
if (@($agentProfile.modules.wsl.distros) -notcontains 'NixOS' -or @($agentProfile.modules.wsl.distros) -notcontains 'FedoraLinux') {
    Add-SmokeFailure 'Expected NixOS-WSL to normalize to NixOS for first-logon installation.'
}

$profile = New-SmokeBuildProfile
$profile.development.wsl.distros = @('Fedora')
Assert-ProfileFailsWith -Profile $profile -Expected 'profile.development.wsl.distros[] must be one of: Ubuntu, FedoraLinux, archlinux, NixOS-WSL, pengwin.'

$settings = New-SmokeBuildProfileSettings
$profile = New-WinMintBuildProfile -Settings $settings
if (@($profile.development.editors).Count -ne 0) {
    Add-SmokeFailure 'Expected omitted editor settings in the Developer group to remain unselected.'
}

$profile = New-SmokeBuildProfile
$profile.drivers.source = 'Host'
$profile.drivers.exportHostDrivers = $false
Assert-ProfileFailsWith -Profile $profile -Expected 'profile.drivers.exportHostDrivers must be true when profile.drivers.source is Host or HostExport.'

$profile = New-SmokeBuildProfile
$profile.drivers.exportHostDrivers = $true
Assert-ProfileFailsWith -Profile $profile -Expected 'profile.drivers.exportHostDrivers requires a driver source or Host/HostExport.'

$profile = New-SmokeBuildProfile
$profile.drivers.source = 'SurfaceCatalog'
$profile.drivers.path = 'surface-laptop-7'
$profile.drivers.exportHostDrivers = $true
$surfaceHostConfig = New-WinMintBuildConfig -BuildProfile $profile
if (-not $surfaceHostConfig.ExportHostDrivers) {
    Add-SmokeFailure 'Expected exportHostDrivers=true with SurfaceCatalog to enable host driver mirror.'
}
if ($surfaceHostConfig.HostMirrorFilter -ne 'setup-critical') {
    Add-SmokeFailure 'Expected default hostMirrorFilter setup-critical when exportHostDrivers is enabled.'
}

$profile = New-SmokeBuildProfile
$profile.drivers.source = 'SurfaceCatalog'
$profile.drivers.path = 'surface-laptop-7'
$profile.drivers.exportHostDrivers = $true
$profile.drivers.hostMirrorFilter = 'full'
$fullMirrorConfig = New-WinMintBuildConfig -BuildProfile $profile
if ($fullMirrorConfig.HostMirrorFilter -ne 'full') {
    Add-SmokeFailure 'Expected explicit hostMirrorFilter full to flow into BuildConfig.'
}

$profile = New-SmokeBuildProfile
$profile.drivers.hostMirrorFilter = 'setup-critical'
Assert-ProfileFailsWith -Profile $profile -Expected 'profile.drivers.hostMirrorFilter requires profile.drivers.exportHostDrivers=true.'

$profile = New-SmokeBuildProfile
$profile.development | Add-Member -NotePropertyName dotfiles -NotePropertyValue ([pscustomobject]@{ repository = 'http://insecure.example/dotfiles.git' }) -Force
Assert-ProfileFailsWith -Profile $profile -Expected 'profile.development.dotfiles.repository must be an https:// git URL (v1).'

$profile = New-SmokeBuildProfile
$profile.development | Add-Member -NotePropertyName dotfiles -NotePropertyValue ([pscustomobject]@{
        repository = 'https://github.com/example/dotfiles.git'
        ref = 'main'
        installScript = 'install.ps1'
    }) -Force
$dotfilesConfig = New-WinMintBuildConfig -BuildProfile $profile
if (-not $dotfilesConfig.Dotfiles.Enabled) {
    Add-SmokeFailure 'Expected dotfiles block to enable Dotfiles on BuildConfig.'
}
$dotfilesPlan = New-WinMintInstallPlanAgentProfile -BuildConfig $dotfilesConfig
if (-not $dotfilesPlan.modules.dotfiles.enabled) {
    Add-SmokeFailure 'Expected dotfiles profile to enable modules.dotfiles in agent profile.'
}

$defaultAgentPlan = New-WinMintInstallPlanAgentProfile -BuildConfig (New-WinMintBuildConfig -BuildProfile (New-SmokeBuildProfile))
if ($defaultAgentPlan.modules.git.enabled) {
    Add-SmokeFailure 'Expected modules.git.enabled to remain false until a future development.git contract exists.'
}

$profile = New-SmokeBuildProfile
$profile.drivers.source = 'Host'
$profile.drivers.exportHostDrivers = $true
$config = New-WinMintBuildConfig -BuildProfile $profile
if (-not $config.ExportHostDrivers) { Add-SmokeFailure 'Expected host driver export to be enabled for drivers.source Host.' }
if ($config.HostMirrorFilter -ne 'full') {
    Add-SmokeFailure 'Expected Host/HostExport driver source to force hostMirrorFilter full.'
}

$profile = New-SmokeBuildProfile
$profile.desktop.cursorPack = 'OtherPack'
Assert-ProfileFailsWith -Profile $profile -Expected 'profile.desktop.cursorPack must be one of: Windows11Modern.'

$profile = New-WinMintBuildProfile -Settings (New-SmokeBuildProfileSettings)
$config = New-WinMintBuildConfig -BuildProfile $profile
$agentProfile = New-WinMintInstallPlanAgentProfile -BuildConfig $config
if ($config.Launcher -ne 'None') {
    Add-SmokeFailure 'Expected launcher modules to stay disabled by default for the Developer group.'
}
if ($agentProfile.modules.phoneLink.enabled -or $agentProfile.modules.liveInstallAudit.enabled) {
    Add-SmokeFailure 'Expected residual live-user modules to stay disabled by default for the Developer group.'
}

$profile = New-WinMintBuildProfile -Settings @{
    Profile = 'Minimal'
    ProfileGroups = @('Minimal')
    ISOPath = (Get-WinMintTestIsoFixturePath)
    Architecture = 'arm64'
    ComputerName = 'WinMint'
    AccountName = 'dev'
    DriverSource = 'None'
    DriverPath = ''
}
$config = New-WinMintBuildConfig -BuildProfile $profile
$agentProfile = New-WinMintInstallPlanAgentProfile -BuildConfig $config
if ($agentProfile.modules.phoneLink.enabled -or $agentProfile.modules.liveInstallAudit.enabled) {
    Add-SmokeFailure 'Expected Phone Link and live install audit to stay disabled for the Minimal group.'
}

$profile = New-WinMintBuildProfile -Settings @{
    Profile = 'Minimal'
    ProfileGroups = @('Minimal', 'DesktopUI')
    ISOPath = (Get-WinMintTestIsoFixturePath)
    Architecture = 'arm64'
    ComputerName = 'WinMint'
    AccountName = 'dev'
    DriverSource = 'None'
    DriverPath = ''
    DesktopUiDefault = $true
}
$config = New-WinMintBuildConfig -BuildProfile $profile
$agentProfile = New-WinMintInstallPlanAgentProfile -BuildConfig $config
if ($config.Launcher -ne 'None') {
    Add-SmokeFailure 'Expected launcher modules to stay disabled by default for the DesktopUI group.'
}

$profile = New-SmokeBuildProfile
$profile.privacy.telemetryTracing = 'default'
$profile.privacy.locationServices = 'disabled'
$config = New-WinMintBuildConfig -BuildProfile $profile
$setupProfile = New-WinMintInstallPlanSetupProfile -BuildConfig $config
if ($setupProfile.privacy.telemetryHardening) { Add-SmokeFailure 'Expected telemetry privacy opt-out to flow into setup profile.' }
if ($setupProfile.privacy.location) { Add-SmokeFailure 'Expected location privacy opt-out to flow into setup profile.' }

$settings = New-SmokeBuildProfileSettings
$settings.TweakHardwareBypass = $true
$profile = New-WinMintBuildProfile -Settings $settings
$config = New-WinMintBuildConfig -BuildProfile $profile
if ($config.RegistryTweaks -notcontains 'hardware-bypass') {
    Add-SmokeFailure 'Expected explicit hardware bypass selection to flow into registry tweaks.'
}

$profile = New-SmokeBuildProfile
$profile.source.isoPath = ''
$profile.source.architecture = ''
$config = New-WinMintBuildConfig -BuildProfile $profile
$pre = Test-WinMintBuildPrerequisite -Config $config -RunMode DryRun
if (-not $pre.Passed) {
    Add-SmokeFailure "Expected profile-only dry run prerequisite check to allow missing ISO and architecture. Failures: $($pre.Failures -join '; ')"
}
if (@($pre.Findings | Where-Object Code -eq 'source.iso.missing.profileOnlyDryRun').Count -ne 1) {
    Add-SmokeFailure 'Expected profile-only dry run preflight to emit source.iso.missing.profileOnlyDryRun.'
}
$pre = Test-WinMintBuildPrerequisite -Config $config
if ($pre.Passed) {
    Add-SmokeFailure 'Expected normal build prerequisite check to reject a missing ISO.'
}
if (@($pre.Findings | Where-Object Code -eq 'source.iso.missing').Count -ne 1) {
    Add-SmokeFailure 'Expected normal build preflight to emit source.iso.missing.'
}

$stickyProfile = New-SmokeBuildProfile
$stickyProfile.posture.accessibility.stickyKeys = 'disabled'
$stickyConfig = New-WinMintBuildConfig -BuildProfile $stickyProfile
$stickySetup = New-WinMintInstallPlanSetupProfile -BuildConfig $stickyConfig
if (-not [bool]$stickySetup.defaultUser.stickyKeysOff) {
    Add-SmokeFailure 'posture.accessibility.stickyKeys=disabled must flow to defaultUser.stickyKeysOff=true.'
}

$v3Profile = $stickyProfile | ConvertTo-Json -Depth 16 | ConvertFrom-Json
$v3Profile.schemaVersion = 3
$v3Result = Test-WinMintBuildProfile -BuildProfile $v3Profile
if ($v3Result.Passed) {
    Add-SmokeFailure 'schemaVersion 3 profiles must be rejected.'
}

if ($failures.Count -gt 0) {
    throw "Profile invariant smoke failed with $($failures.Count) error(s)."
}

Write-Host 'Profile invariant smoke passed.'
exit 0
