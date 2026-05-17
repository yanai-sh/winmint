#Requires -Version 7.3
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:WinWSRepositoryRoot = $root

. (Join-Path $root 'src\WinWS\Core.ps1')
. (Join-Path $root 'src\WinWS\Private\Config\Profile.ps1')
. (Join-Path $root 'src\WinWS\Private\Catalog.ps1')
. (Join-Path $root 'src\WinWS\Engine.ps1')
. (Join-Path $root 'src\WinWS\Reports.ps1')
. (Join-Path $root 'src\WinWS\Private\Runtime.ps1')
. (Join-Path $root 'src\WinWS\Private\Image\Drivers.ps1')
. (Join-Path $root 'src\WinWS\Private\Image\Packages.ps1')
. (Join-Path $root 'src\WinWS\Private\Media.ps1')
. (Join-Path $root 'src\WinWS\Private\Image\Tweaks.ps1')
. (Join-Path $root 'src\WinWS\Private\Image\Unattend.ps1')
. (Join-Path $root 'src\WinWS\Private\SourcePrep.ps1')
. (Join-Path $root 'src\WinWS\Private\Pipeline.Console.ps1')
. (Join-Path $root 'src\WinWS\Private\Headless.ps1')

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
if (-not (Get-Command Test-WinWSAdministrator -ErrorAction SilentlyContinue)) {
    function Test-WinWSAdministrator { return $true }
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
Assert-BuildResultContractAcceptsPipelineOutput
Assert-StartBuildReturnsSingleResultContract
Assert-ManifestPayloadsAreDeduplicated
Assert-TweakAuditArtifactsAreWritten
Assert-CachedDownloadResolver
Assert-OfflinePayloadCacheStatus
Assert-StaticUiFlowInvariants
Assert-HardwareBypassIsExplicit
Assert-ElevationRequiredForAllRuns
Assert-HardwareBypassUnattendGeneration
Assert-MicrosoftOobeUnattendGeneration
Assert-LocalAccountUnattendGeneration
Assert-SetupCompleteDoesNotDecryptBitLocker
Assert-ServiceabilityGuardrails
Assert-ProtectedPlatformPackagesArePreserved
Assert-MinimalAppxRemovalCatalogCoversPolicy
Assert-PhoneLinkAgentDefaults
Assert-ConsumerUtilityPackagesNeverInRemovalList
Assert-LiveInstallAuditIsNonDestructive
Assert-LiveInstallAuditCoversPlatformGuardrails
Assert-LiveInstallAuditUsesSetupProfilePrefixes
Assert-LiveInstallAuditIsStaged
Assert-AgentRunsLiveInstallAudit
Assert-MaintainFallbackDoesNotRemovePlatformApps
Assert-ExternalReferenceAuditDocumentsSparkle
Assert-WslFirstDefaultsAndGuards
Assert-LogNoiseInvariants
Assert-WinPEDriverInjectionDefaultsToSetupOnly
Assert-EdgePolicyPreservesCopilotSidebar
Assert-OneDriveRemovalPolicyIsComplete
Assert-RegistryTweakMetadataAndRollback
Assert-SetupRegistryStampsAreIdempotent
Assert-HeadlessConsoleProfileContract
Assert-HeadlessCliContracts
Assert-HeadlessSourceAndDriverInputContracts

$profile = New-SmokeBuildProfile
$result = Test-WinWSBuildProfile -BuildProfile $profile
if (-not $result.Passed) {
    Add-SmokeFailure "Expected generated profile to pass validation, got: $($result.Failures -join '; ')"
}
$config = New-WinWSBuildConfig -BuildProfile $profile
if ($config.SetupOption -ne 'Minimal') { Add-SmokeFailure 'Expected Minimal to be the default setup option.' }
if ($config.AppxPackages -notcontains 'Microsoft.Copilot' -or $config.AppxPackages -notcontains 'MicrosoftWindows.Client.WebExperience') {
    Add-SmokeFailure 'Expected Minimal setup option to remove Copilot and WebExperience packages.'
}
$setupProfile = New-WinWSSetupProfile -BuildConfig $config
if ($setupProfile.setupComplete.preserveMicrosoftCopilot) {
    Add-SmokeFailure 'Expected Minimal setup option not to preserve Microsoft Copilot surfaces.'
}
if (-not $setupProfile.setupComplete.removeRecall) {
    Add-SmokeFailure 'Expected Minimal setup option to remove Recall.'
}

$settings = New-SmokeBuildProfileSettings
$settings.SetupOption = 'CopilotPlus'
$profile = New-WinWSBuildProfile -Settings $settings
$config = New-WinWSBuildConfig -BuildProfile $profile
if ($config.SetupOption -ne 'CopilotPlus') { Add-SmokeFailure 'Expected CopilotPlus setup option to flow into build config.' }
if ($config.AppxPackages -contains 'Microsoft.Copilot' -or $config.AppxPackages -contains 'MicrosoftWindows.Client.WebExperience') {
    Add-SmokeFailure 'Expected CopilotPlus setup option to preserve Copilot and WebExperience packages.'
}
if ($config.RegistryTweaks -notcontains 'edge-policy-copilotplus') { Add-SmokeFailure 'Expected CopilotPlus builds to use the CopilotPlus Edge policy.' }
if ($config.RegistryTweaks -contains 'edge-policy-minimal') { Add-SmokeFailure 'CopilotPlus builds must not use the strict Minimal Edge policy.' }
$setupProfile = New-WinWSSetupProfile -BuildConfig $config
if (-not $setupProfile.setupComplete.preserveMicrosoftCopilot) {
    Add-SmokeFailure 'Expected CopilotPlus setup option to preserve Microsoft Copilot surfaces.'
}
if (-not $setupProfile.setupComplete.removeRecall) {
    Add-SmokeFailure 'Expected CopilotPlus setup option to still remove Recall.'
}

$profile = New-WinWSBuildProfile -Settings (New-SmokeBuildProfileSettings)
$config = New-WinWSBuildConfig -BuildProfile $profile
if ($config.CursorPackKind -ne 'BreezeXLight') { Add-SmokeFailure 'Expected BreezeXLight cursor pack in build config.' }
if ($config.Tweaks.UpdatePolicy -ne 'All') { Add-SmokeFailure 'Expected All update policy in build config.' }
if ($config.ExportHostDrivers) { Add-SmokeFailure 'Expected host driver export to be disabled for drivers.source None.' }
if ($config.RegistryTweaks -contains 'hardware-bypass') { Add-SmokeFailure 'hardware-bypass must not be in the default registry tweaks for a standard build.' }
if ($config.RegistryTweaks -notcontains 'edge-policy-minimal') { Add-SmokeFailure 'Expected Minimal builds to use the strict Edge policy.' }
if ($config.RegistryTweaks -contains 'edge-policy-copilotplus') { Add-SmokeFailure 'Minimal builds must not use the CopilotPlus Edge policy.' }
$setupProfile = New-WinWSSetupProfile -BuildConfig $config
if (-not $setupProfile.privacy.telemetry) { Add-SmokeFailure 'Expected default setup profile telemetry privacy toggle to be enabled.' }
if ($setupProfile.privacy.location) { Add-SmokeFailure 'Location privacy must default to off so laptop location services remain usable.' }
$agentProfile = New-WinWSAgentProfile -BuildConfig $config
if (@($config.Editors).Count -ne 0) {
    Add-SmokeFailure 'Expected Developer group to leave editor options unselected by default.'
}
if ($config.Features -contains 'Microsoft-Windows-Subsystem-Linux' -or
    $config.Features -contains 'VirtualMachinePlatform') {
    Add-SmokeFailure 'Expected Developer group to leave WSL features disabled until a distro is selected.'
}
if ($agentProfile.modules.wsl.enabled -or @($agentProfile.modules.wsl.distros).Count -ne 0) {
    Add-SmokeFailure 'Expected Developer group to leave FirstLogon WSL module disabled until a distro is selected.'
}

$profile = New-WinWSBuildProfile -Settings @{
    Profile = 'Minimal'
    ProfileGroups = @('Minimal')
    ISOPath = (Get-WinWSTestIsoFixturePath)
    Architecture = 'arm64'
    ComputerName = 'WinWS'
    AccountName = 'dev'
    DriverSource = 'None'
    DriverPath = ''
}
$config = New-WinWSBuildConfig -BuildProfile $profile
$agentProfile = New-WinWSAgentProfile -BuildConfig $config
if ($agentProfile.modules.packageManagers.enabled) {
    Add-SmokeFailure 'Expected package managers to be disabled for Minimal when no module needs winget.'
}

$profile = New-SmokeBuildProfile
$profile.development.editors = @()
$profile.desktop.layers = @('standard', 'yasb')
$config = New-WinWSBuildConfig -BuildProfile $profile
$agentProfile = New-WinWSAgentProfile -BuildConfig $config
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
$config = New-WinWSBuildConfig -BuildProfile $profile
$agentProfile = New-WinWSAgentProfile -BuildConfig $config
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
$config = New-WinWSBuildConfig -BuildProfile $profile
$agentProfile = New-WinWSAgentProfile -BuildConfig $config
if (-not $agentProfile.modules.packageManagers.enabled) {
    Add-SmokeFailure 'Expected package managers to be enabled when the Windhawk layer is selected.'
}
if (-not $agentProfile.modules.windhawk.enabled) {
    Add-SmokeFailure 'Expected Windhawk layer to flow into the agent profile.'
}

$settings = New-SmokeBuildProfileSettings
$settings.EditorCursor = $false
$settings.EditorVSCodium = $false
$settings.EditorVSCode = $false
$settings.EditorZed = $false
$settings.EditorNeovim = $false
$profile = New-WinWSBuildProfile -Settings $settings
if (@($profile.development.editors).Count -ne 0) {
    Add-SmokeFailure 'Expected explicit false editor flags to disable profile default editors.'
}

$settings = New-SmokeBuildProfileSettings
$profile = New-WinWSBuildProfile -Settings $settings
if (@($profile.development.editors).Count -ne 0) {
    Add-SmokeFailure 'Expected omitted editor settings in the Developer group to remain unselected.'
}

$profile = New-SmokeBuildProfile
$profile.drivers.source = 'Host'
$profile.drivers.exportHostDrivers = $false
Assert-ProfileFailsWith -Profile $profile -Expected 'profile.drivers.exportHostDrivers must be true when profile.drivers.source is Host.'

$profile = New-SmokeBuildProfile
$profile.drivers.exportHostDrivers = $true
Assert-ProfileFailsWith -Profile $profile -Expected 'profile.drivers.exportHostDrivers must be false unless profile.drivers.source is Host.'

$profile = New-SmokeBuildProfile
$profile.drivers.source = 'Host'
$profile.drivers.exportHostDrivers = $true
$config = New-WinWSBuildConfig -BuildProfile $profile
if (-not $config.ExportHostDrivers) { Add-SmokeFailure 'Expected host driver export to be enabled for drivers.source Host.' }

$profile = New-SmokeBuildProfile
$profile.desktop.cursorPack = 'OtherPack'
Assert-ProfileFailsWith -Profile $profile -Expected 'profile.desktop.cursorPack must be one of: BreezeXLight.'

$profile = New-WinWSBuildProfile -Settings (New-SmokeBuildProfileSettings)
$config = New-WinWSBuildConfig -BuildProfile $profile
$agentProfile = New-WinWSAgentProfile -BuildConfig $config
if (-not $agentProfile.modules.flowEverything.enabled) {
    Add-SmokeFailure 'Expected flowEverything to be enabled for the Developer group.'
}

$profile = New-WinWSBuildProfile -Settings @{
    Profile = 'Minimal'
    ProfileGroups = @('Minimal')
    ISOPath = (Get-WinWSTestIsoFixturePath)
    Architecture = 'arm64'
    ComputerName = 'WinWS'
    AccountName = 'dev'
    DriverSource = 'None'
    DriverPath = ''
}
$config = New-WinWSBuildConfig -BuildProfile $profile
$agentProfile = New-WinWSAgentProfile -BuildConfig $config
if ($agentProfile.modules.flowEverything.enabled) {
    Add-SmokeFailure 'Expected flowEverything to stay disabled for the Minimal group.'
}

$profile = New-WinWSBuildProfile -Settings @{
    Profile = 'Minimal'
    ProfileGroups = @('Minimal', 'DesktopUI')
    ISOPath = (Get-WinWSTestIsoFixturePath)
    Architecture = 'arm64'
    ComputerName = 'WinWS'
    AccountName = 'dev'
    DriverSource = 'None'
    DriverPath = ''
    DesktopUiDefault = $true
}
$config = New-WinWSBuildConfig -BuildProfile $profile
$agentProfile = New-WinWSAgentProfile -BuildConfig $config
if (-not $agentProfile.modules.flowEverything.enabled) {
    Add-SmokeFailure 'Expected flowEverything to be enabled for the DesktopUI group.'
}

$profile = New-SmokeBuildProfile
$profile.privacy.telemetry = $false
$profile.privacy.location = $false
$config = New-WinWSBuildConfig -BuildProfile $profile
$setupProfile = New-WinWSSetupProfile -BuildConfig $config
if ($setupProfile.privacy.telemetry) { Add-SmokeFailure 'Expected telemetry privacy opt-out to flow into setup profile.' }
if ($setupProfile.privacy.location) { Add-SmokeFailure 'Expected location privacy opt-out to flow into setup profile.' }

$settings = New-SmokeBuildProfileSettings
$settings.TweakHardwareBypass = $true
$profile = New-WinWSBuildProfile -Settings $settings
$config = New-WinWSBuildConfig -BuildProfile $profile
if ($config.RegistryTweaks -notcontains 'hardware-bypass') {
    Add-SmokeFailure 'Expected explicit hardware bypass selection to flow into registry tweaks.'
}

$profile = New-SmokeBuildProfile
$profile.source.isoPath = ''
$config = New-WinWSBuildConfig -BuildProfile $profile
$pre = Test-WinWSBuildPrerequisite -Config $config -AllowMissingSourceIso
if (-not $pre.Passed) {
    Add-SmokeFailure "Expected profile-only dry run prerequisite check to allow a missing ISO. Failures: $($pre.Failures -join '; ')"
}
$pre = Test-WinWSBuildPrerequisite -Config $config
if ($pre.Passed) {
    Add-SmokeFailure 'Expected normal build prerequisite check to reject a missing ISO.'
}

if ($failures.Count -gt 0) {
    throw "Profile invariant smoke failed with $($failures.Count) error(s)."
}

Write-Host 'Profile invariant smoke passed.'
