#Requires -Version 7.3
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:root = $root
. (Join-Path $root 'tests\contract\TestFixtures.ps1')
. (Join-Path $root 'src\runtime\image\WinMint.ps1')
Initialize-WinMintEngine -RepositoryRoot $root -DryRun

$cli = Join-Path $root 'WinMint-CLI.ps1'
$matrixRoot = Join-Path $root 'output\cli-matrix'
$null = New-Item -ItemType Directory -Path $matrixRoot -Force
$sourceIso = Get-WinMintTestOfficialIsoFixturePath

$failures = [System.Collections.Generic.List[string]]::new()

function Add-CliMatrixFailure {
    param([string]$Message)
    $script:failures.Add($Message) | Out-Null
}

function Invoke-CliProfileCase {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$Arguments = @(),
        [scriptblock]$Assert
    )

    $profilePath = Join-Path $matrixRoot "$Name.json"
    Remove-Item -LiteralPath $profilePath -Force -ErrorAction SilentlyContinue
    $cliArgs = @(
        '-NoProfile', '-File', $cli,
        'new', $profilePath,
        '-SourceIso', $sourceIso,
        '-Architecture', 'arm64',
        '-Json'
    ) + @($Arguments)

    $output = & pwsh.exe @cliArgs
    if ($LASTEXITCODE -ne 0) {
        Add-CliMatrixFailure "CLI case '$Name' failed with exit code $($LASTEXITCODE): $output"
        return
    }
    if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
        Add-CliMatrixFailure "CLI case '$Name' did not create profile: $profilePath"
        return
    }

    try {
        $result = $output | ConvertFrom-Json
        if ([string]$result.result -ne 'profile-created') {
            Add-CliMatrixFailure "CLI case '$Name' returned unexpected result: $($result.result)"
        }
    }
    catch {
        Add-CliMatrixFailure "CLI case '$Name' did not emit JSON result: $($_.Exception.Message)"
    }

    $profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
    Assert-WinMintBuildProfile -BuildProfile $profile
    $config = New-WinMintBuildConfig -BuildProfile $profile
    $agentProfile = New-WinMintAgentProfile -BuildConfig $config
    if ($Assert) { & $Assert $profile $config $agentProfile }
}

function Invoke-CliFailureCase {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$ExpectedPattern
    )

    $oldNativePreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $output = & pwsh.exe -NoProfile -File $cli @Arguments -Json
        $exitCode = $LASTEXITCODE
    }
    finally {
        $PSNativeCommandUseErrorActionPreference = $oldNativePreference
    }
    if ($exitCode -ne 1) {
        Add-CliMatrixFailure "CLI failure case '$Name' expected exit code 1, got $($exitCode): $output"
        return
    }
    try {
        $result = $output | ConvertFrom-Json
        if ([string]$result.result -ne 'failed') {
            Add-CliMatrixFailure "CLI failure case '$Name' expected failed result, got: $($result.result)"
        }
        if ((@($result.failures) -join "`n") -notmatch $ExpectedPattern) {
            Add-CliMatrixFailure "CLI failure case '$Name' missing expected failure pattern '$ExpectedPattern'. Got: $(@($result.failures) -join '; ')"
        }
    }
    catch {
        Add-CliMatrixFailure "CLI failure case '$Name' did not emit JSON result: $($_.Exception.Message). Output: $output"
    }
}

Invoke-CliProfileCase -Name 'minimal-default' -Assert {
    param($Profile, $Config, $AgentProfile)
    if ([bool]$Profile.keep.edge -or [bool]$Profile.keep.gaming -or [bool]$Profile.keep.copilot) { Add-CliMatrixFailure 'minimal-default should keep nothing (full subtractive default).' }
    if ([int]$Profile.schemaVersion -ne 3) { Add-CliMatrixFailure 'minimal-default should emit schemaVersion 3.' }
    if (-not [bool]$Profile.tweaks.dmaInterop -or -not [bool]$Config.DmaInterop.Enabled) { Add-CliMatrixFailure 'minimal-default should enable DMA interop.' }
    if ($Config.SetupUserLocale -ne 'en-IE' -or $Config.SetupHomeLocationGeoId -ne 68) { Add-CliMatrixFailure 'minimal-default should use Ireland/en-IE/68 for setup.' }
    if ($Profile.regional.userLocale -ne 'en-US' -or [int]$Profile.regional.homeLocationGeoId -ne 244) { Add-CliMatrixFailure 'minimal-default should restore visible en-US/244 by default.' }
    if (-not [bool]$Profile.privacy.location -or -not [bool]$Config.Privacy.Location) { Add-CliMatrixFailure 'minimal-default should enable location services by default.' }
if ($Config.Launcher -ne 'None' -or -not $AgentProfile.modules.packageManagers.enabled -or
        $AgentProfile.modules.flowEverything.enabled -or $AgentProfile.modules.raycast.enabled -or
        $AgentProfile.modules.phoneLink.enabled -or $AgentProfile.modules.liveInstallAudit.enabled) {
        Add-CliMatrixFailure 'minimal-default should enable only baseline package managers plus WSL, not optional residual first-logon modules.'
    }
    if ($Config.Features -notcontains 'Microsoft-Windows-Subsystem-Linux' -or
        $Config.Features -notcontains 'VirtualMachinePlatform') {
        Add-CliMatrixFailure 'minimal-default should carry WSL2 and Virtual Machine Platform as baseline features.'
    }
    if (-not [bool]$AgentProfile.modules.wsl.enabled -or @($AgentProfile.modules.wsl.distros).Count -ne 0) {
        Add-CliMatrixFailure 'minimal-default should keep WSL enabled with no distro selected.'
    }
}

