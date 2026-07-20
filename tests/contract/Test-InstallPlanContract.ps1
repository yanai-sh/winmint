#Requires -Version 7.6
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
        $setupProfile = New-WinMintInstallPlanSetupProfile -BuildConfig $config
        $agentProfile = New-WinMintInstallPlanAgentProfile -BuildConfig $config
        $setupPlan = New-WinMintInstallPlanSetupPlan `
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
        foreach ($artifact in @(Get-WinMintSetupPayloadRequiredArtifacts -LiveInstallAudit ([bool]$config.LiveInstallAudit))) {
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
            -SetupPlan $plan.SetupPlan `
            -ImageArch ([string]$plan.BuildConfig.Architecture) `
            -LiveInstallAudit:$plan.BuildConfig.LiveInstallAudit

        $scriptsRoot = Join-Path $tempRoot 'Windows\Setup\Scripts'
        foreach ($relativePath in @(
            'SetupComplete.cmd',
            'SetupComplete.ps1',
            'Setup.Actions.ps1',
            'Specialize.ps1',
            'DefaultUser.ps1',
            'FirstLogon.ps1',
            'FirstLogon.Support.ps1',
            'WinMint.Runtime.Common.ps1',
            'WinMint.RuntimeState.ps1',
            'FirstLogon.Context.ps1',
            'FirstLogon.State.ps1',
            'FirstLogon.Host.ps1',
            'FirstLogon.Desktop.ps1',
            'FirstLogon.Region.ps1',
            'FirstLogon.Cleanup.ps1',
            'WindowsTerminal.Profiles.ps1',
            'FirstLogon.Transaction.ps1',
            'FirstLogon.Runtime.ps1',
            'WinMintSetupShell.Status.ps1',
            'WinMintSetupShell.Status.ps1',
            'setup-shell\WinMintSetupShell.exe',
            'setup-shell\tokens.json',
            'setup-shell\winmint_hero_ui.png',
            'setup-shell\winmint_hero.png',
            'WinMintSetupProfile.json',
            'WinMintAgent\Start-WinMintAgent.ps1',
            'WinMintAgent\WinMint.Runtime.Common.ps1',
            'WinMintAgent\Agent.Context.ps1',
            'WinMintAgent\WinMintAgentProfile.json',
            'WinMintAgent\packages.json',
            'WinMintAgent\Assets\Brand\winmint_logo_wordmark.png',
            'WinMintAgent\Assets\Windhawk\preset.manifest.json',
            'WinMintAgent\Assets\Windhawk\preset.json',
            'WinMintAgent\Assets\Yasb\preset.manifest.json',
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
        if (Test-Path -LiteralPath (Join-Path $scriptsRoot 'Audit-LiveInstall.ps1')) {
            Add-InstallPlanFailure 'Setup payload staging should not stage Audit-LiveInstall.ps1 unless LiveInstallAudit is enabled.'
        }
        if (Test-Path -LiteralPath (Join-Path $scriptsRoot 'WinMintSetupPlan.json')) {
            Add-InstallPlanFailure 'Setup payload staging should not write WinMintSetupPlan.json onto the guest image.'
        }

        foreach ($artifact in @(Get-WinMintSetupPayloadRequiredArtifacts -LiveInstallAudit:$plan.BuildConfig.LiveInstallAudit)) {
            if (@($result.RequiredArtifacts) -notcontains $artifact) {
                Add-InstallPlanFailure "Setup payload staging result omitted required artifact '$artifact'."
            }
            if (@($plan.SetupPlan.stagedArtifacts) -notcontains $artifact) {
                Add-InstallPlanFailure "Setup plan stagedArtifacts omitted setup payload artifact '$artifact'."
            }
        }

        $auditPlan = New-WinMintInstallPlan -BuildProfile (New-InstallPlanCaseProfile -Overrides @{ LiveInstallAudit = $true })
        $auditResult = Invoke-WinMintSetupPayloadStaging `
            -MountDir (Join-Path $tempRoot 'audit-mount') `
            -ScriptRoot $root `
            -AgentProfile $auditPlan.AgentProfile `
            -SetupProfile $auditPlan.SetupProfile `
            -SetupPlan $auditPlan.SetupPlan `
            -ImageArch ([string]$auditPlan.BuildConfig.Architecture) `
            -LiveInstallAudit:$auditPlan.BuildConfig.LiveInstallAudit
        $auditScriptsRoot = Join-Path $tempRoot 'audit-mount\Windows\Setup\Scripts'
        if (-not (Test-Path -LiteralPath (Join-Path $auditScriptsRoot 'Audit-LiveInstall.ps1') -PathType Leaf)) {
            Add-InstallPlanFailure 'Setup payload staging should stage Audit-LiveInstall.ps1 when LiveInstallAudit is enabled.'
        }
        foreach ($artifact in @(Get-WinMintSetupPayloadRequiredArtifacts -LiveInstallAudit:$auditPlan.BuildConfig.LiveInstallAudit)) {
            if (@($auditResult.RequiredArtifacts) -notcontains $artifact) {
                Add-InstallPlanFailure "LiveInstallAudit setup payload staging result omitted required artifact '$artifact'."
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

function Assert-BuildDeltaContributorCoverage {
    try {
        $plan = New-WinMintInstallPlan -BuildProfile (New-InstallPlanCaseProfile -Overrides @{
                InstallWindhawk = $true
                InstallYasb = $true
                InstallThide = $true
                PhoneLink = $true
                LiveInstallAudit = $true
                Editors = @('neovim')
                Browsers = @('zen-browser')
            })
        $buildDelta = New-WinMintBuildDeltaCatalog -BuildConfig $plan.BuildConfig -InstallPlan $plan
        $recordIds = @($buildDelta.records | ForEach-Object { [string]$_.id })

        foreach ($expected in @(
                'setup-action:windows-update-restore',
                'setup-action:ai-cleanup',
                'setup-action:inline-secret-cleanup',
                'setup-action:first-logon-runonce',
                'firstlogon:profiles',
                'firstlogon:packageManagers',
                'firstlogon:wsl',
                'firstlogon:launcherKey',
                'firstlogon:phoneLink',
                'firstlogon:shell',
                'firstlogon:windhawk',
                'firstlogon:browsers',
                'firstlogon:editors',
                'firstlogon:liveInstallAudit'
            )) {
            if ($recordIds -notcontains $expected) {
                Add-InstallPlanFailure "BuildDelta should contain contributor record '$expected'."
            }
        }
    }
    catch {
        Add-InstallPlanFailure "BuildDelta contributor coverage failed: $($_.Exception.Message)"
    }
}

function Assert-DirectPackageValidationContract {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath().TrimEnd('\', '/')) ('winmint_direct_package_test_' + [Guid]::NewGuid().ToString('n'))
    try {
        $null = New-Item -ItemType Directory -Path $tempRoot -Force
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
            Add-InstallPlanFailure 'Expected direct package validation to reject all direct tools while none are approved.'
        }
        catch {
            if ($_.Exception.Message -notmatch 'not currently approved') {
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
    @{ Name = 'shell-layers'; Profile = (New-InstallPlanCaseProfile -Overrides @{ InstallWindhawk = $true; InstallYasb = $true; InstallKomorebi = $true; InstallNilesoft = $true }) },
    @{ Name = 'local-account-password'; Profile = (New-InstallPlanCaseProfile -Overrides @{ Password = 'contract-secret'; PasswordSet = $true; AccountMode = 'Local' } -IncludeSecrets) },
    @{ Name = 'microsoft-oobe'; Profile = (New-InstallPlanCaseProfile -Overrides @{ AccountMode = 'MicrosoftOobe' }) },
    @{ Name = 'dma-off'; Profile = (New-InstallPlanCaseProfile -Overrides @{ TweakDmaInterop = $false }) },
    @{ Name = 'location-off'; Profile = (New-InstallPlanCaseProfile -Overrides @{ PrivLocation = $false }) },
    @{ Name = 'dual-boot'; Profile = (New-InstallPlanCaseProfile -Overrides @{ DiskMode = 'DualBootReserved'; DualBootPreset = 'Balanced' }) },
    @{ Name = 'dev-drive-partition'; Profile = (New-InstallPlanCaseProfile -Overrides @{ DiskMode = 'AutoWipeDisk0'; DevDriveMode = 'Partition'; DevDriveSizeGb = 128 }) },
    @{ Name = 'dev-drive-vhd'; Profile = (New-InstallPlanCaseProfile -Overrides @{ DevDriveMode = 'VhdDynamic'; DevDriveSizeGb = 64 }) },
    @{ Name = 'fixed-home'; Profile = (New-InstallPlanCaseProfile -Overrides @{ Edition = 'Home' }) }
)

function Assert-DevDriveInstallPlanContract {
    try {
        $off = New-WinMintInstallPlan -BuildProfile (New-InstallPlanCaseProfile)
        if ([bool]$off.AgentProfile.modules.devDrive.enabled -ne $false -or [string]$off.AgentProfile.modules.devDrive.mode -ne 'Off') {
            Add-InstallPlanFailure 'Default install plan must leave modules.devDrive disabled/Off.'
        }

        $part = New-WinMintInstallPlan -BuildProfile (New-InstallPlanCaseProfile -Overrides @{
                DiskMode = 'AutoWipeDisk0'
                DevDriveMode = 'Partition'
                DevDriveSizeGb = 256
            })
        $dd = $part.AgentProfile.modules.devDrive
        if (-not [bool]$dd.enabled -or [string]$dd.mode -ne 'Partition' -or [int]$dd.sizeGb -ne 256) {
            Add-InstallPlanFailure 'Partition Dev Drive must enable modules.devDrive with mode/sizeGb.'
        }
        if ([string]$part.BuildConfig.DevDrive.mode -ne 'Partition' -or [int]$part.BuildConfig.DevDrive.sizeGb -ne 256) {
            Add-InstallPlanFailure 'BuildConfig.DevDrive must carry Partition mode and sizeGb.'
        }

        $vhd = New-WinMintInstallPlan -BuildProfile (New-InstallPlanCaseProfile -Overrides @{
                DevDriveMode = 'VhdDynamic'
                DevDriveSizeGb = 64
            })
        if (-not [bool]$vhd.AgentProfile.modules.devDrive.enabled -or [string]$vhd.AgentProfile.modules.devDrive.mode -ne 'VhdDynamic') {
            Add-InstallPlanFailure 'VhdDynamic Dev Drive must enable modules.devDrive.'
        }
    }
    catch {
        Add-InstallPlanFailure "Dev Drive install-plan contract failed: $($_.Exception.Message)"
    }
}

foreach ($case in $cases) {
    Assert-InstallPlanMatchesWrappers -Name $case.Name -Profile $case.Profile
}
Assert-DevDriveInstallPlanContract
Assert-WslSelectionNormalizationContract
Assert-ManifestConsumesInstallPlanFacts
Assert-SetupPayloadStagingContract
Assert-DirectPackageValidationContract
Assert-BuildDeltaContributorCoverage

if ($failures.Count -gt 0) {
    throw "Install-plan contract failed:`n$($failures -join "`n")"
}

Write-Host 'Install-plan contract smoke passed.'

