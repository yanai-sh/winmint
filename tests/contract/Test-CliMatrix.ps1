#Requires -Version 7.3
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:root = $root
. (Join-Path $root 'tests\contract\TestFixtures.ps1')
. (Join-Path $root 'src\engine\WinMint.ps1')
Initialize-WinMintEngine -RepositoryRoot $root -DryRun

$cli = Join-Path $root 'WinMint-CLI.ps1'
$matrixRoot = Join-Path $root 'output\cli-matrix'
$null = New-Item -ItemType Directory -Path $matrixRoot -Force
$sourceIso = Get-WinMintTestOfficialIsoFixturePath
$uupZip = Get-WinMintTestUupDumpZipFixturePath

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
        '-NewProfile', $profilePath,
        '-SourceIso', $sourceIso,
        '-Architecture', 'arm64',
        '-DryRun',
        '-Json'
    ) + @($Arguments)

    $output = & pwsh.exe @cliArgs
    if ($LASTEXITCODE -ne 0) {
        Add-CliMatrixFailure "CLI case '$Name' failed with exit code $LASTEXITCODE`: $output"
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
        Add-CliMatrixFailure "CLI failure case '$Name' expected exit code 1, got $exitCode`: $output"
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
    if (@($Profile.profileGroups) -ne 'Minimal') { Add-CliMatrixFailure 'minimal-default should only select Minimal group.' }
    if ([int]$Profile.schemaVersion -ne 2) { Add-CliMatrixFailure 'minimal-default should emit schemaVersion 2.' }
    if (-not [bool]$Profile.tweaks.dmaInterop -or -not [bool]$Config.DmaInterop.Enabled) { Add-CliMatrixFailure 'minimal-default should enable DMA interop.' }
    if ($Config.SetupUserLocale -ne 'en-IE' -or $Config.SetupHomeLocationGeoId -ne 68) { Add-CliMatrixFailure 'minimal-default should use Ireland/en-IE/68 for setup.' }
    if ($Profile.regional.userLocale -ne 'en-US' -or [int]$Profile.regional.homeLocationGeoId -ne 244) { Add-CliMatrixFailure 'minimal-default should restore visible en-US/244 by default.' }
    if (-not [bool]$Profile.privacy.location -or -not [bool]$Config.Privacy.Location) { Add-CliMatrixFailure 'minimal-default should enable location services by default.' }
    if ($Config.Launcher -ne 'None' -or $AgentProfile.modules.packageManagers.enabled -or
        $AgentProfile.modules.flowEverything.enabled -or $AgentProfile.modules.raycast.enabled -or
        $AgentProfile.modules.phoneLink.enabled -or $AgentProfile.modules.liveInstallAudit.enabled) {
        Add-CliMatrixFailure 'minimal-default should not enable residual first-logon modules.'
    }
}

Invoke-CliProfileCase -Name 'minimal-no-dma-no-location' -Arguments @('-NoDmaInterop', '-NoLocationServices') -Assert {
    param($Profile, $Config, $AgentProfile)
    [void]$AgentProfile
    if ([bool]$Profile.tweaks.dmaInterop -or [bool]$Config.DmaInterop.Enabled) { Add-CliMatrixFailure 'minimal-no-dma-no-location should disable DMA interop.' }
    if ($Config.SetupUserLocale -ne 'en-US' -or $Config.SetupHomeLocationGeoId -ne 244) { Add-CliMatrixFailure 'minimal-no-dma-no-location should use visible en-US setup region.' }
    if ([bool]$Profile.privacy.location -or [bool]$Config.Privacy.Location) { Add-CliMatrixFailure 'minimal-no-dma-no-location should disable location services.' }
    if (@($Config.RegistryTweaks) -notcontains 'location-disabled-policy') { Add-CliMatrixFailure 'minimal-no-dma-no-location should apply location-disabled-policy.' }
}

Invoke-CliProfileCase -Name 'developer-only' -Arguments @('-Developer') -Assert {
    param($Profile, $Config, $AgentProfile)
    if (@($Profile.profileGroups) -notcontains 'Developer') { Add-CliMatrixFailure 'developer-only should select Developer group.' }
    if (@($Profile.development.editors).Count -ne 0 -or @($Profile.development.wsl.distros).Count -ne 0) {
        Add-CliMatrixFailure 'developer-only should not preselect editors or WSL distros.'
    }
    if ($AgentProfile.modules.packageManagers.enabled -or $AgentProfile.modules.wsl.enabled -or
        $AgentProfile.modules.phoneLink.enabled -or $AgentProfile.modules.liveInstallAudit.enabled) {
        Add-CliMatrixFailure 'developer-only should not enable residual first-logon modules without explicit choices.'
    }
}

Invoke-CliProfileCase -Name 'desktop-ui-only' -Arguments @('-DesktopUI') -Assert {
    param($Profile, $Config, $AgentProfile)
    if (@($Profile.profileGroups) -notcontains 'DesktopUI') { Add-CliMatrixFailure 'desktop-ui-only should select DesktopUI group.' }
    if ($Config.Launcher -ne 'None' -or $AgentProfile.modules.flowEverything.enabled -or $AgentProfile.modules.raycast.enabled) {
        Add-CliMatrixFailure 'desktop-ui-only should not imply a launcher.'
    }
}

Invoke-CliProfileCase -Name 'developer-flow-launcher' -Arguments @('-Developer', '-Launcher', 'FlowEverything') -Assert {
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
& pwsh.exe -NoProfile -File $cli -NewProfile $profileOverrideBase -SourceIso $sourceIso -Architecture arm64 -DryRun -Json | Out-Null
if ($LASTEXITCODE -ne 0) {
    Add-CliMatrixFailure 'profile-backed source override base profile creation failed.'
}
else {
    $overrideIso = Get-WinMintTestUupDumpIsoFixturePath
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

$uupPrep = Invoke-WinMintHeadlessSourcePrep -Path $uupZip -ValidateOnly
if ($uupPrep.SourceKind -ne 'UupDumpZip' -or $uupPrep.RanConversion -or [string]::IsNullOrWhiteSpace([string]$uupPrep.WorkDir)) {
    Add-CliMatrixFailure 'UUP source validate-only should fingerprint the UUP zip without conversion.'
}

Invoke-CliFailureCase `
    -Name 'profile-template-rejects-uup-source' `
    -Arguments @('-NewProfile', (Join-Path $matrixRoot 'bad-uup-template.json'), '-UupDumpSource', $uupZip, '-Architecture', 'arm64', '-DryRun') `
    -ExpectedPattern 'resolved source ISO only'

Invoke-CliFailureCase `
    -Name 'source-iso-and-uup-source-conflict' `
    -Arguments @('-SourceIso', $sourceIso, '-UupDumpSource', $uupZip, '-Architecture', 'arm64', '-DryRun') `
    -ExpectedPattern 'Use either -SourceIso or -UupDumpSource'

$folderSource = Join-Path $matrixRoot 'uup-folder'
$null = New-Item -ItemType Directory -Path $folderSource -Force
try {
    $null = Invoke-WinMintHeadlessSourcePrep -Path $folderSource -ValidateOnly
    Add-CliMatrixFailure 'UUP folder source should be rejected before source prep.'
}
catch {
    if ($_.Exception.Message -notmatch 'UUP Dump folders are not accepted') {
        Add-CliMatrixFailure "UUP folder rejection should explain -SourceIso guidance, got: $($_.Exception.Message)"
    }
}

if ($failures.Count -gt 0) {
    throw "CLI matrix failed:`n$($failures -join "`n")"
}

Write-Host 'CLI matrix smoke passed.'
