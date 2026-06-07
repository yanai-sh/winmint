#Requires -Version 7.3

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
    foreach ($expected in @('filesystem-performance-policy', 'developer-telemetry-optout', 'telemetry-tracing-policy', 'terminal-admin-context')) {
        if (@($defaultConfig.RegistryTweaks) -notcontains $expected) {
            Add-SmokeFailure "Default Developer build should select registry tweak '$expected'."
        }
    }
    $defaultProfile = New-WinMintSetupProfile -BuildConfig $defaultConfig
    if ([string]$defaultProfile.power.formFactor -ne 'Auto') {
        Add-SmokeFailure 'Setup profile power.formFactor should default to Auto.'
    }
    if ([string]$defaultProfile.power.desktopPowerPlan -ne 'HighPerformance') {
        Add-SmokeFailure 'Setup profile power.desktopPowerPlan should be HighPerformance.'
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
    $packagesPath = Join-Path $root 'src\engine\Private\Image\Packages.ps1'
    $stagingPath = Join-Path $root 'src\engine\Private\Image\Staging.ps1'
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
        $script:WinMintBuildManifest = $null
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
        foreach ($path in @($manifestPath, $auditPath, $mdPath, $regPath)) {
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
        $audit = Get-Content -LiteralPath $auditPath -Raw | ConvertFrom-Json
        if ([int]$audit.summary.applied -lt 1 -or [int]$audit.summary.failed -lt 1) {
            Add-SmokeFailure 'Expected tweak audit JSON to summarize applied and failed events.'
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
        $script:WinMintBuildManifest = $null
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
        $templateResult = Invoke-WinMintHeadlessCli `
            -BoundParameters @{ NewProfile = $templatePath } `
            -NewProfile $templatePath `
            -Quiet
        if ($templateResult.result -ne 'profile-created' -or -not (Test-Path -LiteralPath $templatePath)) {
            Add-SmokeFailure 'Expected -NewProfile to create an editable profile without requiring build inputs.'
        }
        $template = Get-Content -LiteralPath $templatePath -Raw | ConvertFrom-Json
        $templateValidation = Test-WinMintBuildProfile -BuildProfile $template
        if (-not $templateValidation.Passed) {
            Add-SmokeFailure "Expected -NewProfile output to validate, got: $($templateValidation.Failures -join '; ')"
        }
        # Subtractive model: the default template removes everything; developer
        # tooling is now baseline (no Developer group), and the derived label is
        # Minimal-only with no preselected editors or WSL distros.
        if ((@($template.profileGroups) -join ',') -ne 'Minimal' -or @($template.development.editors).Count -ne 0 -or @($template.development.wsl.distros).Count -ne 0) {
            Add-SmokeFailure 'Expected default template to derive the Minimal group without preselecting editors or WSL distros.'
        }
        if ([int]$template.schemaVersion -ne 2) {
            Add-SmokeFailure 'Expected generated profile templates to use schemaVersion 2.'
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

        $outResult = Invoke-WinMintHeadlessCli `
            -BoundParameters @{ OutProfile = $outProfilePath; Gaming = $true; Architecture = 'amd64' } `
            -OutProfile $outProfilePath `
            -Gaming `
            -Architecture amd64 `
            -Quiet
        if ($outResult.result -ne 'profile-created' -or -not (Test-Path -LiteralPath $outProfilePath)) {
            Add-SmokeFailure 'Expected -OutProfile to save flag-authored intent without building.'
        }
        $outProfile = Get-Content -LiteralPath $outProfilePath -Raw | ConvertFrom-Json
        # Subtractive model: -Gaming maps to -KeepGaming, deriving the Gaming label.
        # Template mode leaves shell layers unselected, so DesktopUI is not derived.
        foreach ($expectedGroup in @('Minimal', 'Gaming')) {
            if (@($outProfile.profileGroups) -notcontains $expectedGroup) {
                Add-SmokeFailure "Expected -Gaming/-KeepGaming to derive profile group '$expectedGroup'."
            }
        }
        if (-not [bool]$outProfile.keep.gaming) {
            Add-SmokeFailure 'Expected -Gaming to set the keep.gaming flag in the saved profile.'
        }
        if ((@($outProfile.desktop.layers) -join ',') -ne 'standard') {
            Add-SmokeFailure 'Expected profile templates to avoid preselecting shell layers unless explicit layer flags are supplied.'
        }
    }
    finally {
        Remove-Item -LiteralPath $templatePath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $outProfilePath -Force -ErrorAction SilentlyContinue
    }

    try {
        Assert-WinMintHeadlessParameterSet -BoundParameters @{
            ProfilePath = 'config\build-profiles\yanai-sl7-microsoft-oobe.json'
            ComputerName = 'Other'
        }
        Add-SmokeFailure 'Expected headless parameter validation to reject mixed ProfilePath identity flags.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'source of truth') {
            Add-SmokeFailure "Expected ProfilePath source-of-truth error, got: $($_.Exception.Message)"
        }
    }

    try {
        Assert-WinMintHeadlessParameterSet -BoundParameters @{
            SourceIsoOverride = 'C:\ISO\override.iso'
            SourceIso = 'C:\ISO\base.iso'
        }
        Add-SmokeFailure 'Expected SourceIsoOverride to require ProfilePath.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'SourceIsoOverride') {
            Add-SmokeFailure "Expected SourceIsoOverride validation error, got: $($_.Exception.Message)"
        }
    }

    try {
        Assert-WinMintHeadlessParameterSet -BoundParameters @{
            ProfilePath = 'config\build-profiles\surface-uup.json'
            UupDumpSource = 'C:\UUP\source.zip'
            Yes = $true
        }
    }
    catch {
        Add-SmokeFailure "Expected ProfilePath + UupDumpSource to be valid for profile-backed UUP source prep, got: $($_.Exception.Message)"
    }

    try {
        Assert-WinMintHeadlessParameterSet -BoundParameters @{
            NewProfile = 'C:\Profiles\BuildProfile.json'
            UupDumpSource = 'C:\UUP\source.zip'
        }
        Add-SmokeFailure 'Expected profile authoring with unresolved UUP source to be rejected.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'resolved source ISO') {
            Add-SmokeFailure "Expected profile authoring UUP source validation error, got: $($_.Exception.Message)"
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
    # Subtractive model: setupOption is always the Minimal derived label; the
    # default build already removes the Copilot+ AI surface.
    if ($config.SetupOption -ne 'Minimal' -or $config.AccountMode -ne 'MicrosoftOobe') {
        Add-SmokeFailure 'Expected flag-built headless profile to derive Minimal setupOption and preserve MicrosoftOobe intent.'
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
        -NoDmaInterop `
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
        -DmaInterop `
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
    $manifestDma = $script:WinMintBuildManifest.regional.dmaInterop
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
    if ((@($minimalProfile.profileGroups) -join ',') -ne 'Minimal') {
        Add-SmokeFailure 'Expected omitted headless group flags to default to the Minimal group only.'
    }
    # Subtractive model: developer QoL (OpenSSH client, Developer Mode) is now
    # baseline on every build; WSL stays opt-in until a distro is selected.
    if ($minimalConfig.Features -notcontains 'OpenSSH.Client' -or
        $minimalConfig.RegistryTweaks -notcontains 'developer-mode') {
        Add-SmokeFailure 'Expected default build to include baseline developer QoL (OpenSSH client, Developer Mode).'
    }
    if ($minimalConfig.Features -contains 'Microsoft-Windows-Subsystem-Linux') {
        Add-SmokeFailure 'Expected WSL features to stay disabled until a distro is selected.'
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

    $locationOnProfile = New-WinMintHeadlessProfileFromFlags -SourceIso '' -Architecture 'arm64' -LocationServices -DryRun
    $locationOnConfig = New-WinMintBuildConfig -BuildProfile $locationOnProfile
    if (-not [bool]$locationOnConfig.Privacy.Location) {
        Add-SmokeFailure 'Expected -LocationServices to keep location services enabled through the privacy policy profile.'
    }
    $locationOffProfile = New-WinMintHeadlessProfileFromFlags -SourceIso '' -Architecture 'arm64' -NoLocationServices -DryRun
    $locationOffConfig = New-WinMintBuildConfig -BuildProfile $locationOffProfile
    if ([bool]$locationOffConfig.Privacy.Location -or @($locationOffConfig.RegistryTweaks) -notcontains 'location-disabled-policy') {
        Add-SmokeFailure 'Expected -NoLocationServices to disable location services and select the location block policy.'
    }
    $dmaLocationProfile = New-WinMintHeadlessProfileFromFlags -SourceIso '' -Architecture 'arm64' -DmaInterop -LocationServices -DryRun
    $dmaLocationConfig = New-WinMintBuildConfig -BuildProfile $dmaLocationProfile
    $dmaLocationSetupProfile = New-WinMintSetupProfile -BuildConfig $dmaLocationConfig
    if (-not [bool]$dmaLocationConfig.Privacy.Location -or -not [bool]$dmaLocationSetupProfile.regional.dmaInterop.restoreLocationServices) {
        Add-SmokeFailure 'Expected location services to remain enable-able while DMA interoperability is enabled.'
    }

    try {
        Assert-WinMintHeadlessParameterSet -BoundParameters @{ LocationServices = $true; NoLocationServices = $true }
        Add-SmokeFailure 'Expected LocationServices and NoLocationServices to be mutually exclusive.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'LocationServices|NoLocationServices') {
            Add-SmokeFailure "Expected location switch validation error, got: $($_.Exception.Message)"
        }
    }

    try {
        Assert-WinMintHeadlessParameterSet -BoundParameters @{ DmaInterop = $true; NoDmaInterop = $true }
        Add-SmokeFailure 'Expected DmaInterop and NoDmaInterop to be mutually exclusive.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'DmaInterop|NoDmaInterop') {
            Add-SmokeFailure "Expected DMA switch validation error, got: $($_.Exception.Message)"
        }
    }

    # Subtractive model: -Developer/-Copilot are legacy no-ops (developer QoL is
    # baseline; full Copilot+ AI removal is the default). -Gaming maps to
    # -KeepGaming (preserve Xbox), -DesktopUI selects the shell stack. The derived
    # labels are therefore Minimal + Gaming + DesktopUI only.
    $groupProfile = New-WinMintHeadlessProfileFromFlags `
        -SourceIso '' `
        -Architecture 'arm64' `
        -Developer `
        -Copilot `
        -Gaming `
        -DesktopUI `
        -DryRun
    $groupConfig = New-WinMintBuildConfig -BuildProfile $groupProfile
    foreach ($expectedGroup in @('Minimal', 'Gaming', 'DesktopUI')) {
        if (@($groupProfile.profileGroups) -notcontains $expectedGroup) {
            Add-SmokeFailure "Expected combined headless flags to derive profile group '$expectedGroup'."
        }
    }
    if (@($groupProfile.profileGroups) -contains 'Developer' -or @($groupProfile.profileGroups) -contains 'CopilotPlus') {
        Add-SmokeFailure 'Expected legacy -Developer/-Copilot flags to be no-ops that derive no extra profile group.'
    }
    if ($groupConfig.Features -notcontains 'OpenSSH.Client' -or
        $groupConfig.RegistryTweaks -notcontains 'developer-mode' -or
        $groupConfig.RegistryTweaks -notcontains 'powershell-remotesigned') {
        Add-SmokeFailure 'Expected baseline build to enable OpenSSH, Developer Mode, and RemoteSigned.'
    }
    if (@($groupConfig.Editors).Count -ne 0 -or @($groupConfig.Wsl2Distros).Count -ne 0) {
        Add-SmokeFailure 'Expected baseline build to leave editors and WSL distros unselected by default.'
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
    if ($groupConfig.Launcher -ne 'None' -or $groupConfig.InstallFlowEverything -or $groupConfig.InstallRaycast) {
        Add-SmokeFailure 'Expected launcher modules to stay opt-in even when Developer/DesktopUI groups are selected.'
    }

    $flowProfile = New-WinMintHeadlessProfileFromFlags `
        -SourceIso '' `
        -Architecture 'arm64' `
        -Developer `
        -Launcher FlowEverything `
        -DryRun
    $flowConfig = New-WinMintBuildConfig -BuildProfile $flowProfile
    $flowAgentProfile = New-WinMintAgentProfile -BuildConfig $flowConfig
    if ($flowConfig.Launcher -ne 'FlowEverything' -or -not $flowConfig.InstallFlowEverything -or -not $flowAgentProfile.modules.flowEverything.enabled -or $flowAgentProfile.modules.raycast.enabled) {
        Add-SmokeFailure 'Expected -Launcher FlowEverything to enable only Flow Launcher and Everything in the FirstLogon agent profile.'
    }
    if (-not $flowAgentProfile.modules.packageManagers.enabled) {
        Add-SmokeFailure 'Expected -Launcher FlowEverything to enable package managers for first-logon installation.'
    }

    $raycastProfile = New-WinMintHeadlessProfileFromFlags `
        -SourceIso '' `
        -Architecture 'arm64' `
        -Developer `
        -Launcher Raycast `
        -DryRun
    $raycastConfig = New-WinMintBuildConfig -BuildProfile $raycastProfile
    $raycastAgentProfile = New-WinMintAgentProfile -BuildConfig $raycastConfig
    if ($raycastConfig.Launcher -ne 'Raycast' -or -not $raycastConfig.InstallRaycast -or -not $raycastAgentProfile.modules.raycast.enabled -or $raycastAgentProfile.modules.flowEverything.enabled) {
        Add-SmokeFailure 'Expected -Launcher Raycast to enable only Raycast in the FirstLogon agent profile.'
    }
    if (-not $raycastAgentProfile.modules.packageManagers.enabled) {
        Add-SmokeFailure 'Expected -Launcher Raycast to enable package managers for first-logon installation.'
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

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('winmint-uup-zip-test-' + [Guid]::NewGuid().ToString('n'))
    try {
        $src = Join-Path $tempRoot 'src'
        $files = Join-Path $src 'files'
        $zip = Join-Path $tempRoot 'uup.zip'
        $badZip = Join-Path $tempRoot 'bad.zip'
        $null = New-Item -ItemType Directory -Path $files -Force
        Set-Content -LiteralPath (Join-Path $src 'uup_download_windows.cmd') -Value '@echo off' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $src 'ConvertConfig.ini') -Value "[convert-UUP]`nAddUpdates=0`nCleanup=0`nwim2esd=1`nSkipISO=1" -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $files 'get_aria2.ps1') -Value '' -Encoding ASCII
        Compress-Archive -Path (Join-Path $src '*') -DestinationPath $zip -Force
        Set-Content -LiteralPath (Join-Path $tempRoot 'bad.txt') -Value 'bad' -Encoding ASCII
        Compress-Archive -Path (Join-Path $tempRoot 'bad.txt') -DestinationPath $badZip -Force
        if (-not (Test-WinMintUupDumpZip -Path $zip)) {
            Add-SmokeFailure 'Expected fake UUP Dump conversion zip to validate.'
        }
        if (Test-WinMintUupDumpZip -Path $badZip) {
            Add-SmokeFailure 'Expected invalid UUP zip to be rejected.'
        }
        Assert-WinMintHeadlessParameterSet -BoundParameters @{ UupDumpSource = $zip; SourceIso = 'C:\ISO\win.iso' }
        Add-SmokeFailure 'Expected SourceIso + UupDumpSource to be rejected.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'SourceIso|UupDumpSource') {
            Add-SmokeFailure "Unexpected UUP zip validation error: $($_.Exception.Message)"
        }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Assert-HeadlessSourceAndDriverInputContracts {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('winmint-headless-inputs-' + [Guid]::NewGuid().ToString('n'))
    try {
        $null = New-Item -ItemType Directory -Path $tempRoot -Force

        $uupZip = Get-WinMintTestUupDumpZipFixturePath
        if (-not (Test-WinMintUupDumpZip -Path $uupZip)) {
            Add-SmokeFailure "Expected UUP Dump fixture zip to validate before source prep: $uupZip"
        }
        else {
            $mockPreparedIso = Get-WinMintTestUupDumpPreparedIsoFixturePath
            $uupPrepArgs = @{
                UupDumpZip = $uupZip
                ValidateOnly = $true
            }
            if (-not [string]::IsNullOrWhiteSpace($mockPreparedIso)) {
                $uupPrepArgs.MockPreparedIso = $mockPreparedIso
            }
            $uupPrep = Invoke-WinMintUupDumpSourcePrep @uupPrepArgs
            if ($uupPrep.SourceKind -ne 'UupDumpZip' -or $uupPrep.RanConversion) {
                Add-SmokeFailure 'Expected UUP validate-only prep to fingerprint the fixture zip without converting.'
            }
            $resolvedZipPrep = Invoke-WinMintHeadlessSourcePrep -Path $uupZip -ValidateOnly
            if ($resolvedZipPrep.SourceKind -ne 'UupDumpZip' -or $resolvedZipPrep.RanConversion) {
                Add-SmokeFailure 'Expected preferred UUP source resolver to accept UUP Dump zip input without converting in validate-only mode.'
            }
            if (-not [string]::IsNullOrWhiteSpace($mockPreparedIso) -and -not [bool]$uupPrep.Mocked) {
                Add-SmokeFailure 'Expected prepared UUP fixture output to activate mocked source prep.'
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$uupPrep.GeneratedIso) -and -not $uupPrep.Reused) {
                Add-SmokeFailure 'Expected validate-only UUP prep to report a generated ISO only when reusing a prepared fixture artifact.'
            }
        }

        $officialIso = Get-WinMintTestOfficialIsoFixturePath
        $uupIso = Get-WinMintTestUupDumpIsoFixturePath
        $fixtureComputerName = 'iso-pc'
        foreach ($sourceCase in @(
                @{ Name = 'official-base'; Path = $officialIso },
                @{ Name = 'uupdump-generated'; Path = $uupIso }
            )) {
            $sourceProfile = New-WinMintHeadlessProfileFromFlags `
                -SourceIso $sourceCase.Path `
                -Architecture 'arm64' `
                -ComputerName "$($sourceCase.Name)-pc" `
                -AccountName 'dev' `
                -ValidateOnly
            $sourceConfig = New-WinMintBuildConfig -BuildProfile $sourceProfile
            $sourcePreflight = Test-WinMintBuildPrerequisite -Config $sourceConfig -AllowMissingSourceIso
            if (-not $sourcePreflight.Passed) {
                Add-SmokeFailure "Expected $($sourceCase.Name) ISO fixture path to pass source preflight, got: $($sourcePreflight.Failures -join '; ')"
            }
        }

        $iso = $officialIso
        $isoProfile = New-WinMintHeadlessProfileFromFlags `
            -SourceIso $iso `
            -Architecture 'arm64' `
            -ComputerName $fixtureComputerName `
            -AccountName 'dev' `
            -ValidateOnly
        $isoConfig = New-WinMintBuildConfig -BuildProfile $isoProfile
        $isoPreflight = Test-WinMintBuildPrerequisite -Config $isoConfig -AllowMissingSourceIso
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
            $driverPreflight = Test-WinMintBuildPrerequisite -Config $driverConfig -AllowMissingSourceIso
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
        $hostDriverPreflight = Test-WinMintBuildPrerequisite -Config $hostDriverConfig -AllowMissingSourceIso
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

        $ini = Join-Path $tempRoot 'ConvertConfig.ini'
        Set-Content -LiteralPath $ini -Value "[convert-UUP]`nAddUpdates=0`nCleanup=0`nwim2esd=1`nSkipISO=1" -Encoding ASCII
        Set-WinMintUupConvertConfigPolicy -Path $ini
        $iniText = Get-Content -LiteralPath $ini -Raw
        foreach ($expected in @('AutoStart=1', 'AddUpdates=1', 'Cleanup=1', 'wim2esd=0', 'SkipISO=0', 'AutoExit=1')) {
            if ($iniText -notmatch "(?m)^$([regex]::Escape($expected))\r?$") {
                Add-SmokeFailure "Expected UUP conversion policy to enforce '$expected'."
            }
        }

        $preparedUup = Join-Path $tempRoot 'prepared-uup'
        $null = New-Item -ItemType Directory -Path $preparedUup -Force
        try {
            $null = Invoke-WinMintHeadlessSourcePrep -Path $preparedUup
            Add-SmokeFailure 'Expected preferred UUP source resolver to reject prepared UUP Dump folder input.'
        }
        catch {
            if ($_.Exception.Message -notmatch 'pass that ISO with -SourceIso') {
                Add-SmokeFailure "Expected prepared UUP folder rejection to direct users to -SourceIso, got: $($_.Exception.Message)"
            }
        }
        $preparedIso = Join-Path $tempRoot '26100.1.240331-1435.ge_release_CLIENT_ARM64FRE_en-us.iso'
        Set-Content -LiteralPath $preparedIso -Value 'already converted iso fixture path only' -Encoding ASCII
        $resolvedIsoPrep = Invoke-WinMintHeadlessSourcePrep -Path $preparedIso
        if ($resolvedIsoPrep.SourceKind -ne 'Iso' -or $resolvedIsoPrep.GeneratedIso -ne $preparedIso -or -not $resolvedIsoPrep.Reused -or $resolvedIsoPrep.RanConversion) {
            Add-SmokeFailure 'Expected preferred UUP source resolver to treat final ISO input as reusable source ISO.'
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
            Profile = 'Minimal'
            ProfileGroups = @('Minimal', 'Developer', 'DesktopUI')
            SetupOption = 'Minimal'
            ISOPath = ''
            Architecture = 'amd64'
            ComputerName = 'WinMint'
            AccountName = 'dev'
            AccountMode = 'Local'
            TargetDevice = 'DifferentPC'
            EditionMode = 'TargetLicense'
            Edition = ''
            DriverSource = 'None'
            DriverPath = ''
            DesktopUiDefault = $false
            InstallWindhawk = $true
            InstallYasb = $false
            InstallKomorebi = $true
            Editors = @('zed')
            Wsl2Distros = @('Ubuntu')
            RemoveGaming = $true
            PrivLocation = $false
            TweakHardwareBypass = $false
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
        # Subtractive model: the DesktopUI label is derived from the selected shell
        # layers; Developer is no longer a derived group (dev tooling is baseline).
        if ($config.ProfileGroups -notcontains 'DesktopUI' -or $config.ProfileGroups -contains 'Developer') {
            Add-SmokeFailure 'Expected UI bridge to derive the DesktopUI group from shell layers without a Developer group.'
        }
        if ($config.Editors -notcontains 'zed' -or $config.Wsl2Distros -notcontains 'Ubuntu') {
            Add-SmokeFailure 'Expected UI bridge to preserve editor and WSL intent.'
        }
        if (-not $config.InstallWindhawk -or $config.InstallYasb -or -not $config.InstallKomorebi) {
            Add-SmokeFailure 'Expected UI bridge to preserve selected DesktopUI shell layers.'
        }

        $badSettingsPath = Join-Path $tempRoot 'bad-ui-intent.json'
        [ordered]@{
            Profile = 'Minimal'
            ProfileGroups = @('Developer')
            Architecture = 'amd64'
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $badSettingsPath -Encoding UTF8
        try {
            & pwsh.exe -NoProfile -File (Join-Path $script:WinMintRepositoryRoot 'tools\ui-bridge\New-UiBuildProfile.ps1') `
                -RepositoryRoot $script:WinMintRepositoryRoot `
                -SettingsPath $badSettingsPath `
                -OutputPath (Join-Path $tempRoot 'bad-profile.json') 2>$null
            if ($LASTEXITCODE -eq 0) {
                Add-SmokeFailure 'Expected UI bridge to reject incomplete or non-Minimal profile group intent.'
            }
        }
        catch {
            if ($_.Exception.Message -notmatch 'missing required field|Minimal') {
                Add-SmokeFailure "Expected UI bridge validation error, got: $($_.Exception.Message)"
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
