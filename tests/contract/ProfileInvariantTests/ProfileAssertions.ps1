#Requires -Version 7.6

function New-SmokeBuildProfile {
    New-WinMintBuildProfile -Settings @{
        Profile = 'WinMint'
        ISOPath = (Get-WinMintTestIsoFixturePath)
        Architecture = 'arm64'
        ComputerName = 'WinMint'
        AccountName = 'dev'
        Editors = @('cursor')
        DriverSource = 'None'
        DriverPath = ''
    }
}

function New-SmokeBuildProfileSettings {
    @{
        Profile = 'WinMint'
        ISOPath = (Get-WinMintTestIsoFixturePath)
        Architecture = 'arm64'
        ComputerName = 'WinMint'
        AccountName = 'dev'
        DriverSource = 'None'
        DriverPath = ''
    }
}

function Assert-FormFactorAndPowerProfile {
    $defaultConfig = New-WinMintBuildConfig -BuildProfile (New-SmokeBuildProfile)
    if ([string]$defaultConfig.FormFactor -ne 'Auto') {
        Add-SmokeFailure "Default build config FormFactor should be 'Auto', got '$($defaultConfig.FormFactor)'."
    }
    if ([string]$defaultConfig.PowerPlan -ne 'Balanced') {
        Add-SmokeFailure "Default build config PowerPlan should be 'Balanced', got '$($defaultConfig.PowerPlan)'."
    }
    foreach ($expected in @('filesystem-performance-policy', 'developer-telemetry-optout', 'telemetry-tracing-policy', 'terminal-admin-context', 'driver-coinstaller-policy')) {
        if (@($defaultConfig.RegistryTweaks) -notcontains $expected) {
            Add-SmokeFailure "Default Developer build should select registry tweak '$expected'."
        }
    }
    $defaultProfile = New-WinMintSetupProfile -BuildConfig $defaultConfig
    if ([string]$defaultProfile.power.formFactor -ne 'Auto') {
        Add-SmokeFailure 'Setup profile power.formFactor should default to Auto.'
    }
    if ([string]$defaultProfile.power.desktopPowerPlan -ne 'Balanced' -or [string]$defaultProfile.power.selectedPlan -ne 'Balanced') {
        Add-SmokeFailure 'Setup profile power plan should default to Balanced.'
    }
    if (-not [bool]$defaultProfile.privacy.disableTelemetryTasks) {
        Add-SmokeFailure 'Telemetry-on default should set privacy.disableTelemetryTasks.'
    }
    if (@($defaultProfile.privacy.telemetryTaskPatternsToDisable).Count -eq 0) {
        Add-SmokeFailure 'Default setup profile should carry telemetry scheduled-task patterns.'
    }
    $desktopProfile = New-WinMintBuildProfile -Settings @{
        Profile = 'Developer'
        ProfileGroups = @('Minimal', 'Developer')
        ISOPath = (Get-WinMintTestIsoFixturePath)
        Architecture = 'arm64'
        ComputerName = 'WinMint'
        AccountName = 'dev'
        DriverSource = 'None'
        DriverPath = ''
        FormFactor = 'Desktop'
    }
    $desktopConfig = New-WinMintBuildConfig -BuildProfile $desktopProfile
    if ([string]$desktopConfig.FormFactor -ne 'Desktop') {
        Add-SmokeFailure "FormFactor=Desktop should flow to build config, got '$($desktopConfig.FormFactor)'."
    }
    $ultimateProfile = New-WinMintBuildProfile -Settings @{
        Profile = 'WinMint'
        ISOPath = (Get-WinMintTestIsoFixturePath)
        Architecture = 'arm64'
        ComputerName = 'WinMint'
        AccountName = 'dev'
        DriverSource = 'None'
        DriverPath = ''
        PowerPlan = 'UltimatePerformance'
    }
    $ultimateConfig = New-WinMintBuildConfig -BuildProfile $ultimateProfile
    $ultimateSetup = New-WinMintSetupProfile -BuildConfig $ultimateConfig
    if ([string]$ultimateSetup.power.selectedPlan -ne 'UltimatePerformance') {
        Add-SmokeFailure 'Explicit PowerPlan=UltimatePerformance should flow to the setup profile.'
    }
}

function Assert-ProfileFailsWith {
    param(
        [Parameter(Mandatory)][object]$Profile,
        [Parameter(Mandatory)][string]$Expected
    )

    $result = Test-WinMintBuildProfile -BuildProfile $Profile
    if ($result.Passed) {
        Add-SmokeFailure "Expected profile validation to fail: $Expected"
        return
    }
    if (($result.Failures -join "`n") -notmatch [regex]::Escape($Expected)) {
        Add-SmokeFailure "Expected validation failure '$Expected', got: $($result.Failures -join '; ')"
    }
}

