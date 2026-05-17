#Requires -Version 7.3

function New-SmokeBuildProfile {
    New-WinWSBuildProfile -Settings @{
        Profile = 'Developer'
        ProfileGroups = @('Minimal', 'Developer')
        ISOPath = (Get-WinWSTestIsoFixturePath)
        Architecture = 'arm64'
        ComputerName = 'WinWS'
        AccountName = 'dev'
        Editors = @('cursor')
        DriverSource = 'None'
        DriverPath = ''
    }
}

function New-SmokeBuildProfileSettings {
    @{
        Profile = 'Developer'
        ProfileGroups = @('Minimal', 'Developer')
        ISOPath = (Get-WinWSTestIsoFixturePath)
        Architecture = 'arm64'
        ComputerName = 'WinWS'
        AccountName = 'dev'
        DriverSource = 'None'
        DriverPath = ''
    }
}

function Assert-ProfileFailsWith {
    param(
        [Parameter(Mandatory)][object]$Profile,
        [Parameter(Mandatory)][string]$Expected
    )

    $result = Test-WinWSBuildProfile -BuildProfile $Profile
    if ($result.Passed) {
        Add-SmokeFailure "Expected profile validation to fail: $Expected"
        return
    }
    if (($result.Failures -join "`n") -notmatch [regex]::Escape($Expected)) {
        Add-SmokeFailure "Expected validation failure '$Expected', got: $($result.Failures -join '; ')"
    }
}

function Assert-PayloadCopyPreservesRootAndFolders {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath().TrimEnd('\', '/')) ('winws_payload_copy_test_' + [Guid]::NewGuid().ToString('n'))
    $source = Join-Path $tempRoot 'source'
    $dest = Join-Path $tempRoot 'dest'
    try {
        $null = New-Item -ItemType Directory -Path (Join-Path $source 'cs') -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $source 'Modules\TestModule') -Force
        Set-Content -LiteralPath (Join-Path $source 'pwsh.exe') -Value 'exe' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $source 'root.dll') -Value 'root' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $source 'cs\resource.dll') -Value 'resource' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $source 'Modules\TestModule\Test.psm1') -Value 'module' -Encoding ASCII

        Copy-WinWSPayloadDirectoryChildren -SourceDir $source -DestinationDir $dest

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
        MountPath = 'C:\Temp\WinWS_ISO_active\mount'
        Path = 'C:\Temp\WinWS_ISO_active\mount'
        MountStatus = 'Ok'
    }
    $invalid = [pscustomobject]@{
        MountPath = 'C:\Temp\WinWS_ISO_invalid\mount'
        Path = 'C:\Temp\WinWS_ISO_invalid\mount'
        MountStatus = 'Invalid'
    }
    if (-not (Test-WinWSMountedImagePath -Path 'C:\Temp\WinWS_ISO_active\mount' -MountedImages @($active, $invalid))) {
        Add-SmokeFailure 'Expected mounted-image helper to recognize an active mount record.'
    }
    if (Test-WinWSMountedImagePath -Path 'C:\Temp\WinWS_ISO_invalid\mount' -MountedImages @($active, $invalid)) {
        Add-SmokeFailure 'Expected mounted-image helper to ignore invalid mount records.'
    }
    if (Test-WinWSMountedImagePath -Path 'C:\Temp\WinWS_ISO_absent\mount' -MountedImages @($active, $invalid)) {
        Add-SmokeFailure 'Expected mounted-image helper to ignore absent mount records.'
    }
}

