#Requires -Version 7.3

$script:WinMintUiFixedEditionNames = @(
    'Windows 11 Home',
    'Windows 11 Pro',
    'Windows 11 Home Single Language'
)

function ConvertTo-WinMintBuildProfileSettings {
    param(
        [Parameter(Mandatory)][object]$State,
        [switch]$IncludeSecrets
    )

    $password = if ($IncludeSecrets) { [string]$State.Identity.Password } else { '' }
    $passwordSet = -not [string]::IsNullOrWhiteSpace([string]$State.Identity.Password)
    $wslDistros = @($State.Development.WslDistros)
    $profileGroups = @($State.ProfileGroups)
    if ($profileGroups.Count -eq 0) { $profileGroups = @('Minimal') }
    $isGaming = $profileGroups -contains 'Gaming'
    $isCopilot = $profileGroups -contains 'CopilotPlus'

    [ordered]@{
        Profile               = 'Minimal'
        ProfileGroups         = @($profileGroups)
        SetupOption           = if ($isCopilot) { 'CopilotPlus' } else { 'Minimal' }
        ComputerName          = [string]$State.Identity.ComputerName
        AccountName           = [string]$State.Identity.AccountName
        Password              = $password
        PasswordSet           = $passwordSet
        TimeZoneId            = [string]$State.Regional.TimeZoneId
        UILanguage            = [string]$State.Regional.UILanguage
        SystemLocale          = [string]$State.Regional.SystemLocale
        UILanguageFallback    = [string]$State.Regional.UILanguageFallback
        UserLocale            = [string]$State.Regional.UserLocale
        InputLocale           = [string]$State.Regional.InputLocale
        HomeLocationGeoId     = [int]$State.Regional.HomeLocationGeoId
        EditionMode           = [string]$State.Machine.EditionMode
        Edition               = [string]$State.Machine.Edition
        TargetDevice          = [string]$State.Machine.TargetDevice
        AutoLogon             = $passwordSet
        AutoWipeDisk          = ([string]$State.Disk.Mode -eq 'AutoWipeDisk0')
        CursorPackKind        = 'Windows11Modern'
        InstallWindhawk       = @($State.Desktop.Layers) -contains 'windhawk'
        InstallYasb           = @($State.Desktop.Layers) -contains 'yasb'
        InstallKomorebi       = @($State.Desktop.Layers) -contains 'komorebi'
        EditorNeovim          = @($State.Development.Editors) -contains 'neovim'
        EditorVSCodium        = @($State.Development.Editors) -contains 'vscodium'
        EditorCursor          = @($State.Development.Editors) -contains 'cursor'
        EditorZed             = @($State.Development.Editors) -contains 'zed'
        Wsl2Distro            = $wslDistros.Count -eq 0 ? 'None' : ($wslDistros -join ',')
        Wsl2Distros           = $wslDistros
        InjectDrivers         = [string]$State.Drivers.Source -ne 'None'
        DriverSource          = [string]$State.Drivers.Source
        DriverPath            = [string]$State.Drivers.Path
        RemoveAdvertising     = $true
        RemoveGaming          = -not $isGaming
        RemoveCommunication   = $true
        RemoveMicrosoftApps   = $true
        PrivTelemetry         = $true
        PrivAdvertising       = $true
        PrivLocation          = $true
        PrivTimeline          = $true
        TweakDarkMode         = $true
        TweakFileExt          = $true
        TweakStickyKeys       = $true
        TweakHardwareBypass   = [bool]$State.Machine.HardwareBypass
        ISOPath               = [string]$State.Iso.Path
        Architecture          = [string]$State.Iso.Architecture
    }
}

function New-WinMintUiBuildProfile {
    param(
        [Parameter(Mandatory)][object]$State,
        [switch]$IncludeSecrets
    )

    if (-not (Get-Command New-WinMintBuildProfile -ErrorAction SilentlyContinue)) {
        $script:WinMintRepositoryRoot = [string]$State.RepositoryRoot
        . (Join-Path $script:WinMintRepositoryRoot 'src\WinMint\Core.ps1')
        . (Get-WinMintPath -Name EngineEntry)
    }
    $settings = ConvertTo-WinMintBuildProfileSettings -State $State -IncludeSecrets:$IncludeSecrets
    return New-WinMintBuildProfileFromSettings -Settings $settings -IncludeSecrets:$IncludeSecrets
}