Invoke-CliProfileCase -Name 'minimal-no-dma-no-location' -Arguments @('-Dma', 'Off', '-Location', 'Off') -Assert {
    param($Profile, $Config, $AgentProfile)
    [void]$AgentProfile
    if ([bool]$Profile.tweaks.dmaInterop -or [bool]$Config.DmaInterop.Enabled) { Add-CliMatrixFailure 'minimal-no-dma-no-location should disable DMA interop.' }
    if ($Config.SetupUserLocale -ne 'en-US' -or $Config.SetupHomeLocationGeoId -ne 244) { Add-CliMatrixFailure 'minimal-no-dma-no-location should use visible en-US setup region.' }
    if ([bool]$Profile.privacy.location -or [bool]$Config.Privacy.Location) { Add-CliMatrixFailure 'minimal-no-dma-no-location should disable location services.' }
    if (@($Config.RegistryTweaks) -notcontains 'location-disabled-policy') { Add-CliMatrixFailure 'minimal-no-dma-no-location should apply location-disabled-policy.' }
}

# Subtractive model: developer tooling (OpenSSH client, Developer Mode,
# RemoteSigned) is baseline on every build, with no editors/WSL distros
# preselected.
Invoke-CliProfileCase -Name 'baseline-developer-tooling' -Assert {
    param($Profile, $Config, $AgentProfile)
    if ([bool]$Profile.keep.edge -or [bool]$Profile.keep.gaming -or [bool]$Profile.keep.copilot) { Add-CliMatrixFailure 'baseline-developer-tooling should keep nothing by default.' }
    if ($Config.Features -notcontains 'OpenSSH.Client' -or
        $Config.RegistryTweaks -notcontains 'developer-mode' -or
        $Config.RegistryTweaks -notcontains 'powershell-remotesigned') {
        Add-CliMatrixFailure 'developer-only should carry baseline developer tooling (OpenSSH client, Developer Mode, RemoteSigned).'
    }
    if (@($Profile.development.editors).Count -ne 0 -or @($Profile.development.wsl.distros).Count -ne 0) {
        Add-CliMatrixFailure 'developer-only should not preselect editors or WSL distros.'
    }
    if ($Config.Features -notcontains 'Microsoft-Windows-Subsystem-Linux' -or
        $Config.Features -notcontains 'VirtualMachinePlatform') {
        Add-CliMatrixFailure 'developer-only should carry WSL2 and Virtual Machine Platform as baseline features.'
    }
    if (-not $AgentProfile.modules.packageManagers.enabled -or -not $AgentProfile.modules.wsl.enabled -or
        @($AgentProfile.modules.wsl.distros).Count -ne 0 -or
        $AgentProfile.modules.phoneLink.enabled -or $AgentProfile.modules.liveInstallAudit.enabled) {
        Add-CliMatrixFailure 'developer-only should keep package managers/WSL enabled, with no distro and no optional residual first-logon modules without explicit choices.'
    }
}