function Assert-OscdimgSelectionPrefersNativeHostArchitecture {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath().TrimEnd('\', '/')) ('winws_oscdimg_selection_test_' + [Guid]::NewGuid().ToString('n'))
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

function Assert-BuildResultContractAcceptsPipelineOutput {
    $expected = 'C:\ISO\out.iso'
    $clean = [pscustomobject]@{ OutputIsoPath = $expected; WorkDir = 'C:\Temp\WinWS'; DryRun = $false }
    $polluted = @(
        'cleanup log line'
        [pscustomobject]@{ Unrelated = $true }
        $clean
    )

    if ((Get-WinWSBuildOutputPathFromPipelineResult -PipelineResult $clean -FallbackPath 'C:\Fallback') -ne $expected) {
        Add-SmokeFailure 'Expected build output helper to read OutputIsoPath from a clean pipeline result.'
    }
    if ((Get-WinWSBuildOutputPathFromPipelineResult -PipelineResult $polluted -FallbackPath 'C:\Fallback') -ne $expected) {
        Add-SmokeFailure 'Expected build output helper to read OutputIsoPath from mixed pipeline output.'
    }
    if ((Get-WinWSBuildOutputPathFromPipelineResult -PipelineResult @('noise') -FallbackPath 'C:\Fallback') -ne 'C:\Fallback') {
        Add-SmokeFailure 'Expected build output helper to return fallback when no OutputIsoPath exists.'
    }
    try {
        $emptyFallback = Get-WinWSBuildOutputPathFromPipelineResult -PipelineResult @('noise') -FallbackPath ''
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
    $result = Start-WinWSBuild -BuildProfile $profile -DryRun -ProgressHandler {
        param($ProgressEvent)
        [void]$ProgressEvent
    }
    $items = @($result)
    if ($items.Count -ne 1) {
        Add-SmokeFailure "Expected Start-WinWSBuild to emit one result object, got $($items.Count)."
        return
    }
    if (-not $items[0].PSObject.Properties['Paths']) {
        Add-SmokeFailure 'Expected Start-WinWSBuild result to expose Paths for UI report logging.'
    }
    if (-not $items[0].PSObject.Properties['OutputPath']) {
        Add-SmokeFailure 'Expected Start-WinWSBuild result to expose OutputPath for UI completion.'
    }
}

function Assert-ManifestPayloadsAreDeduplicated {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath().TrimEnd('\', '/')) ('winws_manifest_dedupe_test_' + [Guid]::NewGuid().ToString('n'))
    try {
        $null = New-Item -ItemType Directory -Path $tempRoot -Force
        $config = New-WinWSBuildConfig -BuildProfile (New-SmokeBuildProfile)
        Initialize-WinWSBuildManifest -Config $config
        Add-WinWSManifestPayload -Name 'PowerShell 7' -SourceUrl 'https://example.invalid/pwsh.zip' -Version 'v1' -Sha256 'abc' -SizeBytes 123
        Add-WinWSManifestPayload -Name 'PowerShell 7' -SourceUrl 'https://example.invalid/pwsh.zip' -Version 'v1' -Sha256 'abc' -SizeBytes 123
        $manifestPath = Save-WinWSBuildManifest -OutputDir $tempRoot
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if (@($manifest.payloads).Count -ne 1) {
            Add-SmokeFailure 'Expected manifest payload list to deduplicate repeated payload entries.'
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        $script:WinWSBuildManifest = $null
    }
}

function Assert-TweakAuditArtifactsAreWritten {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath().TrimEnd('\', '/')) ('winws_tweak_audit_test_' + [Guid]::NewGuid().ToString('n'))
    try {
        $null = New-Item -ItemType Directory -Path $tempRoot -Force
        $config = New-WinWSBuildConfig -BuildProfile (New-SmokeBuildProfile)
        Initialize-WinWSBuildManifest -Config $config

        $applied = $script:RegistryTweaks | Where-Object id -eq 'developer-qol' | Select-Object -First 1
        $skipped = $script:RegistryTweaks | Where-Object id -eq 'hardware-bypass' | Select-Object -First 1
        $failed = $script:RegistryTweaks | Where-Object id -eq 'gamebar-policy' | Select-Object -First 1
        Add-WinWSManifestRegistryTweakEvent -Group $applied -Status 'applied'
        Add-WinWSManifestRegistryTweakEvent -Group $skipped -Status 'skipped-not-selected'
        Add-WinWSManifestRegistryTweakEvent -Group $failed -Status 'failed' -ErrorMessage 'fixture failure'

        $manifestPath = Save-WinWSBuildManifest -OutputDir $tempRoot
        $auditPath = Join-Path $tempRoot 'WinWS-TweakAudit.json'
        $mdPath = Join-Path $tempRoot 'WinWS-TweakAudit.md'
        $regPath = Join-Path $tempRoot 'WinWS-TweakRollback.reg'
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
        $script:WinWSBuildManifest = $null
    }
}

function Assert-CachedDownloadResolver {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath().TrimEnd('\', '/')) ('winws_cache_resolver_test_' + [Guid]::NewGuid().ToString('n'))
    try {
        $null = New-Item -ItemType Directory -Path $tempRoot -Force
        $old = Join-Path $tempRoot 'PowerShell-7.5.0-win-arm64.zip'
        $new = Join-Path $tempRoot 'PowerShell-7.6.1-win-arm64.zip'
        Set-Content -LiteralPath $old -Value 'old' -Encoding ASCII
        Start-Sleep -Milliseconds 20
        Set-Content -LiteralPath $new -Value 'new' -Encoding ASCII

        $resolved = Get-WinWSCachedDownloadFile -DownloadDir $tempRoot -Patterns @('PowerShell-*-win-arm64.zip')
        if ($resolved -ne $new) {
            Add-SmokeFailure "Expected cached download resolver to pick newest matching file, got '$resolved'."
        }
        $missing = Get-WinWSCachedDownloadFile -DownloadDir $tempRoot -Patterns @('ViVeTool-*Arm64*.zip')
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
    $tempRoot = Join-Path ([IO.Path]::GetTempPath().TrimEnd('\', '/')) ('winws_payload_status_test_' + [Guid]::NewGuid().ToString('n'))
    $downloads = Join-Path $tempRoot 'downloads'
    $fonts = Join-Path $tempRoot 'fonts'
    try {
        $null = New-Item -ItemType Directory -Path $downloads -Force
        $null = New-Item -ItemType Directory -Path $fonts -Force
        Set-Content -LiteralPath (Join-Path $downloads 'PowerShell-7.6.1-win-arm64.zip') -Value 'ps7' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $downloads 'ViVeTool-v0.3.4-SnapdragonArm64.zip') -Value 'vive' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $downloads 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle') -Value 'winget' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $fonts 'CascadiaCodeNF-Regular.ttf') -Value 'font' -Encoding ASCII

        $complete = Get-WinWSOfflinePayloadCacheStatus -Architecture 'arm64' -DownloadDir $downloads -FontDir $fonts
        if (-not $complete.Complete) {
            Add-SmokeFailure "Expected complete offline payload cache, missing: $($complete.Missing -join ', ')"
        }

        Remove-Item -LiteralPath (Join-Path $downloads 'ViVeTool-v0.3.4-SnapdragonArm64.zip') -Force
        $incomplete = Get-WinWSOfflinePayloadCacheStatus -Architecture 'arm64' -DownloadDir $downloads -FontDir $fonts
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

    $profile = New-WinWSConsoleHeadlessProfile `
        -SourceIso '' `
        -Architecture 'arm64' `
        -ComputerName $headlessComputerName `
        -AccountName 'builder' `
        -InstallYasb `
        -DryRun

    $result = Test-WinWSBuildProfile -BuildProfile $profile
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

    $msProfile = New-WinWSConsoleHeadlessProfile `
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
        $null = New-WinWSConsoleHeadlessProfile -SourceIso '' -Architecture 'amd64'
        Add-SmokeFailure 'Expected non-dry-run headless console profile to require a source ISO.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'SourceIso|ProfilePath') {
            Add-SmokeFailure "Expected source ISO requirement error, got: $($_.Exception.Message)"
        }
    }

    try {
        $null = New-WinWSConsoleHeadlessProfile -SourceIso '' -Architecture 'amd64' -AutoLogon -DryRun
        Add-SmokeFailure 'Expected headless autologon to require an included password.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'Autologon requires') {
            Add-SmokeFailure "Expected autologon password error, got: $($_.Exception.Message)"
        }
    }
}

function Assert-HeadlessCliContracts {
    try {
        Assert-WinWSHeadlessParameterSet -BoundParameters @{
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
        Assert-WinWSHeadlessParameterSet -BoundParameters @{
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
        Assert-WinWSHeadlessParameterSet -BoundParameters @{
            ProfilePath = 'config\build-profiles\surface-uup.json'
            UupDumpZip = 'C:\UUP\source.zip'
            Yes = $true
        }
    }
    catch {
        Add-SmokeFailure "Expected ProfilePath + UupDumpZip to be valid for profile-backed UUP source prep, got: $($_.Exception.Message)"
    }

    $microsoftOobeComputerName = 'SL7'
    $profile = New-WinWSHeadlessProfileFromFlags `
        -SourceIso '' `
        -Architecture 'arm64' `
        -ComputerName $microsoftOobeComputerName `
        -AccountName 'Yanai' `
        -AccountMode MicrosoftOobe `
        -SetupOption CopilotPlus `
        -TimeZoneId 'Israel Standard Time' `
        -InputLocale 'en-US;he-IL' `
        -SystemLocale 'he-IL' `
        -UILanguage 'en-US' `
        -UILanguageFallback 'en-US' `
        -UserLocale 'he-IL' `
        -DryRun
    $config = New-WinWSBuildConfig -BuildProfile $profile
    if ($config.SetupOption -ne 'CopilotPlus' -or $config.AccountMode -ne 'MicrosoftOobe') {
        Add-SmokeFailure 'Expected flag-built headless profile to preserve CopilotPlus + MicrosoftOobe posture.'
    }
    if ($config.TimeZoneId -ne 'Israel Standard Time' -or $config.InputLocale -ne 'en-US;he-IL') {
        Add-SmokeFailure 'Expected flag-built headless profile to preserve regional and keyboard settings.'
    }
    if ($config.UserLocale -ne 'he-IL' -or $config.HomeLocationGeoId -ne 117) {
        Add-SmokeFailure 'Expected flag-built headless profile to preserve the builder home region for post-FirstLogon restore.'
    }
    if ($config.SetupUserLocale -ne 'de-DE' -or $config.SetupHomeLocationGeoId -ne 94 -or -not [bool]$config.DmaInterop.Enabled) {
        Add-SmokeFailure 'Expected every build to bake DMA interoperability with Germany as the setup region.'
    }
    if ($config.AppxPackages -contains 'Microsoft.Copilot' -or $config.AppxPackages -contains 'MicrosoftWindows.Client.WebExperience') {
        Add-SmokeFailure 'Expected CopilotPlus headless profile to preserve Copilot/WebExperience AppX packages.'
    }

    $minimalProfile = New-WinWSHeadlessProfileFromFlags -SourceIso '' -Architecture 'arm64' -DryRun
    $minimalConfig = New-WinWSBuildConfig -BuildProfile $minimalProfile
    if ((@($minimalProfile.profileGroups) -join ',') -ne 'Minimal') {
        Add-SmokeFailure 'Expected omitted headless group flags to default to the Minimal group only.'
    }
    if ($minimalConfig.Features -contains 'OpenSSH.Client' -or
        $minimalConfig.Features -contains 'Microsoft-Windows-Subsystem-Linux' -or
        $minimalConfig.RegistryTweaks -contains 'developer-mode') {
        Add-SmokeFailure 'Expected Minimal group to avoid developer-only features and tweaks.'
    }
    if ($minimalConfig.AppxPackages -notcontains 'Microsoft.Copilot' -or
        $minimalConfig.AppxPackages -notcontains 'Microsoft.GamingApp') {
        Add-SmokeFailure 'Expected Minimal group to remove Copilot/WebExperience and Xbox gaming apps.'
    }
    if ([bool]$minimalConfig.Privacy.Location) {
        Add-SmokeFailure 'Expected default headless profile to leave location services enabled.'
    }

    $locationOffProfile = New-WinWSHeadlessProfileFromFlags -SourceIso '' -Architecture 'arm64' -NoLocationServices -DryRun
    $locationOffConfig = New-WinWSBuildConfig -BuildProfile $locationOffProfile
    if (-not [bool]$locationOffConfig.Privacy.Location) {
        Add-SmokeFailure 'Expected -NoLocationServices to disable location services through the privacy policy profile.'
    }

    try {
        Assert-WinWSHeadlessParameterSet -BoundParameters @{ LocationServices = $true; NoLocationServices = $true }
        Add-SmokeFailure 'Expected LocationServices and NoLocationServices to be mutually exclusive.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'LocationServices|NoLocationServices') {
            Add-SmokeFailure "Expected location switch validation error, got: $($_.Exception.Message)"
        }
    }

    $groupProfile = New-WinWSHeadlessProfileFromFlags `
        -SourceIso '' `
        -Architecture 'arm64' `
        -Developer `
        -Copilot `
        -Gaming `
        -DesktopUI `
        -DryRun
    $groupConfig = New-WinWSBuildConfig -BuildProfile $groupProfile
    foreach ($expectedGroup in @('Minimal', 'Developer', 'CopilotPlus', 'Gaming', 'DesktopUI')) {
        if (@($groupProfile.profileGroups) -notcontains $expectedGroup) {
            Add-SmokeFailure "Expected combined headless flags to include profile group '$expectedGroup'."
        }
    }
    if ($groupConfig.Features -notcontains 'OpenSSH.Client' -or
        $groupConfig.RegistryTweaks -notcontains 'developer-mode' -or
        $groupConfig.RegistryTweaks -notcontains 'powershell-remotesigned') {
        Add-SmokeFailure 'Expected Developer group to enable OpenSSH, Developer Mode, and RemoteSigned.'
    }
    if (@($groupConfig.Editors).Count -ne 0 -or @($groupConfig.Wsl2Distros).Count -ne 0) {
        Add-SmokeFailure 'Expected Developer group to leave editors and WSL distros unselected by default.'
    }
    if ($groupConfig.AppxPackages -contains 'Microsoft.Copilot' -or
        $groupConfig.AppxPackages -contains 'MicrosoftWindows.Client.WebExperience' -or
        $groupConfig.AppxPackages -contains 'Microsoft.GamingApp') {
        Add-SmokeFailure 'Expected Copilot and Gaming groups to preserve Copilot/WebExperience and Xbox apps.'
    }
    if (-not ($groupConfig.InstallWindhawk -and $groupConfig.InstallYasb -and $groupConfig.InstallKomorebi)) {
        Add-SmokeFailure 'Expected DesktopUI group to select the opinionated WinWS shell stack.'
    }

    $thisPcProfile = New-WinWSHeadlessProfileFromFlags -SourceIso '' -Architecture 'arm64' -TargetDevice ThisPC -DryRun
    $thisPcConfig = New-WinWSBuildConfig -BuildProfile $thisPcProfile
    if ($thisPcConfig.TargetDevice -ne 'ThisPC' -or -not $thisPcConfig.ExportHostDrivers -or $thisPcConfig.Drivers.Source -ne 'Host') {
        Add-SmokeFailure 'Expected TargetDevice ThisPC to map to host driver export.'
    }

    $fakePack = Join-Path ([IO.Path]::GetTempPath()) ('winws-driver-pack-' + [Guid]::NewGuid().ToString('n') + '.msi')
    try {
        Set-Content -LiteralPath $fakePack -Value 'not a real msi; normalization only' -Encoding ASCII
        $packProfile = New-WinWSHeadlessProfileFromFlags -SourceIso '' -Architecture 'arm64' -TargetDevice ThisPC -DriverPack $fakePack -DryRun
        $packConfig = New-WinWSBuildConfig -BuildProfile $packProfile
        if ($packConfig.Drivers.Source -ne 'Custom' -or $packConfig.ExportHostDrivers) {
            Add-SmokeFailure 'Expected explicit DriverPack to override ThisPC host driver export.'
        }
    }
    finally {
        Remove-Item -LiteralPath $fakePack -Force -ErrorAction SilentlyContinue
    }

    try {
        $null = New-WinWSHeadlessProfileFromFlags -SourceIso '' -Architecture 'amd64'
        Add-SmokeFailure 'Expected flag-built headless profile to require SourceIso outside dry-run.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'SourceIso') {
            Add-SmokeFailure "Expected SourceIso requirement, got: $($_.Exception.Message)"
        }
    }

    $envName = 'WINWS_TEST_PASSWORD_' + [Guid]::NewGuid().ToString('n')
    try {
        [Environment]::SetEnvironmentVariable($envName, 'secret-from-env')
        $secret = Resolve-WinWSHeadlessSecret -PasswordEnvVar $envName
        if ($secret.Password -ne 'secret-from-env' -or $secret.UsedDeprecatedPassword) {
            Add-SmokeFailure 'Expected password env var to resolve without deprecated-password warning.'
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable($envName, $null)
    }

    $result = New-WinWSHeadlessResult -Result 'success' -BuildId 'test' -OutputIso 'C:\ISO\out.iso' -Warnings @('warn') -Failures @()
    $json = $result | ConvertTo-Json -Depth 8 -Compress
    $roundTrip = $json | ConvertFrom-Json
    if ($roundTrip.result -ne 'success' -or $roundTrip.buildId -ne 'test') {
        Add-SmokeFailure 'Expected headless JSON result contract to round-trip as a single object.'
    }

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('winws-uup-zip-test-' + [Guid]::NewGuid().ToString('n'))
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
        if (-not (Test-WinWSUupDumpZip -Path $zip)) {
            Add-SmokeFailure 'Expected fake UUP Dump conversion zip to validate.'
        }
        if (Test-WinWSUupDumpZip -Path $badZip) {
            Add-SmokeFailure 'Expected invalid UUP zip to be rejected.'
        }
        Assert-WinWSHeadlessParameterSet -BoundParameters @{ UupDumpZip = $zip; SourceIso = 'C:\ISO\win.iso' }
        Add-SmokeFailure 'Expected SourceIso + UupDumpZip to be rejected.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'SourceIso|UupDumpZip') {
            Add-SmokeFailure "Unexpected UUP zip validation error: $($_.Exception.Message)"
        }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Assert-HeadlessSourceAndDriverInputContracts {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('winws-headless-inputs-' + [Guid]::NewGuid().ToString('n'))
    try {
        $null = New-Item -ItemType Directory -Path $tempRoot -Force

        $uupZip = Get-WinWSTestUupDumpZipFixturePath
        if (-not (Test-WinWSUupDumpZip -Path $uupZip)) {
            Add-SmokeFailure "Expected UUP Dump fixture zip to validate before source prep: $uupZip"
        }
        else {
            $mockPreparedIso = Get-WinWSTestUupDumpPreparedIsoFixturePath
            $uupPrepArgs = @{
                UupDumpZip = $uupZip
                ValidateOnly = $true
            }
            if (-not [string]::IsNullOrWhiteSpace($mockPreparedIso)) {
                $uupPrepArgs.MockPreparedIso = $mockPreparedIso
            }
            $uupPrep = Invoke-WinWSUupDumpSourcePrep @uupPrepArgs
            if ($uupPrep.SourceKind -ne 'UupDumpZip' -or $uupPrep.RanConversion) {
                Add-SmokeFailure 'Expected UUP validate-only prep to fingerprint the fixture zip without converting.'
            }
            if (-not [string]::IsNullOrWhiteSpace($mockPreparedIso) -and -not [bool]$uupPrep.Mocked) {
                Add-SmokeFailure 'Expected prepared UUP fixture output to activate mocked source prep.'
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$uupPrep.GeneratedIso) -and -not $uupPrep.Reused) {
                Add-SmokeFailure 'Expected validate-only UUP prep to report a generated ISO only when reusing a prepared fixture artifact.'
            }
        }

        $iso = Get-WinWSTestIsoFixturePath
        $fixtureComputerName = 'iso-pc'
        $isoProfile = New-WinWSHeadlessProfileFromFlags `
            -SourceIso $iso `
            -Architecture 'arm64' `
            -ComputerName $fixtureComputerName `
            -AccountName 'dev' `
            -ValidateOnly
        $isoConfig = New-WinWSBuildConfig -BuildProfile $isoProfile
        $isoPreflight = Test-WinWSBuildPrerequisite -Config $isoConfig -AllowMissingSourceIso
        if (-not $isoPreflight.Passed) {
            Add-SmokeFailure "Expected existing ISO fixture path to pass source preflight, got: $($isoPreflight.Failures -join '; ')"
        }
        if ((Get-WinWSIsoArchitectureHint -Path $iso) -ne 'arm64') {
            Add-SmokeFailure 'Expected ISO filename architecture hint to detect arm64.'
        }

        $profilePath = Join-Path $tempRoot 'profile.json'
        $profile = New-WinWSHeadlessProfileFromFlags -SourceIso '' -Architecture 'amd64' -DryRun
        $null = Save-WinWSBuildProfile -BuildProfile $profile -Path $profilePath
        $imported = Import-WinWSHeadlessBuildProfile -ProfilePath $profilePath -SourceIsoOverride $iso
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
            $driverProfile = New-WinWSHeadlessProfileFromFlags `
                -SourceIso '' `
                -Architecture 'amd64' `
                -DriverSource Custom `
                -DriverPath $validDriverPath `
                -DryRun
            $driverConfig = New-WinWSBuildConfig -BuildProfile $driverProfile
            $driverPreflight = Test-WinWSBuildPrerequisite -Config $driverConfig -AllowMissingSourceIso
            if (-not $driverPreflight.Passed) {
                Add-SmokeFailure "Expected custom driver fixture to pass preflight: $validDriverPath; failures: $($driverPreflight.Failures -join '; ')"
            }
        }
        if (Test-Win11IsoDriverPath -Path $bad) {
            Add-SmokeFailure 'Expected non-driver file to be rejected by driver path validation.'
        }
        try {
            $null = Resolve-WinWSHeadlessDriverIntent -DriverPack $bad
            Add-SmokeFailure 'Expected -DriverPack to reject non-MSI/ZIP paths.'
        }
        catch {
            if ($_.Exception.Message -notmatch 'DriverPack must') {
                Add-SmokeFailure "Expected DriverPack extension validation error, got: $($_.Exception.Message)"
            }
        }

        $hostDriverProfile = New-WinWSHeadlessProfileFromFlags `
            -SourceIso '' `
            -Architecture (Get-BuildHostProcessorArchitecture) `
            -TargetDevice ThisPC `
            -DryRun
        $hostDriverConfig = New-WinWSBuildConfig -BuildProfile $hostDriverProfile
        $hostDriverPreflight = Test-WinWSBuildPrerequisite -Config $hostDriverConfig -AllowMissingSourceIso
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
        Set-WinWSUupConvertConfigPolicy -Path $ini
        $iniText = Get-Content -LiteralPath $ini -Raw
        foreach ($expected in @('AutoStart=1', 'AddUpdates=1', 'Cleanup=1', 'wim2esd=0', 'SkipISO=0', 'AutoExit=1')) {
            if ($iniText -notmatch "(?m)^$([regex]::Escape($expected))\r?$") {
                Add-SmokeFailure "Expected UUP conversion policy to enforce '$expected'."
            }
        }

        $preparedUup = Join-Path $tempRoot 'prepared-uup'
        $preparedFiles = Join-Path $preparedUup 'files'
        $preparedIso = Join-Path $preparedUup '26100.1.240331-1435.ge_release_CLIENT_ARM64FRE_en-us.iso'
        $null = New-Item -ItemType Directory -Path $preparedFiles -Force
        Set-Content -LiteralPath (Join-Path $preparedUup 'uup_download_windows.cmd') -Value '@echo off' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $preparedUup 'ConvertConfig.ini') -Value "[convert-UUP]`nAddUpdates=1`nCleanup=1`nwim2esd=0`nSkipISO=0" -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $preparedFiles 'get_aria2.ps1') -Value '' -Encoding ASCII
        Set-Content -LiteralPath $preparedIso -Value 'already converted iso fixture path only' -Encoding ASCII
        if (-not (Test-WinWSUupDumpFolder -Path $preparedUup)) {
            Add-SmokeFailure 'Expected prepared UUP Dump folder markers to validate.'
        }
        $prepared = Invoke-WinWSPreparedUupFolderSourcePrep -UupDumpFolder $preparedUup
        if ($prepared.SourceKind -ne 'PreparedUupDumpFolder' -or
            $prepared.GeneratedIso -ne $preparedIso -or
            -not $prepared.Reused -or
            $prepared.RanConversion) {
            Add-SmokeFailure 'Expected prepared UUP folder source prep to reuse the existing ISO without conversion.'
        }
        $missingIsoUup = Join-Path $tempRoot 'prepared-uup-no-iso'
        $missingIsoFiles = Join-Path $missingIsoUup 'files'
        $null = New-Item -ItemType Directory -Path $missingIsoFiles -Force
        Set-Content -LiteralPath (Join-Path $missingIsoUup 'uup_download_windows.cmd') -Value '@echo off' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $missingIsoUup 'ConvertConfig.ini') -Value "[convert-UUP]" -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $missingIsoFiles 'get_aria2.ps1') -Value '' -Encoding ASCII
        try {
            $null = Invoke-WinWSPreparedUupFolderSourcePrep -UupDumpFolder $missingIsoUup
            Add-SmokeFailure 'Expected prepared UUP folder source prep to reject a converted folder with no ISO.'
        }
        catch {
            if ($_.Exception.Message -notmatch 'no generated ISO') {
                Add-SmokeFailure "Expected missing prepared UUP ISO error, got: $($_.Exception.Message)"
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
