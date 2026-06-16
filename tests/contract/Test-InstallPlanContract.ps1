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

$failures = [System.Collections.Generic.List[string]]::new()

function Add-InstallPlanFailure {
    param([string]$Message)
    $script:failures.Add($Message) | Out-Null
}

function ConvertTo-PlanComparableJson {
    param($Value)

    $Value | ConvertTo-Json -Depth 32 -Compress
}

function New-InstallPlanCaseProfile {
    param(
        [hashtable]$Overrides = @{},
        [switch]$IncludeSecrets
    )

    $settings = @{
        Profile = 'WinMint'
        ISOPath = (Get-WinMintTestOfficialIsoFixturePath)
        Architecture = 'arm64'
        ComputerName = 'WinMint'
        AccountName = 'dev'
        DriverSource = 'None'
        DriverPath = ''
    }
    foreach ($entry in $Overrides.GetEnumerator()) {
        $settings[$entry.Key] = $entry.Value
    }

    New-WinMintBuildProfile -Settings $settings -IncludeSecrets:$IncludeSecrets
}

function Assert-InstallPlanMatchesWrappers {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Profile
    )

    try {
        $plan = New-WinMintInstallPlan -BuildProfile $Profile
        $config = New-WinMintBuildConfig -BuildProfile $Profile
        $setupProfile = New-WinMintSetupProfile -BuildConfig $config
        $agentProfile = New-WinMintAgentProfile -BuildConfig $config
        $setupPlan = New-WinMintSetupPlan `
            -BuildConfig $config `
            -SetupProfile $setupProfile `
            -AgentProfile $agentProfile

        $pairs = @(
            @('BuildConfig', $plan.BuildConfig, $config),
            @('SetupProfile', $plan.SetupProfile, $setupProfile),
            @('AgentProfile', $plan.AgentProfile, $agentProfile),
            @('SetupPlan', $plan.SetupPlan, $setupPlan)
        )
        foreach ($pair in $pairs) {
            $actual = ConvertTo-PlanComparableJson -Value $pair[1]
            $expected = ConvertTo-PlanComparableJson -Value $pair[2]
            if ($actual -ne $expected) {
                Add-InstallPlanFailure "Install-plan case '$Name' changed $($pair[0]) output."
            }
        }

        foreach ($required in @('profile', 'keep', 'regional', 'removals', 'setup', 'firstLogon', 'artifacts')) {
            if (-not $plan.Facts.Contains($required)) {
                Add-InstallPlanFailure "Install-plan case '$Name' is missing reportable fact group '$required'."
            }
        }
        if ($plan.Facts.artifacts.setupProfile -ne 'WinMintSetupProfile.json' -or
            $plan.Facts.artifacts.agentProfile -ne 'WinMintAgentProfile.json' -or
            $plan.Facts.artifacts.setupPlan -ne 'WinMintSetupPlan.json') {
            Add-InstallPlanFailure "Install-plan case '$Name' changed generated artifact names."
        }
        foreach ($artifact in @(Get-WinMintSetupPayloadRequiredArtifacts)) {
            if (@($plan.SetupPlan.stagedArtifacts) -notcontains $artifact) {
                Add-InstallPlanFailure "Install-plan case '$Name' staged artifacts are missing '$artifact'."
            }
        }
    }
    catch {
        Add-InstallPlanFailure "Install-plan case '$Name' failed: $($_.Exception.Message)"
    }
}

function Assert-WslSelectionNormalizationContract {
    try {
        $selection = ConvertTo-WinMintWslSelection -Values @(
            'Ubuntu,NixOS-WSL',
            'FedoraLinux-44',
            'Arch Linux',
            'Pengwin'
        )
        foreach ($expected in @('Ubuntu', 'NixOS-WSL', 'FedoraLinux', 'archlinux', 'pengwin')) {
            if (@($selection.ProfileTokens) -notcontains $expected) {
                Add-InstallPlanFailure "WSL selection profile tokens are missing '$expected'."
            }
        }
        foreach ($expected in @('Ubuntu', 'NixOS', 'FedoraLinux', 'archlinux', 'pengwin')) {
            if (@($selection.AgentTokens) -notcontains $expected) {
                Add-InstallPlanFailure "WSL selection agent tokens are missing '$expected'."
            }
        }
        $nixos = @($selection.Items | Where-Object { [string]$_.profileToken -eq 'NixOS-WSL' } | Select-Object -First 1)
        if (-not $nixos -or [string]$nixos.agentToken -ne 'NixOS' -or [string]$nixos.installIdentity -ne 'NixOS') {
            Add-InstallPlanFailure 'Expected NixOS-WSL profile token to map to NixOS agent/install identity.'
        }

        $profile = New-InstallPlanCaseProfile -Overrides @{ Wsl2Distros = @('Ubuntu', 'NixOS-WSL', 'FedoraLinux-44') }
        $plan = New-WinMintInstallPlan -BuildProfile $profile
        if (@($plan.BuildConfig.Wsl2Distros) -notcontains 'NixOS-WSL') {
            Add-InstallPlanFailure 'Expected build config WSL distros to preserve the NixOS-WSL profile token.'
        }
        if (@($plan.AgentProfile.modules.wsl.distros) -notcontains 'NixOS') {
            Add-InstallPlanFailure 'Expected agent profile WSL distros to use the NixOS runtime token.'
        }
        if (@($plan.Facts.firstLogon.wslDistros) -notcontains 'NixOS-WSL' -or
            @($plan.Facts.firstLogon.wslAgentDistros) -notcontains 'NixOS') {
            Add-InstallPlanFailure 'Expected install-plan facts to expose both WSL profile and agent tokens.'
        }
    }
    catch {
        Add-InstallPlanFailure "WSL selection normalization contract failed: $($_.Exception.Message)"
    }
}

function Assert-RayCastEverythingBackendContract {
    try {
        $armProfile = New-InstallPlanCaseProfile -Overrides @{ Launcher = 'Raycast'; Architecture = 'arm64' }
        $armPlan = New-WinMintInstallPlan -BuildProfile $armProfile
        if ([string]$armPlan.AgentProfile.modules.raycast.everythingBackend.package -ne 'everything-arm64-beta') {
            Add-InstallPlanFailure 'Expected ARM64 Raycast builds to use the pinned native Everything 1.5 ARM64 direct payload rather than x64-only winget beta metadata.'
        }
        $armRequires = @(
            @($armPlan.AgentProfile.modules.raycast.extensions) |
                Where-Object { [string]$_.id -eq 'everything-search' } |
                Select-Object -First 1
        ).requires
        if (@($armRequires) -notcontains 'everything-arm64-beta' -or @($armRequires) -contains 'everything-cli') {
            Add-InstallPlanFailure 'Expected ARM64 Raycast Everything extension requirements to include only the pinned ARM64 backend package.'
        }

        $amdProfile = New-InstallPlanCaseProfile -Overrides @{ Launcher = 'Raycast'; Architecture = 'amd64' }
        $amdPlan = New-WinMintInstallPlan -BuildProfile $amdProfile
        if ([string]$amdPlan.AgentProfile.modules.raycast.everythingBackend.package -ne 'everything-beta') {
            Add-InstallPlanFailure 'Expected amd64 Raycast builds to use Everything Beta.'
        }
        $amdRequires = @(
            @($amdPlan.AgentProfile.modules.raycast.extensions) |
                Where-Object { [string]$_.id -eq 'everything-search' } |
                Select-Object -First 1
        ).requires
        if (@($amdRequires) -notcontains 'everything-beta' -or @($amdRequires) -contains 'everything-cli') {
            Add-InstallPlanFailure 'Expected amd64 Raycast Everything extension requirements to include only Everything Beta.'
        }
    }
    catch {
        Add-InstallPlanFailure "Raycast Everything backend contract failed: $($_.Exception.Message)"
    }
}

function Assert-RaycastExtensionCurationContract {
    try {
        $profile = New-InstallPlanCaseProfile -Overrides @{
            Launcher = 'Raycast'
            InstallThide = $true
            Editors = @('vscode', 'zed')
            Browsers = @('zen-browser', 'helium')
        }
        $plan = New-WinMintInstallPlan -BuildProfile $profile
        $extensions = @($plan.AgentProfile.modules.raycast.extensions)
        $extensionIds = @($extensions | ForEach-Object { [string]$_.id })
        foreach ($expected in @(
                'everything-search',
                'windows-terminal',
                'window-walker',
                'visual-studio-code',
                'zed-recent-projects',
                'zen-browser'
            )) {
            if ($extensionIds -notcontains $expected) {
                Add-InstallPlanFailure "Expected Raycast extension curation to include '$expected'."
            }
        }
        foreach ($unexpected in @(
                'winget',
                'scoop',
                'browser-bookmarks',
                'system-commands',
                'emoji',
                'calculator',
                'snippets'
            )) {
            if ($extensionIds -contains $unexpected) {
                Add-InstallPlanFailure "Raycast extension curation must not include '$unexpected'."
            }
        }

        $everything = $extensions | Where-Object { [string]$_.id -eq 'everything-search' } | Select-Object -First 1
        if (-not $everything -or [string]$everything.owner -ne 'anastasiy_safari') {
            Add-InstallPlanFailure 'Expected Everything Raycast extension owner to remain anastasiy_safari.'
        }
        $walker = $extensions | Where-Object { [string]$_.id -eq 'window-walker' } | Select-Object -First 1
        if (-not $walker -or [string]$walker.owner -ne 'nazzy_wazzy_lu') {
            Add-InstallPlanFailure 'Expected Window Walker Raycast extension owner to remain nazzy_wazzy_lu.'
        }
    }
    catch {
        Add-InstallPlanFailure "Raycast extension curation contract failed: $($_.Exception.Message)"
    }
}

function Assert-EverythingConfigurationContract {
    try {
        $raycastText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Modules\Raycast.ps1') -Raw
        foreach ($expected in @(
                'exclude_hidden_files_and_folders',
                'exclude_system_files_and_folders',
                'exclude_list_enabled',
                'C:\$Recycle.Bin\**',
                'C:\Windows\SoftwareDistribution\**',
                'C:\Windows\WinSxS\**',
                'C:\Windows\Installer\**',
                'C:\ProgramData\Microsoft\Windows\WER\**',
                'C:\Users\*\AppData\Local\Temp\**',
                'http_server_enabled',
                'etp_server_enabled',
                'ftp_server_enabled',
                'content_index_enabled',
                'NO_ALPHA_INSTANCE'
            )) {
            if ($raycastText -notmatch [regex]::Escape($expected)) {
                Add-InstallPlanFailure "Everything backend configuration should contain '$expected'."
            }
        }
        foreach ($forbidden in @(
                'C:\Users\*\AppData\**',
                'node_modules',
                '.git',
                '.venv',
                'browser cache',
                'Everything.Cli',
                'everything-cli'
            )) {
            if ($raycastText -match [regex]::Escape($forbidden)) {
                Add-InstallPlanFailure "Everything backend configuration must not include broad/noisy exclusion or CLI dependency '$forbidden'."
            }
        }
    }
    catch {
        Add-InstallPlanFailure "Everything configuration contract failed: $($_.Exception.Message)"
    }
}

function Assert-VirtualDesktopFlyoutSuppressionContract {
    try {
        $defaultPlan = New-WinMintInstallPlan -BuildProfile (New-InstallPlanCaseProfile)
        if ([bool]$defaultPlan.SetupProfile.setupComplete.disableVirtualDesktopFlyout) {
            Add-InstallPlanFailure 'Expected default builds to leave the virtual desktop flyout override disabled.'
        }

        $thidePlan = New-WinMintInstallPlan -BuildProfile (New-InstallPlanCaseProfile -Overrides @{ InstallThide = $true })
        if (-not [bool]$thidePlan.SetupProfile.setupComplete.disableVirtualDesktopFlyout) {
            Add-InstallPlanFailure 'Expected thide builds to disable the virtual desktop switch flyout even when Windhawk is not selected.'
        }

        $windhawkPlan = New-WinMintInstallPlan -BuildProfile (New-InstallPlanCaseProfile -Overrides @{ InstallWindhawk = $true })
        if (-not [bool]$windhawkPlan.SetupProfile.setupComplete.disableVirtualDesktopFlyout) {
            Add-InstallPlanFailure 'Expected Windhawk builds to keep disabling the virtual desktop switch flyout.'
        }

        $systemHygieneText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\SetupComplete\SystemHygiene.ps1') -Raw
        foreach ($featureId in @('42105254', '42316343', '34508225', '40459297')) {
            if ($systemHygieneText -notmatch [regex]::Escape($featureId)) {
                Add-InstallPlanFailure "Expected SetupComplete ViVeTool flyout suppression to include feature id '$featureId'."
            }
        }
    }
    catch {
        Add-InstallPlanFailure "Virtual desktop flyout suppression contract failed: $($_.Exception.Message)"
    }
}

function Assert-ManifestConsumesInstallPlanFacts {
    try {
        $profile = New-InstallPlanCaseProfile -Overrides @{
            Wsl2Distros = @('NixOS-WSL')
            KeepEdge = $true
        }
        $plan = New-WinMintInstallPlan -BuildProfile $profile
        $plan.Facts.regional.setupCountry = 'PlanCountry'
        $plan.Facts.regional.setupUserLocale = 'en-GB'
        $plan.Facts.regional.setupHomeLocationGeoId = 242
        $plan.Facts.regional.restoreTimeZoneId = 'Plan Standard Time'
        $plan.Facts.regional.restoreUserLocale = 'en-AU'
        $plan.Facts.regional.restoreHomeLocationGeoId = 12
        $plan.Facts.regional.locationServicesPolicy = 'disabled'
        $plan.Facts.removals.appxPrefixes = @('Plan.Appx')
        $plan.Facts.removals.appxCatalogVersion = 99
        $plan.Facts.removals.featuresEnabled = @('PlanFeature')
        $plan.Facts.removals.aiPolicy = 'Core'
        $plan.Facts.removals.aiCatalogVersion = 98
        $plan.Facts.removals.aiAppxPrefixes = @('Plan.Ai')
        $plan.Facts.removals.aiRegistryPolicies = @('windows-ai-core-policy')
        $plan.Facts.removals.aiAggressiveActions = @('plan-aggressive-action')
        Initialize-WinMintBuildManifest -Config $plan.BuildConfig -InstallPlan $plan
        $manifest = Get-WinMintBuildManifest

        if ([string]$manifest.regional.dmaInterop.setupCountry -ne 'PlanCountry' -or
            [string]$manifest.regional.dmaInterop.setupUserLocale -ne 'en-GB' -or
            [int]$manifest.regional.dmaInterop.setupHomeLocationGeoId -ne 242 -or
            [string]$manifest.regional.dmaInterop.restoredTimeZoneId -ne 'Plan Standard Time' -or
            [string]$manifest.regional.dmaInterop.restoredUserLocale -ne 'en-AU' -or
            [int]$manifest.regional.dmaInterop.restoredHomeLocationGeoId -ne 12 -or
            [string]$manifest.regional.dmaInterop.locationServicesPolicy -ne 'disabled') {
            Add-InstallPlanFailure 'Expected manifest regional facts to come from InstallPlan.Facts.'
        }
        if (@($manifest.removals.appxPrefixes) -notcontains 'Plan.Appx' -or
            [int]$manifest.removals.appxCatalogVersion -ne 99 -or
            @($manifest.removals.featuresEnabled) -notcontains 'PlanFeature' -or
            [string]$manifest.removals.ai.policy -ne 'Core' -or
            [int]$manifest.removals.ai.catalogVersion -ne 98 -or
            @($manifest.removals.ai.appxPrefixes) -notcontains 'Plan.Ai' -or
            @($manifest.removals.ai.registryPoliciesApplied) -notcontains 'windows-ai-core-policy' -or
            @($manifest.removals.ai.aggressiveActions) -notcontains 'plan-aggressive-action') {
            Add-InstallPlanFailure 'Expected manifest removal and AI facts to come from InstallPlan.Facts.'
        }
    }
    catch {
        Add-InstallPlanFailure "Manifest install-plan fact consumption failed: $($_.Exception.Message)"
    }
    finally {
        Clear-WinMintBuildManifest
    }
}

function Assert-SetupPayloadStagingContract {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath().TrimEnd('\', '/')) ('winmint_setup_payload_test_' + [Guid]::NewGuid().ToString('n'))
    try {
        $profile = New-InstallPlanCaseProfile -Overrides @{
            InstallWindhawk = $true
            InstallYasb = $true
            InstallKomorebi = $true
        }
        $plan = New-WinMintInstallPlan -BuildProfile $profile
        $null = New-Item -ItemType Directory -Path $tempRoot -Force

        $result = Invoke-WinMintSetupPayloadStaging `
            -MountDir $tempRoot `
            -ScriptRoot $root `
            -AgentProfile $plan.AgentProfile `
            -SetupProfile $plan.SetupProfile `
            -SetupPlan $plan.SetupPlan

        $scriptsRoot = Join-Path $tempRoot 'Windows\Setup\Scripts'
        foreach ($relativePath in @(
            'SetupComplete.cmd',
            'SetupComplete.ps1',
            'Specialize.ps1',
            'DefaultUser.ps1',
            'FirstLogon.ps1',
            'FirstLogon.Support.ps1',
            'FirstLogon.Transaction.ps1',
            'FirstLogon.Runtime.ps1',
            'SetupComplete\Edge.ps1',
            'Audit-LiveInstall.ps1',
            'WinMintSetupProfile.json',
            'WinMintSetupPlan.json',
            'WinMintAgent\Start-WinMintAgent.ps1',
            'WinMintAgent\BuildProfile.json',
            'WinMintAgent\packages.json',
            'WinMintAgent\Assets\Brand\winmint_logo_wordmark.png',
            'WinMintAgent\Assets\Windhawk\preset.json',
            'WinMintAgent\Assets\Yasb\config.yaml',
            'WinMintAgent\Assets\Yasb\styles.css',
            'WinMintAgent\Assets\Komorebi\komorebi.json',
            'WinMintAgent\Assets\Komorebi\applications.json',
            'WinMintAgent\Assets\Komorebi\whkdrc'
        )) {
            $path = Join-Path $scriptsRoot $relativePath
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                Add-InstallPlanFailure "Setup payload staging did not write expected artifact '$relativePath'."
            }
        }

        if (Test-Path -LiteralPath (Join-Path $scriptsRoot 'WinMintAgent\agent')) {
            Add-InstallPlanFailure 'Setup payload staging nested the agent payload under WinMintAgent\agent.'
        }

        foreach ($artifact in @(Get-WinMintSetupPayloadRequiredArtifacts)) {
            if (@($result.RequiredArtifacts) -notcontains $artifact) {
                Add-InstallPlanFailure "Setup payload staging result omitted required artifact '$artifact'."
            }
            if (@($plan.SetupPlan.stagedArtifacts) -notcontains $artifact) {
                Add-InstallPlanFailure "Setup plan stagedArtifacts omitted setup payload artifact '$artifact'."
            }
        }
    }
    catch {
        Add-InstallPlanFailure "Setup payload staging contract failed: $($_.Exception.Message)"
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Assert-DirectPackageValidationContract {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath().TrimEnd('\', '/')) ('winmint_direct_package_test_' + [Guid]::NewGuid().ToString('n'))
    try {
        $null = New-Item -ItemType Directory -Path $tempRoot -Force
        $missingHashPath = Join-Path $tempRoot 'packages-missing-hash.json'
        [ordered]@{
            tools = [ordered]@{
                'everything-arm64-beta' = [ordered]@{
                    displayName = 'Everything 1.5 Beta ARM64'
                    source = 'direct'
                    id = 'Everything-1.5.0.1415b.ARM64'
                    version = '1.5.0.1415b'
                    url = 'https://www.voidtools.com/Everything-1.5.0.1415b.ARM64.en-US-Setup.exe'
                    architectures = @('arm64')
                    silentArgs = @('/S')
                }
            }
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $missingHashPath -Encoding UTF8

        try {
            Assert-WinMintAgentToolSources -ManifestPath $missingHashPath
            Add-InstallPlanFailure 'Expected direct package validation to reject a missing SHA256 hash.'
        }
        catch {
            if ($_.Exception.Message -notmatch 'pinned Everything 1\.5\.0\.1415b ARM64') {
                Add-InstallPlanFailure "Direct package missing-hash validation failed with the wrong message: $($_.Exception.Message)"
            }
        }

        $unexpectedDirectPath = Join-Path $tempRoot 'packages-unexpected-direct.json'
        [ordered]@{
            tools = [ordered]@{
                'some-tool' = [ordered]@{
                    displayName = 'Some Tool'
                    source = 'direct'
                    id = 'Some.Tool'
                    version = '1.0.0'
                    url = 'https://example.invalid/tool.exe'
                    sha256 = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
                    architectures = @('amd64')
                    silentArgs = @('/S')
                }
            }
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $unexpectedDirectPath -Encoding UTF8

        try {
            Assert-WinMintAgentToolSources -ManifestPath $unexpectedDirectPath
            Add-InstallPlanFailure 'Expected direct package validation to reject non-Everything direct tools.'
        }
        catch {
            if ($_.Exception.Message -notmatch 'restricted to the pinned Everything') {
                Add-InstallPlanFailure "Unexpected direct package validation failed with the wrong message: $($_.Exception.Message)"
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$cases = @(
    @{ Name = 'default'; Profile = (New-InstallPlanCaseProfile) },
    @{ Name = 'keep-edge'; Profile = (New-InstallPlanCaseProfile -Overrides @{ KeepEdge = $true }) },
    @{ Name = 'keep-gaming'; Profile = (New-InstallPlanCaseProfile -Overrides @{ KeepGaming = $true }) },
    @{ Name = 'keep-copilot'; Profile = (New-InstallPlanCaseProfile -Overrides @{ KeepCopilot = $true }) },
    @{ Name = 'raycast-launcher'; Profile = (New-InstallPlanCaseProfile -Overrides @{ Launcher = 'Raycast' }) },
    @{ Name = 'shell-layers'; Profile = (New-InstallPlanCaseProfile -Overrides @{ InstallWindhawk = $true; InstallYasb = $true; InstallKomorebi = $true; InstallNilesoft = $true }) },
    @{ Name = 'local-account-password'; Profile = (New-InstallPlanCaseProfile -Overrides @{ Password = 'contract-secret'; PasswordSet = $true; AccountMode = 'Local' } -IncludeSecrets) },
    @{ Name = 'microsoft-oobe'; Profile = (New-InstallPlanCaseProfile -Overrides @{ AccountMode = 'MicrosoftOobe' }) },
    @{ Name = 'dma-off'; Profile = (New-InstallPlanCaseProfile -Overrides @{ TweakDmaInterop = $false }) },
    @{ Name = 'location-off'; Profile = (New-InstallPlanCaseProfile -Overrides @{ PrivLocation = $false }) },
    @{ Name = 'dual-boot'; Profile = (New-InstallPlanCaseProfile -Overrides @{ DiskMode = 'DualBootReserved'; DualBootPreset = 'Balanced' }) },
    @{ Name = 'fixed-home'; Profile = (New-InstallPlanCaseProfile -Overrides @{ Edition = 'Home' }) }
)

foreach ($case in $cases) {
    Assert-InstallPlanMatchesWrappers -Name $case.Name -Profile $case.Profile
}
Assert-WslSelectionNormalizationContract
Assert-RayCastEverythingBackendContract
Assert-RaycastExtensionCurationContract
Assert-EverythingConfigurationContract
Assert-VirtualDesktopFlyoutSuppressionContract
Assert-ManifestConsumesInstallPlanFacts
Assert-SetupPayloadStagingContract
Assert-DirectPackageValidationContract

if ($failures.Count -gt 0) {
    throw "Install-plan contract failed:`n$($failures -join "`n")"
}

Write-Host 'Install-plan contract smoke passed.'