Invoke-CliProfileCase -Name 'toolkit-browser-editor-selection' -Arguments @(
    '-Editor', 'cursor,neovim',
    '-Browser', 'zen-browser,edge',
    '-Install', 'nilesoft',
    '-Wsl2Distros', 'Ubuntu,Fedora,archlinux,NixOS-WSL,pengwin'
) -Assert {
    param($Profile, $Config, $AgentProfile)
    if ($Profile.development.editors -notcontains 'cursor' -or $Profile.development.editors -notcontains 'neovim') {
        Add-CliMatrixFailure 'toolkit-browser-editor-selection should preserve editor selections in the build profile.'
    }
    if ($Profile.development.browsers -notcontains 'zen-browser' -or $Profile.development.browsers -notcontains 'edge') {
        Add-CliMatrixFailure 'toolkit-browser-editor-selection should preserve browser selections in the build profile.'
    }
    if ($Profile.development.wsl.distros -notcontains 'Ubuntu' -or $Profile.development.wsl.distros -notcontains 'FedoraLinux' -or $Profile.development.wsl.distros -notcontains 'archlinux' -or $Profile.development.wsl.distros -notcontains 'NixOS-WSL' -or $Profile.development.wsl.distros -notcontains 'pengwin') {
        Add-CliMatrixFailure 'toolkit-browser-editor-selection should preserve WSL distro selections in the build profile.'
    }
    if ($Config.Keep.Edge -ne $true -or $Config.Browsers -notcontains 'zen-browser' -or $Config.Browsers -notcontains 'edge' -or -not $Config.InstallNilesoft) {
        Add-CliMatrixFailure 'toolkit-browser-editor-selection should carry browser/shell intent into the build config and keep Edge when selected.'
    }
    if ($Config.Wsl2Distros -notcontains 'Ubuntu' -or $Config.Wsl2Distros -notcontains 'FedoraLinux' -or $Config.Wsl2Distros -notcontains 'archlinux' -or $Config.Wsl2Distros -notcontains 'NixOS-WSL' -or $Config.Wsl2Distros -notcontains 'pengwin') {
        Add-CliMatrixFailure 'toolkit-browser-editor-selection should preserve canonical WSL distros in the build config.'
    }
    if ($AgentProfile.modules.packageManagers.enabled -ne $true -or $AgentProfile.browsers -notcontains 'zen-browser' -or @($AgentProfile.modules.wsl.distros) -notcontains 'NixOS') {
        Add-CliMatrixFailure 'toolkit-browser-editor-selection should enable package managers, browser bootstrap, and WSL normalization.'
    }
}

# Subtractive model: the desktop shell layers are selected explicitly through the
# single -Install flag (window-manager tooling), which records them in the profile.
Invoke-CliProfileCase -Name 'desktop-ui-only' -Arguments @('-Install', 'windhawk,yasb,komorebi') -Assert {
    param($Profile, $Config, $AgentProfile)
    if (@($Profile.desktop.layers) -notcontains 'windhawk' -or @($Profile.desktop.layers) -notcontains 'yasb' -or @($Profile.desktop.layers) -notcontains 'komorebi') { Add-CliMatrixFailure 'desktop-ui-only should record the selected shell layers in the profile.' }
    if (-not $Config.InstallWindhawk -or -not $Config.InstallYasb -or -not $Config.InstallKomorebi) {
        Add-CliMatrixFailure 'desktop-ui-only should preserve the selected Windhawk/YASB/Komorebi shell layers.'
    }
    if ($Config.Launcher -ne 'None' -or $AgentProfile.modules.flowEverything.enabled -or $AgentProfile.modules.raycast.enabled) {
        Add-CliMatrixFailure 'desktop-ui-only should not imply a launcher.'
    }
}

Invoke-CliProfileCase -Name 'flow-launcher' -Arguments @('-Launcher', 'FlowEverything') -Assert {
    param($Profile, $Config, $AgentProfile)
    if ($Config.Launcher -ne 'FlowEverything' -or -not $AgentProfile.modules.flowEverything.enabled -or
        $AgentProfile.modules.raycast.enabled -or -not $AgentProfile.modules.packageManagers.enabled) {
        Add-CliMatrixFailure 'developer-flow-launcher should enable only Flow/Everything launcher path.'
    }
}

Invoke-CliProfileCase -Name 'raycast-launcher' -Arguments @('-Launcher', 'Raycast') -Assert {
    param($Profile, $Config, $AgentProfile)
    if ($Config.Launcher -ne 'Raycast' -or -not $AgentProfile.modules.raycast.enabled -or
        $AgentProfile.modules.flowEverything.enabled -or -not $AgentProfile.modules.packageManagers.enabled) {
        Add-CliMatrixFailure 'raycast-launcher should enable only Raycast launcher path.'
    }
}

$profileOverrideBase = Join-Path $matrixRoot 'profile-override-base.json'
& pwsh.exe -NoProfile -File $cli new $profileOverrideBase -SourceIso $sourceIso -Architecture arm64 -Json | Out-Null
if ($LASTEXITCODE -ne 0) {
    Add-CliMatrixFailure 'profile-backed source override base profile creation failed.'
}
else {
    $overrideIso = $sourceIso
    try {
        $imported = Import-WinMintHeadlessBuildProfile -ProfilePath $profileOverrideBase -SourceIsoOverride $overrideIso
        if ([string]$imported.source.isoPath -ne $overrideIso) {
            Add-CliMatrixFailure 'profile-backed source override should replace source.isoPath before validation.'
        }
    }
    catch {
        Add-CliMatrixFailure "profile-backed source override import failed: $($_.Exception.Message)"
    }
}

if ($failures.Count -gt 0) {
    throw "CLI matrix failed:`n$($failures -join "`n")"
}

Write-Host 'CLI matrix smoke passed.'
