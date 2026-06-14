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
    }
    catch {
        Add-InstallPlanFailure "Install-plan case '$Name' failed: $($_.Exception.Message)"
    }
}

$cases = @(
    @{ Name = 'default'; Profile = (New-InstallPlanCaseProfile) },
    @{ Name = 'keep-edge'; Profile = (New-InstallPlanCaseProfile -Overrides @{ KeepEdge = $true }) },
    @{ Name = 'keep-gaming'; Profile = (New-InstallPlanCaseProfile -Overrides @{ KeepGaming = $true }) },
    @{ Name = 'keep-copilot'; Profile = (New-InstallPlanCaseProfile -Overrides @{ KeepCopilot = $true }) },
    @{ Name = 'flow-launcher'; Profile = (New-InstallPlanCaseProfile -Overrides @{ Launcher = 'FlowEverything' }) },
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

if ($failures.Count -gt 0) {
    throw "Install-plan contract failed:`n$($failures -join "`n")"
}

Write-Host 'Install-plan contract smoke passed.'