function Assert-PayloadCopyPreservesRootAndFolders {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath().TrimEnd('\', '/')) ('winmint_payload_copy_test_' + [Guid]::NewGuid().ToString('n'))
    $source = Join-Path $tempRoot 'source'
    $dest = Join-Path $tempRoot 'dest'
    try {
        $null = New-Item -ItemType Directory -Path (Join-Path $source 'cs') -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $source 'Modules\TestModule') -Force
        Set-Content -LiteralPath (Join-Path $source 'pwsh.exe') -Value 'exe' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $source 'root.dll') -Value 'root' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $source 'cs\resource.dll') -Value 'resource' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $source 'Modules\TestModule\Test.psm1') -Value 'module' -Encoding ASCII

        Copy-WinMintPayloadDirectoryChildren -SourceDir $source -DestinationDir $dest

        foreach ($expected in @('pwsh.exe', 'root.dll', 'cs\resource.dll', 'Modules\TestModule\Test.psm1')) {
            if (-not (Test-Path -LiteralPath (Join-Path $dest $expected))) {
                Add-SmokeFailure "Expected payload copy to preserve '$expected'."
            }
        }
        if (Test-Path -LiteralPath (Join-Path $dest 'resource.dll')) {
            Add-SmokeFailure 'Expected payload copy not to flatten child directory files into the destination root.'
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Assert-MountedImagePathIgnoresInvalidRecords {
    $active = [pscustomobject]@{
        MountPath = 'C:\Temp\WinMint_ISO_active\mount'
        Path = 'C:\Temp\WinMint_ISO_active\mount'
        MountStatus = 'Ok'
    }
    $invalid = [pscustomobject]@{
        MountPath = 'C:\Temp\WinMint_ISO_invalid\mount'
        Path = 'C:\Temp\WinMint_ISO_invalid\mount'
        MountStatus = 'Invalid'
    }
    if (-not (Test-WinMintMountedImagePath -Path 'C:\Temp\WinMint_ISO_active\mount' -MountedImages @($active, $invalid))) {
        Add-SmokeFailure 'Expected mounted-image helper to recognize an active mount record.'
    }
    if (Test-WinMintMountedImagePath -Path 'C:\Temp\WinMint_ISO_invalid\mount' -MountedImages @($active, $invalid)) {
        Add-SmokeFailure 'Expected mounted-image helper to ignore invalid mount records.'
    }
    if (Test-WinMintMountedImagePath -Path 'C:\Temp\WinMint_ISO_absent\mount' -MountedImages @($active, $invalid)) {
        Add-SmokeFailure 'Expected mounted-image helper to ignore absent mount records.'
    }
}

function Assert-OscdimgSelectionPrefersNativeHostArchitecture {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath().TrimEnd('\', '/')) ('winmint_oscdimg_selection_test_' + [Guid]::NewGuid().ToString('n'))
    try {
        $candidates = foreach ($arch in @('amd64', 'arm64', 'x86')) {
            $path = Join-Path $tempRoot "Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$arch\Oscdimg\oscdimg.exe"
            $null = New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force
            Set-Content -LiteralPath $path -Value 'oscdimg fixture' -Encoding ASCII
            $path
        }

        $selectedArm64 = Select-PreferredOscdimgExe -CandidatePaths $candidates -HostProcessorArch 'arm64'
        if ($selectedArm64 -notmatch '(?i)[\\/]arm64[\\/]Oscdimg[\\/]oscdimg\.exe$') {
            Add-SmokeFailure "Expected ARM64 hosts to prefer native oscdimg, got: $selectedArm64"
        }

        $selectedAmd64 = Select-PreferredOscdimgExe -CandidatePaths $candidates -HostProcessorArch 'amd64'
        if ($selectedAmd64 -notmatch '(?i)[\\/]amd64[\\/]Oscdimg[\\/]oscdimg\.exe$') {
            Add-SmokeFailure "Expected amd64 hosts to prefer amd64 oscdimg, got: $selectedAmd64"
        }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Assert-IsoBootUsesNoPromptEfiWhenAvailable {
    $packagesPath = Join-Path $root 'src\runtime\image\Private\Image\Packages.ps1'
    $stagingPath = Join-Path $root 'src\runtime\image\Private\Image\Staging.ps1'
    $packagesText = Get-Content -LiteralPath $packagesPath -Raw
    $stagingText = Get-Content -LiteralPath $stagingPath -Raw

    foreach ($expected in @('efisys_noprompt.bin', 'efisys.bin')) {
        if ($packagesText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "ISO bootdata selection should reference '$expected'."
        }
        if ($stagingText -notmatch [regex]::Escape($expected)) {
            Add-SmokeFailure "ISO staging validation should reference '$expected'."
        }
    }
    $noPromptIndex = $packagesText.IndexOf('efisys_noprompt.bin')
    $promptIndex = $packagesText.IndexOf('efisys.bin')
    if ($noPromptIndex -lt 0 -or $promptIndex -lt 0 -or $noPromptIndex -gt $promptIndex) {
        Add-SmokeFailure 'ISO bootdata selection should prefer efisys_noprompt.bin before falling back to efisys.bin.'
    }
}

function Assert-BuildResultContractAcceptsPipelineOutput {
    $expected = 'C:\ISO\out.iso'
    $clean = [pscustomobject]@{ OutputIsoPath = $expected; WorkDir = 'C:\Temp\WinMint'; DryRun = $false }
    $polluted = @(
        'cleanup log line'
        [pscustomobject]@{ Unrelated = $true }
        $clean
    )

    if ((Get-WinMintBuildOutputPathFromPipelineResult -PipelineResult $clean -FallbackPath 'C:\Fallback') -ne $expected) {
        Add-SmokeFailure 'Expected build output helper to read OutputIsoPath from a clean pipeline result.'
    }
    if ((Get-WinMintBuildOutputPathFromPipelineResult -PipelineResult $polluted -FallbackPath 'C:\Fallback') -ne $expected) {
        Add-SmokeFailure 'Expected build output helper to read OutputIsoPath from mixed pipeline output.'
    }
    if ((Get-WinMintBuildOutputPathFromPipelineResult -PipelineResult @('noise') -FallbackPath 'C:\Fallback') -ne 'C:\Fallback') {
        Add-SmokeFailure 'Expected build output helper to return fallback when no OutputIsoPath exists.'
    }
    try {
        $emptyFallback = Get-WinMintBuildOutputPathFromPipelineResult -PipelineResult @('noise') -FallbackPath ''
        if ($emptyFallback -ne '') {
            Add-SmokeFailure 'Expected build output helper to allow an empty fallback for optional ISO output.'
        }
    }
    catch {
        Add-SmokeFailure "Expected build output helper to accept empty fallback, got: $($_.Exception.Message)"
    }
}

function Assert-StartBuildReturnsSingleResultContract {
    $profile = New-SmokeBuildProfile
    $profile.source.isoPath = ''
    $result = Start-WinMintBuild -BuildProfile $profile -DryRun -ProgressHandler {
        param($ProgressEvent)
        [void]$ProgressEvent
    }
    $items = @($result)
    if ($items.Count -ne 1) {
        Add-SmokeFailure "Expected Start-WinMintBuild to emit one result object, got $($items.Count)."
        return
    }
    if (-not $items[0].PSObject.Properties['Paths']) {
        Add-SmokeFailure 'Expected Start-WinMintBuild result to expose Paths for UI report logging.'
    }
    if (-not $items[0].PSObject.Properties['OutputPath']) {
        Add-SmokeFailure 'Expected Start-WinMintBuild result to expose OutputPath for UI completion.'
    }
}

function Assert-ManifestPayloadsAreDeduplicated {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath().TrimEnd('\', '/')) ('winmint_manifest_dedupe_test_' + [Guid]::NewGuid().ToString('n'))
    try {
        $null = New-Item -ItemType Directory -Path $tempRoot -Force
        $config = New-WinMintBuildConfig -BuildProfile (New-SmokeBuildProfile)
        Initialize-WinMintBuildManifest -Config $config
        Add-WinMintManifestPayload -Name 'PowerShell 7' -SourceUrl 'https://example.invalid/pwsh.zip' -Version 'v1' -Sha256 'abc' -SizeBytes 123
        Add-WinMintManifestPayload -Name 'PowerShell 7' -SourceUrl 'https://example.invalid/pwsh.zip' -Version 'v1' -Sha256 'abc' -SizeBytes 123
        $manifestPath = Save-WinMintBuildManifest -OutputDir $tempRoot
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if (@($manifest.payloads).Count -ne 1) {
            Add-SmokeFailure 'Expected manifest payload list to deduplicate repeated payload entries.'
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        Clear-WinMintBuildManifest
    }
}

function Assert-TweakAuditArtifactsAreWritten {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath().TrimEnd('\', '/')) ('winmint_tweak_audit_test_' + [Guid]::NewGuid().ToString('n'))
    try {
        $null = New-Item -ItemType Directory -Path $tempRoot -Force
        $config = New-WinMintBuildConfig -BuildProfile (New-SmokeBuildProfile)
        Initialize-WinMintBuildManifest -Config $config

        $applied = $script:RegistryTweaks | Where-Object id -eq 'explorer-qol' | Select-Object -First 1
        $skipped = $script:RegistryTweaks | Where-Object id -eq 'hardware-bypass' | Select-Object -First 1
        $failed = $script:RegistryTweaks | Where-Object id -eq 'gamebar-policy' | Select-Object -First 1
        Add-WinMintManifestRegistryTweakEvent -Group $applied -Status 'applied'
        Add-WinMintManifestRegistryTweakEvent -Group $skipped -Status 'skipped-not-selected'
        Add-WinMintManifestRegistryTweakEvent -Group $failed -Status 'failed' -ErrorMessage 'fixture failure'

        $manifestPath = Save-WinMintBuildManifest -OutputDir $tempRoot
        $auditPath = Join-Path $tempRoot 'WinMint-TweakAudit.json'
        $mdPath = Join-Path $tempRoot 'WinMint-TweakAudit.md'
        $regPath = Join-Path $tempRoot 'WinMint-TweakRollback.reg'
        $buildDeltaPath = Join-Path $tempRoot 'WinMint-BuildDelta.json'
        foreach ($path in @($manifestPath, $auditPath, $mdPath, $regPath, $buildDeltaPath)) {
            if (-not (Test-Path -LiteralPath $path)) {
                Add-SmokeFailure "Expected tweak audit artifact to exist: $path"
            }
        }

        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if (-not $manifest.tweaks.PSObject.Properties['registryGroupsApplied']) {
            Add-SmokeFailure 'Expected manifest to preserve tweaks.registryGroupsApplied.'
        }
        if (@($manifest.tweaks.registryGroups).Count -eq 0) {
            Add-SmokeFailure 'Expected manifest to include detailed tweaks.registryGroups.'
        }
        if (-not $manifest.audit -or [string]::IsNullOrWhiteSpace([string]$manifest.audit.buildDeltaPath)) {
            Add-SmokeFailure 'Expected manifest audit metadata to include the BuildDelta artifact path.'
        }
        $audit = Get-Content -LiteralPath $auditPath -Raw | ConvertFrom-Json
        if ([int]$audit.summary.applied -lt 1 -or [int]$audit.summary.failed -lt 1) {
            Add-SmokeFailure 'Expected tweak audit JSON to summarize applied and failed events.'
        }
        $buildDelta = Get-Content -LiteralPath $buildDeltaPath -Raw | ConvertFrom-Json
        if (@($buildDelta.records).Count -eq 0) {
            Add-SmokeFailure 'Expected BuildDelta to contain at least one selected backend change record.'
        }
        $regText = Get-Content -LiteralPath $regPath -Raw
        foreach ($expected in @('Windows Registry Editor Version 5.00', 'HideFileExt', 'dword:00000001')) {
            if ($regText -notmatch [regex]::Escape($expected)) {
                Add-SmokeFailure "Expected rollback .reg to contain '$expected'."
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        Clear-WinMintBuildManifest
    }
}

function Assert-CachedDownloadResolver {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath().TrimEnd('\', '/')) ('winmint_cache_resolver_test_' + [Guid]::NewGuid().ToString('n'))
    try {
        $null = New-Item -ItemType Directory -Path $tempRoot -Force
        $old = Join-Path $tempRoot 'PowerShell-7.5.0-win-arm64.zip'
        $new = Join-Path $tempRoot 'PowerShell-7.6.1-win-arm64.zip'
        Set-Content -LiteralPath $old -Value 'old' -Encoding ASCII
        Start-Sleep -Milliseconds 20
        Set-Content -LiteralPath $new -Value 'new' -Encoding ASCII

        $resolved = Get-WinMintCachedDownloadFile -DownloadDir $tempRoot -Patterns @('PowerShell-*-win-arm64.zip')
        if ($resolved -ne $new) {
            Add-SmokeFailure "Expected cached download resolver to pick newest matching file, got '$resolved'."
        }
        $missing = Get-WinMintCachedDownloadFile -DownloadDir $tempRoot -Patterns @('ViVeTool-*Arm64*.zip')
        if ($null -ne $missing) {
            Add-SmokeFailure 'Expected cached download resolver to return null when no pattern matches.'
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Assert-OfflinePayloadCacheStatus {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath().TrimEnd('\', '/')) ('winmint_payload_status_test_' + [Guid]::NewGuid().ToString('n'))
    $downloads = Join-Path $tempRoot 'downloads'
    $fonts = Join-Path $tempRoot 'fonts'
    try {
        $null = New-Item -ItemType Directory -Path $downloads -Force
        $null = New-Item -ItemType Directory -Path $fonts -Force
        Set-Content -LiteralPath (Join-Path $downloads 'PowerShell-7.6.1-win-arm64.zip') -Value 'ps7' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $downloads 'ViVeTool-v0.3.4-SnapdragonArm64.zip') -Value 'vive' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $downloads 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle') -Value 'winget' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $fonts 'CascadiaCodeNF-Regular.ttf') -Value 'font' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $fonts 'MonaspaceNeonNerdFont-Regular.ttf') -Value 'font' -Encoding ASCII

        $complete = Get-WinMintOfflinePayloadCacheStatus -Architecture 'arm64' -DownloadDir $downloads -FontDir $fonts
        if (-not $complete.Complete) {
            Add-SmokeFailure "Expected complete offline payload cache, missing: $($complete.Missing -join ', ')"
        }

        Remove-Item -LiteralPath (Join-Path $downloads 'ViVeTool-v0.3.4-SnapdragonArm64.zip') -Force
        $incomplete = Get-WinMintOfflinePayloadCacheStatus -Architecture 'arm64' -DownloadDir $downloads -FontDir $fonts
        if ($incomplete.Complete -or @($incomplete.Missing) -notcontains 'ViVeTool') {
            Add-SmokeFailure 'Expected offline payload cache status to report missing ViVeTool.'
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Assert-ImageUpdateProfileContract {
    $defaultProfile = New-WinMintBuildProfile -Settings (New-SmokeBuildProfileSettings)
    if ([string]$defaultProfile.updates.mode -ne 'None') {
        Add-SmokeFailure "Expected image updates to default to None, got '$($defaultProfile.updates.mode)'."
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$defaultProfile.updates.payloadRoot)) {
        Add-SmokeFailure 'Expected default image updates to leave payload root empty.'
    }
    $defaultConfig = New-WinMintBuildConfig -BuildProfile $defaultProfile
    if ([string]$defaultConfig.Updates.Mode -ne 'None') {
        Add-SmokeFailure "Expected build config updates to default to None, got '$($defaultConfig.Updates.Mode)'."
    }

    $optInSettings = New-SmokeBuildProfileSettings
    $optInSettings.UpdateImage = 'Stable25H2'
    $optInProfile = New-WinMintBuildProfile -Settings $optInSettings
    $optInConfig = New-WinMintBuildConfig -BuildProfile $optInProfile
    if ([string]$optInProfile.updates.mode -ne 'Stable25H2' -or [string]$optInConfig.Updates.Mode -ne 'Stable25H2') {
        Add-SmokeFailure 'Expected UpdateImage Stable25H2 to opt in to offline image updates.'
    }

    $missingSettings = New-SmokeBuildProfileSettings
    $missingSettings.UpdateImage = 'Stable25H2'
    $missingSettings.UpdatePayloadRoot = Join-Path ([IO.Path]::GetTempPath().TrimEnd('\', '/')) ('winmint-missing-update-root-' + [Guid]::NewGuid().ToString('n'))
    $missingSettings.ISOPath = Get-WinMintTestOfficialIsoFixturePath
    $missingProfile = New-WinMintBuildProfile -Settings $missingSettings
    $missingConfig = New-WinMintBuildConfig -BuildProfile $missingProfile
    $missingPreflight = Test-WinMintBuildPrerequisite -Config $missingConfig -RunMode DryRun
    if ($missingPreflight.Passed -or ($missingPreflight.Failures -join '; ') -notmatch 'Update payload root not found') {
        Add-SmokeFailure 'Expected Stable25H2 preflight to require an explicit update payload root.'
    }
    if (@($missingPreflight.Findings | Where-Object Code -eq 'updates.payloadRoot.notFound').Count -ne 1) {
        Add-SmokeFailure 'Expected missing Stable25H2 payload root to emit updates.payloadRoot.notFound.'
    }
    $buildPreflightContext = New-WinMintBuildPreflightContext -RunMode Build
    $dryRunPreflightContext = New-WinMintBuildPreflightContext -RunMode DryRun
    if (-not [bool]$buildPreflightContext.RequireOnlinePayloadCache -or [bool]$dryRunPreflightContext.RequireOnlinePayloadCache) {
        Add-SmokeFailure 'Expected preflight context to require online/cache payload readiness only for real builds.'
    }
    if ([string]$buildPreflightContext.SourceIsoPolicy -ne 'Required' -or [string]$dryRunPreflightContext.SourceIsoPolicy -ne 'ProfileOnlyOptional') {
        Add-SmokeFailure 'Expected preflight context to expose run-mode-specific source ISO policy.'
    }
    if ($buildPreflightContext.PSObject.Properties['AllowMissingSourceIso'] -or $dryRunPreflightContext.PSObject.Properties['AllowMissingSourceIso']) {
        Add-SmokeFailure 'Expected generated preflight contexts to avoid legacy AllowMissingSourceIso flags.'
    }

    $unsupportedPackageSettings = New-SmokeBuildProfileSettings
    $unsupportedPackageSettings.InstallWindhawk = $true
    $unsupportedPackageProfile = New-WinMintBuildProfile -Settings $unsupportedPackageSettings
    $unsupportedPackageConfig = New-WinMintBuildConfig -BuildProfile $unsupportedPackageProfile
    $unsupportedPackagePreflight = Test-WinMintBuildPrerequisite -Config $unsupportedPackageConfig -RunMode DryRun
    if (-not $unsupportedPackagePreflight.Passed) {
        Add-SmokeFailure "Expected unsupported optional package architecture to warn, not fail: $($unsupportedPackagePreflight.Failures -join '; ')"
    }
    if (@($unsupportedPackagePreflight.Findings | Where-Object { $_.Code -eq 'packages.tool.architectureUnsupported' -and $_.Severity -eq 'warning' }).Count -lt 1) {
        Add-SmokeFailure 'Expected ARM64 Windhawk selection to emit packages.tool.architectureUnsupported warning.'
    }

    $tempRoot = Join-Path ([IO.Path]::GetTempPath().TrimEnd('\', '/')) ('winmint_update_payload_test_' + [Guid]::NewGuid().ToString('n'))
    try {
        $packages = Join-Path $tempRoot 'packages'
        $appx = Join-Path $tempRoot 'appx'
        $deps = Join-Path $tempRoot 'appx-dependencies\arm64'
        $null = New-Item -ItemType Directory -Path $packages, $appx, $deps -Force
        $lcu = Join-Path $packages 'windows11.0-kb0000000-arm64.msu'
        $terminal = Join-Path $appx 'Microsoft.WindowsTerminal.msixbundle'
        $vclibs = Join-Path $deps 'Microsoft.VCLibs.arm64.appx'
        Set-Content -LiteralPath $lcu -Value 'lcu' -Encoding ASCII
        Set-Content -LiteralPath $terminal -Value 'terminal' -Encoding ASCII
        Set-Content -LiteralPath $vclibs -Value 'dependency' -Encoding ASCII

        $settings = New-SmokeBuildProfileSettings
        $settings.UpdateImage = 'Stable25H2'
        $settings.UpdatePayloadRoot = $tempRoot
        $profile = New-WinMintBuildProfile -Settings $settings
        $result = Test-WinMintBuildProfile -BuildProfile $profile
        if (-not $result.Passed) {
            Add-SmokeFailure "Expected Stable25H2 update profile to validate, got: $($result.Failures -join '; ')"
        }
        $config = New-WinMintBuildConfig -BuildProfile $profile
        if ([string]$config.Updates.Mode -ne 'Stable25H2' -or [string]$config.Updates.ReleaseCadence -ne 'BRelease' -or [bool]$config.Updates.IncludeOptionalPreviews) {
            Add-SmokeFailure 'Expected Stable25H2 update settings to flow to build config with B-release previews disabled.'
        }
        $preflight = Test-WinMintBuildPrerequisite -Config $config -RunMode DryRun
        if (-not $preflight.Passed) {
            Add-SmokeFailure "Expected Stable25H2 preflight to pass with a payload root. Failures: $($preflight.Failures -join '; ')"
        }
        if (@($preflight.Findings | Where-Object Severity -eq 'failure').Count -ne 0) {
            Add-SmokeFailure 'Expected Stable25H2 preflight with a payload root to have no failure findings.'
        }
        $resolvedPackages = @(Get-WinMintOfflineUpdatePackageFiles -PayloadRoot $tempRoot -Category 'packages')
        if ($resolvedPackages -ne $lcu) {
            Add-SmokeFailure "Expected update package resolver to find the LCU fixture, got: $($resolvedPackages -join ', ')"
        }
        $resolvedAppx = @(Get-WinMintOfflineUpdateAppxFiles -PayloadRoot $tempRoot)
        if ($resolvedAppx -ne $terminal) {
            Add-SmokeFailure "Expected update AppX resolver to find Terminal fixture, got: $($resolvedAppx -join ', ')"
        }
        $resolvedDeps = @(Get-WinMintOfflineUpdateAppxDependencyFiles -PayloadRoot $tempRoot -TargetArch 'arm64')
        if ($resolvedDeps -ne $vclibs) {
            Add-SmokeFailure "Expected update AppX dependency resolver to find ARM64 dependency fixture, got: $($resolvedDeps -join ', ')"
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Assert-UpdatePayloadHashHelpers {
    $catalogSha256 = 'TT00I9uVmDM8VR+eMEpWxho251EODaPXr2NpI/Q7hBI='
    $expectedHex = '4D3D3423DB9598333C551F9E304A56C61A36E7510E0DA3D7AF636923F43B8412'
    $actualHex = ConvertFrom-WinMintCatalogBase64Sha256 -Sha256Base64 $catalogSha256
    if ($actualHex -ne $expectedHex) {
        Add-SmokeFailure "Expected Catalog Base64 SHA256 to convert to $expectedHex, got $actualHex."
    }

    try {
        $null = ConvertFrom-WinMintCatalogBase64Sha256 -Sha256Base64 'not-a-valid-hash'
        Add-SmokeFailure 'Expected invalid Catalog Base64 SHA256 metadata to fail closed.'
    }
    catch {
    }
}

function Assert-HeadlessConsoleProfileContract {
    $headlessComputerName = 'headless-pc'
    $microsoftOobeComputerName = 'SL7'

    $profile = New-WinMintConsoleHeadlessProfile `
        -SourceIso '' `
        -Architecture 'arm64' `
        -ComputerName $headlessComputerName `
        -AccountName 'builder' `
        -InstallYasb `
        -DryRun

    $result = Test-WinMintBuildProfile -BuildProfile $profile
    if (-not $result.Passed) {
        Add-SmokeFailure "Expected headless console profile to pass validation, got: $($result.Failures -join '; ')"
    }
    if ($profile.source.architecture -ne 'arm64') {
        Add-SmokeFailure 'Expected headless console profile to preserve explicit architecture.'
    }
    if ($profile.identity.computerName -ne $headlessComputerName -or $profile.identity.accountName -ne 'builder') {
        Add-SmokeFailure 'Expected headless console profile to preserve identity arguments.'
    }
    if (@($profile.desktop.layers) -notcontains 'yasb') {
        Add-SmokeFailure 'Expected headless console profile to include selected desktop layer.'
    }

    $msProfile = New-WinMintConsoleHeadlessProfile `
        -SourceIso '' `
        -Architecture 'arm64' `
        -ComputerName $microsoftOobeComputerName `
        -AccountName 'Yanai' `
        -AccountMode MicrosoftOobe `
        -TimeZoneId 'Israel Standard Time' `
        -InputLocale 'en-US;he-IL' `
        -SystemLocale 'he-IL' `
        -UILanguage 'en-US' `
        -UILanguageFallback 'en-US' `
        -UserLocale 'he-IL' `
        -DryRun
    if ($msProfile.identity.accountMode -ne 'MicrosoftOobe') {
        Add-SmokeFailure 'Expected headless console profile to preserve Microsoft OOBE account mode.'
    }
    if ($msProfile.regional.timeZoneId -ne 'Israel Standard Time' -or $msProfile.regional.inputLocale -ne 'en-US;he-IL') {
        Add-SmokeFailure 'Expected headless console profile to preserve explicit Israel regional settings and keyboard list.'
    }

    try {
        $null = New-WinMintConsoleHeadlessProfile -SourceIso '' -Architecture 'amd64'
        Add-SmokeFailure 'Expected non-dry-run headless console profile to require a source ISO.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'SourceIso|ProfilePath') {
            Add-SmokeFailure "Expected source ISO requirement error, got: $($_.Exception.Message)"
        }
    }

    try {
        $null = New-WinMintConsoleHeadlessProfile -SourceIso '' -Architecture 'amd64' -AutoLogon -DryRun
        Add-SmokeFailure 'Expected headless autologon to require an included password.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'Autologon requires') {
            Add-SmokeFailure "Expected autologon password error, got: $($_.Exception.Message)"
        }
    }
}

function Assert-HeadlessCliContracts {
    $templatePath = Join-Path ([IO.Path]::GetTempPath()) ('winmint-new-profile-' + [Guid]::NewGuid().ToString('n') + '.json')
    $outProfilePath = Join-Path ([IO.Path]::GetTempPath()) ('winmint-out-profile-' + [Guid]::NewGuid().ToString('n') + '.json')
    try {
        $templateResult = Invoke-WinMintNewProfileCommand -OutPath $templatePath -Quiet
        if ($templateResult.result -ne 'profile-created' -or -not (Test-Path -LiteralPath $templatePath)) {
            Add-SmokeFailure 'Expected `new` to create an editable profile without requiring build inputs.'
        }
        $template = Get-Content -LiteralPath $templatePath -Raw | ConvertFrom-Json
        $templateValidation = Test-WinMintBuildProfile -BuildProfile $template
        if (-not $templateValidation.Passed) {
            Add-SmokeFailure "Expected -NewProfile output to validate, got: $($templateValidation.Failures -join '; ')"
        }
        # Subtractive model: the default template keeps nothing and preselects no
        # editors or WSL distros; developer tooling is baseline.
        if ([bool]$template.keep.edge -or [bool]$template.keep.gaming -or [bool]$template.keep.copilot -or @($template.development.editors).Count -ne 0 -or @($template.development.wsl.distros).Count -ne 0) {
            Add-SmokeFailure 'Expected default template to keep nothing without preselecting editors or WSL distros.'
        }
        if ([int]$template.schemaVersion -ne 3) {
            Add-SmokeFailure 'Expected generated profile templates to use schemaVersion 3.'
        }
        if (-not [bool]$template.tweaks.dmaInterop) {
            Add-SmokeFailure 'Expected generated profile templates to enable DMA interoperability by default.'
        }
        if (-not [bool]$template.privacy.location) {
            Add-SmokeFailure 'Expected generated profile templates to enable location services by default.'
        }
        if ($template.regional.userLocale -ne 'en-US' -or [int]$template.regional.homeLocationGeoId -ne 244) {
            Add-SmokeFailure 'Expected generated profile templates to default visible region to en-US/GeoID 244.'
        }

        $outResult = Invoke-WinMintNewProfileCommand -OutPath $outProfilePath -KeepGaming -Architecture amd64 -Quiet
        if ($outResult.result -ne 'profile-created' -or -not (Test-Path -LiteralPath $outProfilePath)) {
            Add-SmokeFailure 'Expected `new` to save flag-authored intent without building.'
        }
        $outProfile = Get-Content -LiteralPath $outProfilePath -Raw | ConvertFrom-Json
        # Subtractive model: -KeepGaming sets the keep.gaming flag. Template mode
        # leaves shell layers unselected.
        if (-not [bool]$outProfile.keep.gaming) {
            Add-SmokeFailure 'Expected -KeepGaming to set the keep.gaming flag in the saved profile.'
        }
        if ((@($outProfile.desktop.layers) -join ',') -ne 'standard') {
            Add-SmokeFailure 'Expected profile templates to avoid preselecting shell layers unless explicit layer flags are supplied.'
        }
    }
    finally {
        Remove-Item -LiteralPath $templatePath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $outProfilePath -Force -ErrorAction SilentlyContinue
    }

    # Profile is the source of truth: the build verb structurally has no
    # authoring/identity parameters, so passing one is rejected at parameter binding.
    try {
        $null = Invoke-WinMintBuildCommand -ProfilePath 'config\build-profiles\yanai-sl7-microsoft-oobe.json' -ComputerName 'Other'
        Add-SmokeFailure 'Expected the build verb to reject authoring/identity flags.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'ComputerName|parameter') {
            Add-SmokeFailure "Expected build verb to reject -ComputerName, got: $($_.Exception.Message)"
        }
    }

    $microsoftOobeComputerName = 'SL7'
    $profile = New-WinMintHeadlessProfileFromFlags `
        -SourceIso '' `
        -Architecture 'arm64' `
        -ComputerName $microsoftOobeComputerName `
        -AccountName 'Yanai' `
        -AccountMode MicrosoftOobe `
        -TimeZoneId 'Israel Standard Time' `
        -InputLocale 'en-US;he-IL' `
        -SystemLocale 'he-IL' `
        -UILanguage 'en-US' `
        -UILanguageFallback 'en-US' `
        -UserLocale 'he-IL' `
        -DryRun
    $config = New-WinMintBuildConfig -BuildProfile $profile
    # Subtractive model: the default build already removes the Copilot+ AI surface.
    if ($config.AccountMode -ne 'MicrosoftOobe') {
        Add-SmokeFailure 'Expected flag-built headless profile to preserve MicrosoftOobe intent.'
    }
    if ($config.TimeZoneId -ne 'Israel Standard Time' -or $config.InputLocale -ne 'en-US;he-IL') {
        Add-SmokeFailure 'Expected flag-built headless profile to preserve regional and keyboard settings.'
    }
    if ($config.UserLocale -ne 'he-IL' -or $config.HomeLocationGeoId -ne 117) {
        Add-SmokeFailure 'Expected flag-built headless profile to preserve the builder home region for post-FirstLogon restore.'
    }
    if ($config.SetupUserLocale -ne 'en-IE' -or $config.SetupHomeLocationGeoId -ne 68 -or -not [bool]$config.DmaInterop.Enabled) {
        Add-SmokeFailure 'Expected DMA interoperability to default on and use Ireland as the setup region.'
    }
    if ($config.UserLocale -ne 'he-IL' -or $config.HomeLocationGeoId -ne 117) {
        Add-SmokeFailure 'Expected default DMA interoperability to preserve the configured real restore region.'
    }

    $noDmaProfile = New-WinMintHeadlessProfileFromFlags `
        -SourceIso '' `
        -Architecture 'amd64' `
        -Dma Off `
        -DryRun
    $noDmaConfig = New-WinMintBuildConfig -BuildProfile $noDmaProfile
    if ([bool]$noDmaConfig.DmaInterop.Enabled -or $noDmaConfig.SetupUserLocale -ne 'en-US' -or $noDmaConfig.SetupHomeLocationGeoId -ne 244) {
        Add-SmokeFailure 'Expected -NoDmaInterop to disable the Ireland setup latch and use visible en-US setup region.'
    }

    $dmaProfile = New-WinMintHeadlessProfileFromFlags `
        -SourceIso '' `
        -Architecture 'amd64' `
        -TimeZoneId 'Israel Standard Time' `
        -InputLocale 'en-US;he-IL' `
        -SystemLocale 'en-US' `
        -UILanguage 'en-US' `
        -UserLocale 'he-IL' `
        -Dma On `
        -DryRun
    $dmaConfig = New-WinMintBuildConfig -BuildProfile $dmaProfile
    if ($dmaConfig.SetupUserLocale -ne 'en-IE' -or $dmaConfig.SetupHomeLocationGeoId -ne 68 -or -not [bool]$dmaConfig.DmaInterop.Enabled) {
        Add-SmokeFailure 'Expected explicit DMA interoperability to use Ireland as the setup region.'
    }
    if ($dmaConfig.UserLocale -ne 'he-IL' -or $dmaConfig.HomeLocationGeoId -ne 117 -or $dmaConfig.TimeZoneId -ne 'Israel Standard Time') {
        Add-SmokeFailure 'Expected DMA interoperability to preserve the configured real restore region, culture, and time zone.'
    }
    $dmaSetupProfile = New-WinMintSetupProfile -BuildConfig $dmaConfig
    if ($dmaSetupProfile.regional.dmaInterop.setupCountry -ne 'Ireland' -or
        $dmaSetupProfile.regional.dmaInterop.setupUserLocale -ne 'en-IE' -or
        [int]$dmaSetupProfile.regional.dmaInterop.setupHomeLocationGeoId -ne 68 -or
        $dmaSetupProfile.regional.dmaInterop.restoreUserLocale -ne 'he-IL' -or
        [int]$dmaSetupProfile.regional.dmaInterop.restoreHomeLocationGeoId -ne 117 -or
        $dmaSetupProfile.regional.dmaInterop.restoreTimeZoneId -ne 'Israel Standard Time') {
        Add-SmokeFailure 'Expected setup profile to keep DMA setup values separate from user restore values.'
    }
    Initialize-WinMintBuildManifest -Config $dmaConfig
    $manifestDma = (Get-WinMintBuildManifest).regional.dmaInterop
    if ($manifestDma.setupLatchedCountry -ne 'Ireland' -or
        [int]$manifestDma.setupLatchedGeoId -ne 68 -or
        $manifestDma.restoredUserLocale -ne 'he-IL' -or
        [int]$manifestDma.restoredHomeLocationGeoId -ne 117 -or
        $manifestDma.restoredTimeZoneId -ne 'Israel Standard Time') {
        Add-SmokeFailure 'Expected manifest to record both DMA setup latch values and restored user region values.'
    }
    if ($config.AppxPackages -notcontains 'Microsoft.Copilot' -or $config.AppxPackages -notcontains 'MicrosoftWindows.Client.WebExperience') {
        Add-SmokeFailure 'Expected default headless profile to remove Copilot/WebExperience AppX packages.'
    }
    if ($config.AiRemoval.Policy -ne 'ServiceableFull') {
        Add-SmokeFailure 'Expected default headless profile to select ServiceableFull AI removal.'
    }

    $minimalProfile = New-WinMintHeadlessProfileFromFlags -SourceIso '' -Architecture 'arm64' -DryRun
    $minimalConfig = New-WinMintBuildConfig -BuildProfile $minimalProfile
    if ([bool]$minimalProfile.keep.edge -or [bool]$minimalProfile.keep.gaming -or [bool]$minimalProfile.keep.copilot) {
        Add-SmokeFailure 'Expected omitted headless keep flags to default to keeping nothing.'
    }
    # Subtractive model: developer QoL (OpenSSH client, Developer Mode) is now
    # baseline on every build; WSL2 is also baseline even when no distro is
    # selected yet.
    if ($minimalConfig.Features -notcontains 'OpenSSH.Client' -or
        $minimalConfig.RegistryTweaks -notcontains 'developer-mode') {
        Add-SmokeFailure 'Expected default build to include baseline developer QoL (OpenSSH client, Developer Mode).'
    }
    if ($minimalConfig.Features -notcontains 'Microsoft-Windows-Subsystem-Linux' -or
        $minimalConfig.Features -notcontains 'VirtualMachinePlatform') {
        Add-SmokeFailure 'Expected WSL2 and Virtual Machine Platform to be baseline features.'
    }
    if ($minimalConfig.AppxPackages -notcontains 'Microsoft.Copilot' -or
        $minimalConfig.AppxPackages -notcontains 'Microsoft.GamingApp') {
        Add-SmokeFailure 'Expected default build to remove Copilot/WebExperience and Xbox gaming apps.'
    }
    if (-not [bool]$minimalConfig.Privacy.Location) {
        Add-SmokeFailure 'Expected default headless profile to enable location services for laptop-first builds.'
    }
    if (-not [bool]$minimalConfig.DmaInterop.Enabled -or $minimalConfig.SetupUserLocale -ne 'en-IE' -or $minimalConfig.SetupHomeLocationGeoId -ne 68) {
        Add-SmokeFailure 'Expected default headless profile to enable DMA interoperability through Ireland.'
    }

    $locationOnProfile = New-WinMintHeadlessProfileFromFlags -SourceIso '' -Architecture 'arm64' -Location On -DryRun
    $locationOnConfig = New-WinMintBuildConfig -BuildProfile $locationOnProfile
    if (-not [bool]$locationOnConfig.Privacy.Location) {
        Add-SmokeFailure 'Expected -Location On to keep location services enabled through the privacy policy profile.'
    }
    $locationOffProfile = New-WinMintHeadlessProfileFromFlags -SourceIso '' -Architecture 'arm64' -Location Off -DryRun
    $locationOffConfig = New-WinMintBuildConfig -BuildProfile $locationOffProfile
    if ([bool]$locationOffConfig.Privacy.Location -or @($locationOffConfig.RegistryTweaks) -notcontains 'location-disabled-policy') {
        Add-SmokeFailure 'Expected -Location Off to disable location services and select the location block policy.'
    }
    $dmaLocationProfile = New-WinMintHeadlessProfileFromFlags -SourceIso '' -Architecture 'arm64' -Dma On -Location On -DryRun
    $dmaLocationConfig = New-WinMintBuildConfig -BuildProfile $dmaLocationProfile
    $dmaLocationSetupProfile = New-WinMintSetupProfile -BuildConfig $dmaLocationConfig
    if (-not [bool]$dmaLocationConfig.Privacy.Location -or -not [bool]$dmaLocationSetupProfile.regional.dmaInterop.restoreLocationServices) {
        Add-SmokeFailure 'Expected location services to remain enable-able while DMA interoperability is enabled.'
    }

    # The -Dma/-Location settings are single On|Off selectors, so a conflicting
    # pair is structurally impossible; an out-of-set value is rejected by ValidateSet.
    try {
        $null = New-WinMintHeadlessProfileFromFlags -SourceIso '' -Architecture 'arm64' -Location 'Maybe' -DryRun
        Add-SmokeFailure 'Expected -Location to reject values outside On|Off.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'Location|ValidateSet|set') {
            Add-SmokeFailure "Expected -Location ValidateSet error, got: $($_.Exception.Message)"
        }
    }

    try {
        $null = New-WinMintHeadlessProfileFromFlags -SourceIso '' -Architecture 'arm64' -Dma 'Maybe' -DryRun
        Add-SmokeFailure 'Expected -Dma to reject values outside On|Off.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'Dma|ValidateSet|set') {
            Add-SmokeFailure "Expected -Dma ValidateSet error, got: $($_.Exception.Message)"
        }
    }

    # Subtractive model: -KeepGaming preserves Xbox apps and -DesktopUI selects the
    # WinMint shell stack; Copilot+ AI is still removed by default.
    $groupProfile = New-WinMintHeadlessProfileFromFlags `
        -SourceIso '' `
        -Architecture 'arm64' `
        -KeepGaming `
        -DesktopUI `
        -DryRun
    $groupConfig = New-WinMintBuildConfig -BuildProfile $groupProfile
    if (-not [bool]$groupProfile.keep.gaming) {
        Add-SmokeFailure 'Expected -KeepGaming to set the keep.gaming flag.'
    }
    if ([bool]$groupProfile.keep.copilot) {
        Add-SmokeFailure 'Expected Copilot to stay removed by default without -KeepCopilot.'
    }
    if ($groupConfig.Features -notcontains 'OpenSSH.Client' -or
        $groupConfig.RegistryTweaks -notcontains 'developer-mode' -or
        $groupConfig.RegistryTweaks -notcontains 'powershell-remotesigned') {
        Add-SmokeFailure 'Expected baseline build to enable OpenSSH, Developer Mode, and RemoteSigned.'
    }
    if (@($groupConfig.Editors).Count -ne 0 -or @($groupConfig.Wsl2Distros).Count -ne 0) {
        Add-SmokeFailure 'Expected baseline build to leave editors and WSL distros unselected by default.'
    }
    if ($groupConfig.Features -notcontains 'Microsoft-Windows-Subsystem-Linux' -or
        $groupConfig.Features -notcontains 'VirtualMachinePlatform') {
        Add-SmokeFailure 'Expected baseline build to include WSL2 and Virtual Machine Platform as developer baseline features.'
    }
    $groupAgentProfile = New-WinMintAgentProfile -BuildConfig $groupConfig
    if (-not [bool]$groupAgentProfile.modules.wsl.enabled -or @($groupAgentProfile.modules.wsl.distros).Count -ne 0) {
        Add-SmokeFailure 'Expected baseline build to keep the FirstLogon WSL module enabled with no distro selected.'
    }
    if ($groupConfig.AppxPackages -notcontains 'Microsoft.Copilot' -or
        $groupConfig.AppxPackages -notcontains 'MicrosoftWindows.Client.WebExperience' -or
        $groupConfig.AppxPackages -contains 'Microsoft.GamingApp') {
        Add-SmokeFailure 'Expected default Copilot removal to drop Copilot/WebExperience while -KeepGaming preserves Xbox apps.'
    }
    if ($groupConfig.RegistryTweaks -notcontains 'gaming-performance-policy' -or $groupConfig.RegistryTweaks -contains 'gamebar-policy') {
        Add-SmokeFailure 'Expected -KeepGaming to select gaming-performance-policy and suppress gamebar-policy.'
    }
    if (-not ($groupConfig.InstallWindhawk -and $groupConfig.InstallYasb -and $groupConfig.InstallKomorebi)) {
        Add-SmokeFailure 'Expected -DesktopUI to select the opinionated WinMint shell stack.'
    }
    if ($groupConfig.Launcher -ne 'None' -or $groupConfig.InstallRaycast) {
        Add-SmokeFailure 'Expected launcher modules to stay opt-in even when Developer/DesktopUI groups are selected.'
    }

    $raycastProfile = New-WinMintHeadlessProfileFromFlags `
        -SourceIso '' `
        -Architecture 'arm64' `
        -Launcher Raycast `
        -DryRun
    $raycastConfig = New-WinMintBuildConfig -BuildProfile $raycastProfile
    $raycastAgentProfile = New-WinMintAgentProfile -BuildConfig $raycastConfig
    if ($raycastConfig.Launcher -ne 'Raycast' -or -not $raycastConfig.InstallRaycast -or -not $raycastAgentProfile.modules.raycast.enabled) {
        Add-SmokeFailure 'Expected -Launcher Raycast to enable only Raycast in the FirstLogon agent profile.'
    }
    if (-not $raycastAgentProfile.modules.launcherKey.enabled -or $raycastAgentProfile.modules.launcherKey.target -ne 'Raycast' -or $raycastAgentProfile.modules.launcherKey.chord -ne 'Win+Shift+F23') {
        Add-SmokeFailure 'Expected Raycast builds to bind the launcher key to Raycast on the common Copilot hardware-key chord.'
    }
    if (-not $raycastAgentProfile.modules.packageManagers.enabled) {
        Add-SmokeFailure 'Expected -Launcher Raycast to enable package managers for first-logon installation.'
    }
    if ([string]$raycastAgentProfile.modules.raycast.everythingBackend.package -ne 'everything-arm64-beta') {
        Add-SmokeFailure 'Expected ARM64 Raycast builds to use the pinned native Everything ARM64 backend.'
    }

    $raycastAmd64Profile = New-WinMintHeadlessProfileFromFlags `
        -SourceIso '' `
        -Architecture 'amd64' `
        -Launcher Raycast `
        -DryRun
    $raycastAmd64Config = New-WinMintBuildConfig -BuildProfile $raycastAmd64Profile
    $raycastAmd64AgentProfile = New-WinMintAgentProfile -BuildConfig $raycastAmd64Config
    if ([string]$raycastAmd64AgentProfile.modules.raycast.everythingBackend.package -ne 'everything-beta') {
        Add-SmokeFailure 'Expected amd64 Raycast builds to use the package-manager Everything Beta backend.'
    }

    $thisPcProfile = New-WinMintHeadlessProfileFromFlags -SourceIso '' -Architecture 'arm64' -TargetDevice ThisPC -DryRun
    $thisPcConfig = New-WinMintBuildConfig -BuildProfile $thisPcProfile
    if ($thisPcConfig.TargetDevice -ne 'ThisPC' -or -not $thisPcConfig.ExportHostDrivers -or $thisPcConfig.Drivers.Source -ne 'Host') {
        Add-SmokeFailure 'Expected TargetDevice ThisPC to map to host driver export.'
    }

    $fakePack = Join-Path ([IO.Path]::GetTempPath()) ('winmint-driver-pack-' + [Guid]::NewGuid().ToString('n') + '.msi')
    try {
        Set-Content -LiteralPath $fakePack -Value 'not a real msi; normalization only' -Encoding ASCII
        $packProfile = New-WinMintHeadlessProfileFromFlags -SourceIso '' -Architecture 'arm64' -TargetDevice ThisPC -DriverPack $fakePack -DryRun
        $packConfig = New-WinMintBuildConfig -BuildProfile $packProfile
        if ($packConfig.Drivers.Source -ne 'Custom' -or $packConfig.ExportHostDrivers) {
            Add-SmokeFailure 'Expected explicit DriverPack to override ThisPC host driver export.'
        }
    }
    finally {
        Remove-Item -LiteralPath $fakePack -Force -ErrorAction SilentlyContinue
    }

    try {
        $null = New-WinMintHeadlessProfileFromFlags -SourceIso '' -Architecture 'amd64'
        Add-SmokeFailure 'Expected flag-built headless profile to require SourceIso outside dry-run.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'SourceIso') {
            Add-SmokeFailure "Expected SourceIso requirement, got: $($_.Exception.Message)"
        }
    }

    $envName = 'WINMINT_TEST_PASSWORD_' + [Guid]::NewGuid().ToString('n')
    try {
        [Environment]::SetEnvironmentVariable($envName, 'secret-from-env')
        $secret = Resolve-WinMintHeadlessSecret -PasswordEnvVar $envName
        if ($secret.Password -ne 'secret-from-env' -or $secret.UsedDeprecatedPassword) {
            Add-SmokeFailure 'Expected password env var to resolve without deprecated-password warning.'
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable($envName, $null)
    }

    $result = New-WinMintHeadlessResult -Result 'success' -BuildId 'test' -OutputIso 'C:\ISO\out.iso' -Warnings @('warn') -Failures @()
    $json = $result | ConvertTo-Json -Depth 8 -Compress
    $roundTrip = $json | ConvertFrom-Json
    if ($roundTrip.result -ne 'success' -or $roundTrip.buildId -ne 'test') {
        Add-SmokeFailure 'Expected headless JSON result contract to round-trip as a single object.'
    }

}

function Assert-HeadlessSourceAndDriverInputContracts {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('winmint-headless-inputs-' + [Guid]::NewGuid().ToString('n'))
    try {
        $null = New-Item -ItemType Directory -Path $tempRoot -Force

        $officialIso = Get-WinMintTestOfficialIsoFixturePath
        $fixtureComputerName = 'iso-pc'
        $sourceProfile = New-WinMintHeadlessProfileFromFlags `
            -SourceIso $officialIso `
            -Architecture 'arm64' `
            -ComputerName "$fixtureComputerName-pc" `
            -AccountName 'dev' `
            -UpdateImage None `
            -ValidateOnly
        $sourceConfig = New-WinMintBuildConfig -BuildProfile $sourceProfile
        $sourcePreflight = Test-WinMintBuildPrerequisite -Config $sourceConfig -RunMode ValidateOnly
        if (-not $sourcePreflight.Passed) {
            Add-SmokeFailure "Expected official ISO fixture path to pass source preflight, got: $($sourcePreflight.Failures -join '; ')"
        }

        $iso = $officialIso
        $isoProfile = New-WinMintHeadlessProfileFromFlags `
            -SourceIso $iso `
            -Architecture 'arm64' `
            -ComputerName $fixtureComputerName `
            -AccountName 'dev' `
            -UpdateImage None `
            -ValidateOnly
        $isoConfig = New-WinMintBuildConfig -BuildProfile $isoProfile
        $isoPreflight = Test-WinMintBuildPrerequisite -Config $isoConfig -RunMode ValidateOnly
        if (-not $isoPreflight.Passed) {
            Add-SmokeFailure "Expected existing ISO fixture path to pass source preflight, got: $($isoPreflight.Failures -join '; ')"
        }
        if ((Get-WinMintIsoArchitectureHint -Path $iso) -ne 'arm64') {
            Add-SmokeFailure 'Expected ISO filename architecture hint to detect arm64.'
        }

        $profilePath = Join-Path $tempRoot 'profile.json'
        $profile = New-WinMintHeadlessProfileFromFlags -SourceIso '' -Architecture 'amd64' -DryRun
        $null = Save-WinMintBuildProfile -BuildProfile $profile -Path $profilePath
        $imported = Import-WinMintHeadlessBuildProfile -ProfilePath $profilePath -SourceIsoOverride $iso
        if ([string]$imported.source.isoPath -ne $iso) {
            Add-SmokeFailure 'Expected -SourceIsoOverride to replace the source ISO in imported profile builds.'
        }

        $drivers = Join-Path $tempRoot 'drivers'
        $nested = Join-Path $drivers 'surface'
        $null = New-Item -ItemType Directory -Path $nested -Force
        $inf = Join-Path $nested 'surface.inf'
        $msi = Join-Path $tempRoot 'SurfaceDriverPack.msi'
        $zipSource = Join-Path $tempRoot 'zip-src'
        $zip = Join-Path $tempRoot 'SurfaceDriverPack.zip'
        $bad = Join-Path $tempRoot 'drivers.txt'
        Set-Content -LiteralPath $inf -Value "[Version]`nClass=System" -Encoding ASCII
        Set-Content -LiteralPath $msi -Value 'driver msi fixture path only' -Encoding ASCII
        Set-Content -LiteralPath $bad -Value 'not a driver payload' -Encoding ASCII
        $null = New-Item -ItemType Directory -Path $zipSource -Force
        Set-Content -LiteralPath (Join-Path $zipSource 'surface.inf') -Value "[Version]`nClass=System" -Encoding ASCII
        Compress-Archive -Path (Join-Path $zipSource '*') -DestinationPath $zip -Force

        foreach ($validDriverPath in @($inf, $msi, $zip, $drivers)) {
            if (-not (Test-Win11IsoDriverPath -Path $validDriverPath)) {
                Add-SmokeFailure "Expected driver path to validate: $validDriverPath"
            }
            $driverProfile = New-WinMintHeadlessProfileFromFlags `
                -SourceIso '' `
                -Architecture 'amd64' `
                -DriverSource Custom `
                -DriverPath $validDriverPath `
                -DryRun
            $driverConfig = New-WinMintBuildConfig -BuildProfile $driverProfile
            $driverPreflight = Test-WinMintBuildPrerequisite -Config $driverConfig -RunMode DryRun
            if (-not $driverPreflight.Passed) {
                Add-SmokeFailure "Expected custom driver fixture to pass preflight: $validDriverPath; failures: $($driverPreflight.Failures -join '; ')"
            }
        }
        if (Test-Win11IsoDriverPath -Path $bad) {
            Add-SmokeFailure 'Expected non-driver file to be rejected by driver path validation.'
        }
        try {
            $null = Resolve-WinMintHeadlessDriverIntent -DriverPack $bad
            Add-SmokeFailure 'Expected -DriverPack to reject non-MSI/ZIP paths.'
        }
        catch {
            if ($_.Exception.Message -notmatch 'DriverPack must') {
                Add-SmokeFailure "Expected DriverPack extension validation error, got: $($_.Exception.Message)"
            }
        }

        $hostDriverProfile = New-WinMintHeadlessProfileFromFlags `
            -SourceIso '' `
            -Architecture (Get-BuildHostProcessorArchitecture) `
            -TargetDevice ThisPC `
            -DryRun
        $hostDriverConfig = New-WinMintBuildConfig -BuildProfile $hostDriverProfile
        $hostDriverPreflight = Test-WinMintBuildPrerequisite -Config $hostDriverConfig -RunMode DryRun
        if (
            (Get-Command Export-WindowsDriver -ErrorAction SilentlyContinue) -or
            (Get-Command pnputil.exe -CommandType Application -ErrorAction SilentlyContinue)
        ) {
            if (-not $hostDriverPreflight.Passed) {
                Add-SmokeFailure "Expected host driver dry-run preflight to pass when host driver export tooling is available, got: $($hostDriverPreflight.Failures -join '; ')"
            }
        }
        else {
        if ($hostDriverPreflight.Passed -or ($hostDriverPreflight.Failures -join '; ') -notmatch 'Export-WindowsDriver|pnputil') {
                Add-SmokeFailure 'Expected host driver dry-run preflight to fail when host driver export tooling is unavailable.'
            }
        }
        $preparedIso = Join-Path $tempRoot '26100.1.240331-1435.ge_release_CLIENT_ARM64FRE_en-us.iso'
        Set-Content -LiteralPath $preparedIso -Value 'already converted iso fixture path only' -Encoding ASCII
        $resolvedIsoPrep = Invoke-WinMintHeadlessSourcePrep -Path $preparedIso
        if ($resolvedIsoPrep.SourceKind -ne 'Iso' -or $resolvedIsoPrep.GeneratedIso -ne $preparedIso -or -not $resolvedIsoPrep.Reused -or $resolvedIsoPrep.RanConversion) {
            Add-SmokeFailure 'Expected source resolver to treat final ISO input as reusable source ISO.'
        }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Assert-UiBridgeBuildProfileContract {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('winmint-ui-bridge-' + [Guid]::NewGuid().ToString('n'))
    $null = New-Item -ItemType Directory -Path $tempRoot -Force
    try {
        $settingsPath = Join-Path $tempRoot 'ui-intent.json'
        $profilePath = Join-Path $tempRoot 'BuildProfile.json'
        $settings = [ordered]@{
            Profile = 'WinMint'
            KeepEdge = $false
            KeepGaming = $false
            KeepCopilot = $false
            ISOPath = ''
            Architecture = 'amd64'
            ComputerName = 'WinMint'
            AccountName = 'dev'
            AccountMode = 'Local'
            TargetDevice = 'DifferentPC'
            FormFactor = 'Auto'
            Edition = 'Pro'
            DriverSource = 'None'
            DriverPath = ''
            InstallWindhawk = $true
            InstallYasb = $false
            InstallKomorebi = $true
            InstallNilesoft = $true
            Editors = @('zed')
            Browsers = @('brave', 'edge')
            Wsl2Distros = @('Ubuntu', 'NixOS-WSL')
            PrivLocation = $false
            TweakHardwareBypass = $false
            TweakDmaInterop = $true
        }
        $settings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $settingsPath -Encoding UTF8

        & pwsh.exe -NoProfile -File (Join-Path $script:WinMintRepositoryRoot 'tools\ui-bridge\New-UiBuildProfile.ps1') `
            -RepositoryRoot $script:WinMintRepositoryRoot `
            -SettingsPath $settingsPath `
            -OutputPath $profilePath
        if ($LASTEXITCODE -ne 0) {
            Add-SmokeFailure "Expected UI bridge profile generation to exit 0, got $LASTEXITCODE."
            return
        }
        if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
            Add-SmokeFailure 'Expected UI bridge to write BuildProfile.json.'
            return
        }

        $profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
        $result = Test-WinMintBuildProfile -BuildProfile $profile
        if ($result.Failures.Count -gt 0) {
            Add-SmokeFailure "Expected UI bridge output to validate, got: $($result.Failures -join '; ')"
        }
        $config = New-WinMintBuildConfig -BuildProfile $profile
        # Subtractive keep-flag model: the bridge carries the explicit editor, WSL,
        # and shell-layer intent straight through to the build config.
        if ($config.Editors -notcontains 'zed' -or $config.Browsers -notcontains 'brave' -or $config.Wsl2Distros -notcontains 'Ubuntu' -or $config.Wsl2Distros -notcontains 'NixOS-WSL') {
            Add-SmokeFailure 'Expected UI bridge to preserve editor, browser, and WSL intent.'
        }
        if (-not $config.InstallWindhawk -or $config.InstallYasb -or -not $config.InstallKomorebi -or -not $config.InstallNilesoft) {
            Add-SmokeFailure 'Expected UI bridge to preserve selected shell layers.'
        }

        $badSettingsPath = Join-Path $tempRoot 'bad-ui-intent.json'
        [ordered]@{
            Profile = 'WinMint'
            Architecture = 'amd64'
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $badSettingsPath -Encoding UTF8
        try {
            & pwsh.exe -NoProfile -File (Join-Path $script:WinMintRepositoryRoot 'tools\ui-bridge\New-UiBuildProfile.ps1') `
                -RepositoryRoot $script:WinMintRepositoryRoot `
                -SettingsPath $badSettingsPath `
                -OutputPath (Join-Path $tempRoot 'bad-profile.json') 2>$null
            if ($LASTEXITCODE -eq 0) {
                Add-SmokeFailure 'Expected UI bridge to reject intent missing required keep-flag fields.'
            }
        }
        catch {
            if ($_.Exception.Message -notmatch 'missing required field') {
                Add-SmokeFailure "Expected UI bridge validation error, got: $($_.Exception.Message)"
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

