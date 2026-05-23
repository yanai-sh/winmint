#Requires -Version 7.3

function Get-WinMintProfileSetting {
    param(
        [object]$Settings,
        [string]$Name,
        $Default = $null
    )

    if ($Settings -is [System.Collections.IDictionary] -and $Settings.Contains($Name)) {
        return $Settings[$Name]
    }
    $prop = $Settings.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $Default
}

function Test-WinMintProfileSettingExists {
    param(
        [object]$Settings,
        [string]$Name
    )

    if ($null -eq $Settings) { return $false }
    if ($Settings -is [System.Collections.IDictionary]) { return $Settings.Contains($Name) }
    return $null -ne $Settings.PSObject.Properties[$Name]
}

function Get-WinMintProfileStringSetting {
    param(
        [object]$Settings,
        [string]$Name,
        [string]$Default = ''
    )

    $value = [string](Get-WinMintProfileSetting $Settings $Name $Default)
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

function ConvertTo-WinMintProfileStringArray {
    param($Value)

    @(
        @($Value) |
            ForEach-Object { ([string]$_) -split ',' } |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne 'None' } |
            Select-Object -Unique
    )
}

function Resolve-WinMintRegionGeoId {
    param(
        [string]$CultureName,
        [int]$Default = 244
    )

    if (-not [string]::IsNullOrWhiteSpace($CultureName)) {
        try {
            return [int]([System.Globalization.RegionInfo]::new($CultureName)).GeoId
        }
        catch {
            Write-Verbose "Could not resolve GeoID for culture '$CultureName': $($_.Exception.Message)"
        }
    }
    return $Default
}

function Resolve-WinMintDmaInteropSetupRegion {
    $preferred = @{ Country = 'Ireland'; Culture = 'en-IE'; FallbackGeoId = 68 }
    $fallback = @{ Country = 'Germany'; Culture = 'de-DE'; FallbackGeoId = 94 }

    foreach ($candidate in @($preferred, $fallback)) {
        try {
            $region = [System.Globalization.RegionInfo]::new([string]$candidate.Culture)
            return [pscustomobject]@{
                Country = [string]$candidate.Country
                Culture = [string]$candidate.Culture
                GeoId = [int]$region.GeoId
            }
        }
        catch {
            Write-Verbose "Could not resolve DMA setup region '$($candidate.Culture)': $($_.Exception.Message)"
        }
    }

    [pscustomobject]@{
        Country = [string]$fallback.Country
        Culture = [string]$fallback.Culture
        GeoId = [int]$fallback.FallbackGeoId
    }
}

function Get-WinMintProfileAiPolicy {
    param(
        [object]$Settings,
        [string]$SetupOption = 'Minimal'
    )

    $raw = [string](Get-WinMintProfileSetting $Settings 'AiPolicy' '')
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $raw = [string](Get-WinMintProfileSetting $Settings 'AIPolicy' '')
    }
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $raw = if ($SetupOption -eq 'CopilotPlus') { 'ServiceableFull' } else { 'Core' }
    }
    switch -Regex ($raw) {
        '^(Core|Minimal|Default)$' { return 'Core' }
        '^(ServiceableFull|Full|FullServiceable)$' { return 'ServiceableFull' }
        '^(AggressiveExperimental|ExperimentalAggressive|Experimental)$' {
            if ([string]$env:WINMINT_ENABLE_EXPERIMENTAL_AI_REMOVAL -ne '1') {
                throw 'AggressiveExperimental AI removal is internal-only. Set WINMINT_ENABLE_EXPERIMENTAL_AI_REMOVAL=1 to enable it for development.'
            }
            return 'AggressiveExperimental'
        }
        default { throw "Unsupported AI removal policy '$raw'." }
    }
}

function ConvertTo-WinMintProfileGroupArray {
    param([object]$Settings)

    $rawGroups = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $Settings 'ProfileGroups' @()))
    $groups = [System.Collections.Generic.List[string]]::new()
    foreach ($group in $rawGroups) {
        switch -Regex ($group) {
            '^(Minimal|Base|Core)$' { $groups.Add('Minimal') | Out-Null; break }
            '^(Developer|Dev)$' { $groups.Add('Developer') | Out-Null; break }
            '^(CopilotPlus|Copilot|AI)$' { $groups.Add('CopilotPlus') | Out-Null; break }
            '^(Gaming|Game)$' { $groups.Add('Gaming') | Out-Null; break }
            '^(DesktopUI|Desktop-UI|CustomUI|Shell)$' { $groups.Add('DesktopUI') | Out-Null; break }
        }
    }

    $setupOption = Get-WinMintProfileSetupOption -Settings $Settings
    if ($setupOption -eq 'CopilotPlus') { $groups.Add('CopilotPlus') | Out-Null }

    if ($groups.Count -eq 0) { $groups.Add('Minimal') | Out-Null }
    return @($groups.ToArray() | Select-Object -Unique)
}

function Get-WinMintAppxRemovalCatalog {
    $path = Get-WinMintPath -Name Config -ChildPath 'appx-removal.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "AppX removal catalog not found: $path"
    }
    Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Test-WinMintProfileGroup {
    param(
        [object]$Settings,
        [Parameter(Mandatory)][string]$Group
    )

    return @(ConvertTo-WinMintProfileGroupArray -Settings $Settings) -contains $Group
}

function Get-WinMintProfileEditorIds {
    param([object]$Settings)

    $editors = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $Settings 'Editors' @()))
    if ($editors.Count -gt 0 -or (Test-WinMintProfileSettingExists -Settings $Settings -Name 'Editors')) {
        return $editors
    }

    $editorFlags = @(
        @('EditorCursor', 'cursor'),
        @('EditorVSCodium', 'vscodium'),
        @('EditorVSCode', 'vscode'),
        @('EditorZed', 'zed'),
        @('EditorNeovim', 'neovim')
    )
    $hasExplicitEditorFlag = @(
        $editorFlags |
            Where-Object { Test-WinMintProfileSettingExists -Settings $Settings -Name $_[0] }
    ).Count -gt 0
    $editors = @(
        $editorFlags |
            Where-Object { [bool](Get-WinMintProfileSetting $Settings $_[0] $false) } |
            ForEach-Object { $_[1] }
    )
    if ($editors.Count -gt 0 -or $hasExplicitEditorFlag) { return $editors }

    @()
}

function Get-WinMintProfileDesktopLayers {
    param([object]$Settings)

    $layers = [System.Collections.Generic.List[string]]::new()
    if ([bool](Get-WinMintProfileSetting $Settings 'DesktopUiDefault' $false)) {
        $layers.Add('windhawk')
        $layers.Add('yasb')
        $layers.Add('komorebi')
    }
    if ([bool](Get-WinMintProfileSetting $Settings 'InstallWindhawk' $false)) { $layers.Add('windhawk') }
    if ([bool](Get-WinMintProfileSetting $Settings 'InstallYasb' $false)) { $layers.Add('yasb') }
    if ([bool](Get-WinMintProfileSetting $Settings 'InstallKomorebi' $false)) { $layers.Add('komorebi') }
    if ($layers.Count -eq 0) { $layers.Add('standard') }
    return @($layers.ToArray() | Select-Object -Unique)
}

function Get-WinMintAppxBloatwareCategories {
    $catalog = Get-WinMintAppxRemovalCatalog
    [ordered]@{
        'Core Microsoft'      = @($catalog.groups.coreMicrosoft)
        'Communication'       = @($catalog.groups.communication)
        'Gaming (Xbox)'       = @($catalog.groups.gaming)
        'Consumer third-party' = @($catalog.groups.consumerThirdParty)
        'OEM consumer'         = @($catalog.groups.oemConsumer)
    }
}

function Get-WinMintEffectiveAppxRemovalPrefix {
    param([object]$Settings)

    $categories = Get-WinMintAppxBloatwareCategories
    $effective = [System.Collections.Generic.List[string]]::new()
    $effective.AddRange([string[]]$categories['Core Microsoft'])
    if ([bool](Get-WinMintProfileSetting $Settings 'RemoveConsumerThirdParty' $false)) {
        $effective.AddRange([string[]]$categories['Consumer third-party'])
        $effective.AddRange([string[]]$categories['OEM consumer'])
    }
    if ([bool](Get-WinMintProfileSetting $Settings 'RemoveGaming' $true)) {
        $effective.AddRange([string[]]$categories['Gaming (Xbox)'])
    }
    if ([bool](Get-WinMintProfileSetting $Settings 'RemoveCommunication' $true)) {
        $effective.AddRange([string[]]$categories['Communication'])
    }
    return @($effective.ToArray() | Sort-Object -Unique)
}

function Get-WinMintProfileAppxRemovalPrefix {
    param([object]$Removals)

    $settings = [ordered]@{
        RemoveAdvertising = [bool](Get-WinMintProfileSetting $Removals 'advertising' $true)
        RemoveGaming = [bool](Get-WinMintProfileSetting $Removals 'gaming' $true)
        RemoveCommunication = [bool](Get-WinMintProfileSetting $Removals 'communication' $true)
        RemoveMicrosoftApps = [bool](Get-WinMintProfileSetting $Removals 'microsoftApps' $true)
    }
    Get-WinMintEffectiveAppxRemovalPrefix -Settings $settings
}

function Get-WinMintProfileSetupOption {
    param([object]$Settings)

    $raw = [string](Get-WinMintProfileSetting $Settings 'SetupOption' 'Minimal')
    switch -Regex ($raw) {
        '^(Minimal|Slim|Core)$' { return 'Minimal' }
        '^(CopilotPlus|Copilot|Microsoft|MicrosoftComplete)$' { return 'CopilotPlus' }
        default { return 'Minimal' }
    }
}

function Get-WinMintProfileEditionMode {
    param([object]$Settings)

    $raw = [string](Get-WinMintProfileSetting $Settings 'EditionMode' 'TargetLicense')
    switch -Regex ($raw) {
        '^(TargetLicense|Target|License|Auto)$' { return 'TargetLicense' }
        '^(Fixed|Forced|Force)$' { return 'Fixed' }
        default { return 'TargetLicense' }
    }
}

function Get-WinMintProfileDiskMode {
    param([object]$Settings)

    $raw = [string](Get-WinMintProfileSetting $Settings 'DiskMode' '')
    if ([string]::IsNullOrWhiteSpace($raw)) {
        if ([bool](Get-WinMintProfileSetting $Settings 'AutoWipeDisk' $false)) { return 'AutoWipeDisk0' }
        return 'Manual'
    }

    switch -Regex ($raw) {
        '^(Manual|Setup|ExistingPartitions)$' { return 'Manual' }
        '^(AutoWipeDisk0|Auto|WindowsOnly|Wipe)$' { return 'AutoWipeDisk0' }
        '^(DualBootReserved|DualBoot|LinuxReserved)$' { return 'DualBootReserved' }
        default { return 'Manual' }
    }
}

function Get-WinMintProfileDualBootPreset {
    param([object]$Settings)

    $raw = [string](Get-WinMintProfileSetting $Settings 'DualBootPreset' '')
    switch -Regex ($raw) {
        '^(WindowsHeavy|MoreWindows|70/30)$' { return 'WindowsHeavy' }
        '^(Balanced|60/40)$' { return 'Balanced' }
        '^(EvenSplit|Even|50/50)$' { return 'EvenSplit' }
        '^(LinuxHeavy|MoreLinux|40/60)$' { return 'LinuxHeavy' }
        default { return '' }
    }
}

function New-WinMintBuildProfile {
    [CmdletBinding()]
    param(
        [object]$Settings = @{},
        [switch]$IncludeSecrets
    )

    $profileName = [string](Get-WinMintProfileSetting $Settings 'Profile' 'Developer')
    $profileGroups = @(ConvertTo-WinMintProfileGroupArray -Settings $Settings)
    $setupOption = if ($profileGroups -contains 'CopilotPlus') { 'CopilotPlus' } else { Get-WinMintProfileSetupOption -Settings $Settings }
    $editionMode = Get-WinMintProfileEditionMode -Settings $Settings
    $edition = [string](Get-WinMintProfileSetting $Settings 'Edition' '')
    if ($editionMode -eq 'Fixed' -and [string]::IsNullOrWhiteSpace($edition)) {
        $edition = 'Windows 11 Home Single Language'
    }
    $diskMode = Get-WinMintProfileDiskMode -Settings $Settings
    $dualBootPreset = Get-WinMintProfileDualBootPreset -Settings $Settings
    if ($diskMode -eq 'DualBootReserved' -and [string]::IsNullOrWhiteSpace($dualBootPreset)) {
        throw 'DualBootPreset must be explicitly selected when DiskMode is DualBootReserved.'
    }
    $driverSource = [string](Get-WinMintProfileSetting $Settings 'DriverSource' 'None')
    $driverPath = [string](Get-WinMintProfileSetting $Settings 'DriverPath' '')
    $hasExplicitWslDistros = Test-WinMintProfileSettingExists -Settings $Settings -Name 'Wsl2Distros'
    $hasExplicitWslDistro = Test-WinMintProfileSettingExists -Settings $Settings -Name 'Wsl2Distro'
    if ($hasExplicitWslDistros) {
        $wslDistros = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $Settings 'Wsl2Distros' @()))
    }
    elseif ($hasExplicitWslDistro) {
        $wslDistros = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $Settings 'Wsl2Distro' 'None'))
    }
    else {
        $wslDistros = @()
    }

    $password = [string](Get-WinMintProfileSetting $Settings 'Password' '')
    $accountMode = [string](Get-WinMintProfileSetting $Settings 'AccountMode' 'Local')
    if ($accountMode -notin @('Local', 'MicrosoftOobe')) { $accountMode = 'Local' }
    $passwordSet = [bool](Get-WinMintProfileSetting $Settings 'PasswordSet' (-not [string]::IsNullOrWhiteSpace($password)))
    $removeAdvertising = [bool](Get-WinMintProfileSetting $Settings 'RemoveAdvertising' $true)
    $removeGaming = [bool](Get-WinMintProfileSetting $Settings 'RemoveGaming' (-not ($profileGroups -contains 'Gaming')))
    $removeCommunication = [bool](Get-WinMintProfileSetting $Settings 'RemoveCommunication' $true)
    $removeMicrosoftApps = [bool](Get-WinMintProfileSetting $Settings 'RemoveMicrosoftApps' $true)
    $aiPolicy = Get-WinMintProfileAiPolicy -Settings $Settings -SetupOption $setupOption
    $userLocale = Get-WinMintProfileStringSetting -Settings $Settings -Name 'UserLocale' -Default 'en-US'
    $homeLocationGeoId = [int](Get-WinMintProfileSetting $Settings 'HomeLocationGeoId' (Resolve-WinMintRegionGeoId -CultureName $userLocale))
    $effectiveAppxSettings = [ordered]@{
        RemoveAdvertising = $removeAdvertising
        RemoveGaming = $removeGaming
        RemoveCommunication = $removeCommunication
        RemoveMicrosoftApps = $removeMicrosoftApps
    }
    $identity = [ordered]@{
        computerName     = [string](Get-WinMintProfileSetting $Settings 'ComputerName' '')
        accountName      = [string](Get-WinMintProfileSetting $Settings 'AccountName' '')
        accountMode      = $accountMode
        autoLogon        = [bool](Get-WinMintProfileSetting $Settings 'AutoLogon' $false)
        passwordSet      = $passwordSet
        passwordIncluded = [bool]$IncludeSecrets
    }
    if ($IncludeSecrets) { $identity.password = $password }

    [ordered]@{
        schemaVersion = 2
        createdAt = [DateTimeOffset]::Now.ToString('o')
        profileName = $profileName
        profileGroups = @($profileGroups)
        setupOption = $setupOption
        source = [ordered]@{
            isoPath = [string](Get-WinMintProfileSetting $Settings 'ISOPath' '')
            architecture = [string](Get-WinMintProfileSetting $Settings 'Architecture' '')
        }
        target = [ordered]@{
            device = [string](Get-WinMintProfileSetting $Settings 'TargetDevice' 'DifferentPC')
            editionMode = $editionMode
            edition = $edition
            diskMode = $diskMode
            diskLayout = [ordered]@{
                mode = $diskMode
                preset = if ($diskMode -eq 'DualBootReserved') { $dualBootPreset } else { '' }
                roundingGb = 64
                windowsMinimumGb = 256
                windowsRecommendedGb = 384
                linuxMinimumGb = 128
                linuxRecommendedGb = 256
                efiMb = 1024
                msrMb = 16
                recoveryMb = 1024
            }
        }
        identity = $identity
        regional = [ordered]@{
            timeZoneId = [string](Get-WinMintProfileSetting $Settings 'TimeZoneId' '')
            uiLanguage = Get-WinMintProfileStringSetting -Settings $Settings -Name 'UILanguage' -Default 'en-US'
            systemLocale = Get-WinMintProfileStringSetting -Settings $Settings -Name 'SystemLocale' -Default 'en-US'
            uiLanguageFallback = Get-WinMintProfileStringSetting -Settings $Settings -Name 'UILanguageFallback' -Default 'en-US'
            userLocale = $userLocale
            inputLocale = Get-WinMintProfileStringSetting -Settings $Settings -Name 'InputLocale' -Default 'en-US'
            homeLocationGeoId = $homeLocationGeoId
        }
        drivers = [ordered]@{
            source = $driverSource
            path = if ($driverSource -eq 'Custom') { $driverPath } else { '' }
            exportHostDrivers = ($driverSource -eq 'Host')
        }
        desktop = [ordered]@{
            cursorPack = 'Windows11Modern'
            layers = @(Get-WinMintProfileDesktopLayers -Settings $Settings)
        }
        development = [ordered]@{
            editors = @(Get-WinMintProfileEditorIds -Settings $Settings)
            wsl = [ordered]@{
                enabled = ($wslDistros.Count -gt 0)
                distros = @($wslDistros)
            }
        }
        features = [ordered]@{
            launcher = [string](Get-WinMintProfileSetting $Settings 'Launcher' $(if ([bool](Get-WinMintProfileSetting $Settings 'InstallFlowEverything' $false)) { 'FlowEverything' } else { 'None' }))
            liveInstallAudit = [bool](Get-WinMintProfileSetting $Settings 'LiveInstallAudit' $false)
            phoneLink = [bool](Get-WinMintProfileSetting $Settings 'PhoneLink' $false)
        }
        removals = [ordered]@{
            advertising = $removeAdvertising
            gaming = $removeGaming
            communication = $removeCommunication
            microsoftApps = $removeMicrosoftApps
            aiPolicy = $aiPolicy
            effectiveAppx = @(
                Get-WinMintEffectiveAppxRemovalPrefix -Settings $effectiveAppxSettings
            )
        }
        privacy = [ordered]@{
            telemetry = [bool](Get-WinMintProfileSetting $Settings 'PrivTelemetry' $true)
            advertisingId = [bool](Get-WinMintProfileSetting $Settings 'PrivAdvertising' $true)
            location = [bool](Get-WinMintProfileSetting $Settings 'PrivLocation' $true)
            timeline = [bool](Get-WinMintProfileSetting $Settings 'PrivTimeline' $true)
        }
        tweaks = [ordered]@{
            darkMode = [bool](Get-WinMintProfileSetting $Settings 'TweakDarkMode' $true)
            fileExtensions = [bool](Get-WinMintProfileSetting $Settings 'TweakFileExt' $true)
            stickyKeys = [bool](Get-WinMintProfileSetting $Settings 'TweakStickyKeys' $true)
            hardwareBypass = [bool](Get-WinMintProfileSetting $Settings 'TweakHardwareBypass' $false)
            dmaInterop = [bool](Get-WinMintProfileSetting $Settings 'TweakDmaInterop' $true)
        }
    }
}

function New-WinMintBuildProfileFromSettings {
    [CmdletBinding()]
    param(
        [object]$Settings = @{},
        [switch]$IncludeSecrets
    )

    New-WinMintBuildProfile -Settings $Settings -IncludeSecrets:$IncludeSecrets
}

function Save-WinMintBuildProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$BuildProfile,
        [Parameter(Mandatory)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    $json = $BuildProfile | ConvertTo-Json -Depth 16
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, $utf8NoBom)
    return $Path
}

function Test-WinMintProfileProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    Test-WinMintProfileSettingExists -Settings $Object -Name $Name
}

function Test-WinMintBuildProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$BuildProfile)

    $failures = [System.Collections.Generic.List[string]]::new()
    $add = { param([string]$Message) $failures.Add($Message) | Out-Null }
    $require = {
        param([object]$Object, [string]$Path, [string[]]$Names)
        foreach ($name in $Names) {
            if (-not (Test-WinMintProfileProperty -Object $Object -Name $name)) {
                & $add "$Path.$name is required."
            }
        }
    }
    $enum = {
        param([string]$Value, [string]$Path, [string[]]$Allowed)
        if ($Allowed -notcontains $Value) {
            & $add "$Path must be one of: $($Allowed -join ', ')."
        }
    }
    $bool = {
        param([object]$Object, [string]$Name, [string]$Path)
        if (-not (Test-WinMintProfileProperty -Object $Object -Name $Name)) { return }
        $Value = Get-WinMintProfileSetting $Object $Name
        if ($Value -isnot [bool]) { & $add "$Path must be a boolean." }
    }

    & $require $BuildProfile 'profile' @(
        'schemaVersion', 'createdAt', 'profileName', 'source', 'target', 'identity',
        'regional', 'drivers', 'desktop', 'development', 'removals', 'privacy', 'tweaks'
    )
    if ($failures.Count -gt 0) { return [pscustomobject]@{ Passed = $false; Failures = $failures.ToArray() } }

    if ([int]$BuildProfile.schemaVersion -ne 2) { & $add 'profile.schemaVersion must be 2.' }
    if (Test-WinMintProfileProperty -Object $BuildProfile -Name 'profileGroups') {
        $groups = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $BuildProfile 'profileGroups' @()))
        foreach ($group in $groups) { & $enum $group 'profile.profileGroups[]' @('Minimal', 'Developer', 'CopilotPlus', 'Gaming', 'DesktopUI') }
        if ($groups.Count -ne @($groups | Select-Object -Unique).Count) { & $add 'profile.profileGroups must be unique.' }
    }
    if (Test-WinMintProfileProperty -Object $BuildProfile -Name 'setupOption') {
        & $enum ([string](Get-WinMintProfileSetting $BuildProfile 'setupOption' 'Minimal')) 'profile.setupOption' @('Minimal', 'CopilotPlus')
    }
    $source = Get-WinMintProfileSetting $BuildProfile 'source' @{}
    $target = Get-WinMintProfileSetting $BuildProfile 'target' @{}
    $identity = Get-WinMintProfileSetting $BuildProfile 'identity' @{}
    $regional = Get-WinMintProfileSetting $BuildProfile 'regional' @{}
    $drivers = Get-WinMintProfileSetting $BuildProfile 'drivers' @{}
    $desktop = Get-WinMintProfileSetting $BuildProfile 'desktop' @{}
    $development = Get-WinMintProfileSetting $BuildProfile 'development' @{}
    $features = Get-WinMintProfileSetting $BuildProfile 'features' @{}
    $removals = Get-WinMintProfileSetting $BuildProfile 'removals' @{}
    $privacy = Get-WinMintProfileSetting $BuildProfile 'privacy' @{}
    $tweaks = Get-WinMintProfileSetting $BuildProfile 'tweaks' @{}

    & $require $source 'profile.source' @('isoPath', 'architecture')
    & $enum ([string](Get-WinMintProfileSetting $source 'architecture' '')) 'profile.source.architecture' @('amd64', 'arm64', 'x86', '')
    & $require $target 'profile.target' @('device', 'editionMode', 'edition', 'diskMode')
    & $enum ([string](Get-WinMintProfileSetting $target 'device' '')) 'profile.target.device' @('ThisPC', 'DifferentPC')
    & $enum ([string](Get-WinMintProfileSetting $target 'editionMode' '')) 'profile.target.editionMode' @('TargetLicense', 'Fixed')
    $diskMode = [string](Get-WinMintProfileSetting $target 'diskMode' '')
    & $enum $diskMode 'profile.target.diskMode' @('Manual', 'AutoWipeDisk0', 'DualBootReserved')
    if (Test-WinMintProfileProperty -Object $target -Name 'diskLayout') {
        $diskLayout = Get-WinMintProfileSetting $target 'diskLayout' @{}
        & $require $diskLayout 'profile.target.diskLayout' @(
            'mode', 'preset', 'roundingGb', 'windowsMinimumGb', 'windowsRecommendedGb',
            'linuxMinimumGb', 'linuxRecommendedGb', 'efiMb', 'msrMb', 'recoveryMb'
        )
        & $enum ([string](Get-WinMintProfileSetting $diskLayout 'mode' '')) 'profile.target.diskLayout.mode' @('Manual', 'AutoWipeDisk0', 'DualBootReserved')
        & $enum ([string](Get-WinMintProfileSetting $diskLayout 'preset' '')) 'profile.target.diskLayout.preset' @('', 'WindowsHeavy', 'Balanced', 'EvenSplit', 'LinuxHeavy')
        if ([string](Get-WinMintProfileSetting $diskLayout 'mode' '') -ne $diskMode) {
            & $add 'profile.target.diskLayout.mode must match profile.target.diskMode.'
        }
        $diskLayoutPreset = [string](Get-WinMintProfileSetting $diskLayout 'preset' '')
        if ($diskMode -eq 'DualBootReserved' -and [string]::IsNullOrWhiteSpace($diskLayoutPreset)) {
            & $add 'profile.target.diskLayout.preset is required when profile.target.diskMode is DualBootReserved.'
        }
        elseif ($diskMode -ne 'DualBootReserved' -and -not [string]::IsNullOrWhiteSpace($diskLayoutPreset)) {
            & $add 'profile.target.diskLayout.preset must be empty unless profile.target.diskMode is DualBootReserved.'
        }
        foreach ($name in @('roundingGb', 'windowsMinimumGb', 'windowsRecommendedGb', 'linuxMinimumGb', 'linuxRecommendedGb', 'efiMb', 'msrMb', 'recoveryMb')) {
            $value = Get-WinMintProfileSetting $diskLayout $name $null
            if ($value -isnot [int] -and $value -isnot [long]) { & $add "profile.target.diskLayout.$name must be an integer." }
        }
    }

    & $require $identity 'profile.identity' @('computerName', 'accountName', 'autoLogon', 'passwordSet', 'passwordIncluded')
    if (Test-WinMintProfileProperty -Object $identity -Name 'accountMode') {
        & $enum ([string](Get-WinMintProfileSetting $identity 'accountMode' 'Local')) 'profile.identity.accountMode' @('Local', 'MicrosoftOobe')
    }
    & $bool $identity 'autoLogon' 'profile.identity.autoLogon'
    & $bool $identity 'passwordSet' 'profile.identity.passwordSet'
    & $bool $identity 'passwordIncluded' 'profile.identity.passwordIncluded'
    if ((Get-WinMintProfileSetting $identity 'passwordIncluded' $false) -and
        -not (Test-WinMintProfileProperty -Object $identity -Name 'password')) {
        & $add 'profile.identity.password is required when passwordIncluded is true.'
    }

    & $require $regional 'profile.regional' @('timeZoneId', 'uiLanguage', 'systemLocale', 'uiLanguageFallback', 'userLocale', 'inputLocale')
    $homeLocationGeoId = Get-WinMintProfileSetting $regional 'homeLocationGeoId' $null
    if ($null -ne $homeLocationGeoId -and $homeLocationGeoId -isnot [int] -and $homeLocationGeoId -isnot [long]) {
        & $add 'profile.regional.homeLocationGeoId must be an integer.'
    }
    & $require $drivers 'profile.drivers' @('source', 'path', 'exportHostDrivers')
    $driverSource = [string](Get-WinMintProfileSetting $drivers 'source' '')
    & $enum $driverSource 'profile.drivers.source' @('None', 'Host', 'Custom')
    & $bool $drivers 'exportHostDrivers' 'profile.drivers.exportHostDrivers'
    $exportHostDrivers = Get-WinMintProfileSetting $drivers 'exportHostDrivers' $null
    if ($exportHostDrivers -is [bool]) {
        if ($driverSource -eq 'Host' -and -not $exportHostDrivers) {
            & $add 'profile.drivers.exportHostDrivers must be true when profile.drivers.source is Host.'
        }
        elseif ($driverSource -ne 'Host' -and $exportHostDrivers) {
            & $add 'profile.drivers.exportHostDrivers must be false unless profile.drivers.source is Host.'
        }
    }

    & $require $desktop 'profile.desktop' @('cursorPack', 'layers')
    & $enum ([string](Get-WinMintProfileSetting $desktop 'cursorPack' '')) 'profile.desktop.cursorPack' @('Windows11Modern')
    $layers = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $desktop 'layers' @()))
    foreach ($layer in $layers) { & $enum $layer 'profile.desktop.layers[]' @('standard', 'windhawk', 'yasb', 'komorebi') }
    if ($layers.Count -ne @($layers | Select-Object -Unique).Count) { & $add 'profile.desktop.layers must be unique.' }

    & $require $development 'profile.development' @('editors', 'wsl')
    $wsl = Get-WinMintProfileSetting $development 'wsl' @{}
    & $require $wsl 'profile.development.wsl' @('enabled', 'distros')
    & $bool $wsl 'enabled' 'profile.development.wsl.enabled'

    if (Test-WinMintProfileProperty -Object $BuildProfile -Name 'features') {
        & $require $features 'profile.features' @('launcher')
        & $enum ([string](Get-WinMintProfileSetting $features 'launcher' '')) 'profile.features.launcher' @('None', 'FlowEverything', 'Raycast')
        if (Test-WinMintProfileProperty -Object $features -Name 'liveInstallAudit') {
            & $bool $features 'liveInstallAudit' 'profile.features.liveInstallAudit'
        }
        if (Test-WinMintProfileProperty -Object $features -Name 'phoneLink') {
            & $bool $features 'phoneLink' 'profile.features.phoneLink'
        }
        if (Test-WinMintProfileProperty -Object $features -Name 'flowEverything') {
            & $bool $features 'flowEverything' 'profile.features.flowEverything'
        }
    }

    & $require $removals 'profile.removals' @('advertising', 'gaming', 'communication', 'microsoftApps', 'aiPolicy')
    foreach ($name in @('advertising', 'gaming', 'communication', 'microsoftApps')) {
        & $bool $removals $name "profile.removals.$name"
    }
    if (Test-WinMintProfileProperty -Object $removals -Name 'aiPolicy') {
        & $enum ([string](Get-WinMintProfileSetting $removals 'aiPolicy' 'Core')) 'profile.removals.aiPolicy' @('Core', 'ServiceableFull', 'AggressiveExperimental')
        if ([string](Get-WinMintProfileSetting $removals 'aiPolicy' 'Core') -eq 'AggressiveExperimental' -and
            [string]$env:WINMINT_ENABLE_EXPERIMENTAL_AI_REMOVAL -ne '1') {
            & $add 'profile.removals.aiPolicy AggressiveExperimental requires WINMINT_ENABLE_EXPERIMENTAL_AI_REMOVAL=1.'
        }
    }
    & $require $privacy 'profile.privacy' @('telemetry', 'advertisingId', 'location', 'timeline')
    foreach ($name in @('telemetry', 'advertisingId', 'location', 'timeline')) {
        & $bool $privacy $name "profile.privacy.$name"
    }
    & $require $tweaks 'profile.tweaks' @('darkMode', 'fileExtensions', 'stickyKeys')
    foreach ($name in @('darkMode', 'fileExtensions', 'stickyKeys', 'hardwareBypass', 'dmaInterop')) {
        & $bool $tweaks $name "profile.tweaks.$name"
    }

    [pscustomobject]@{ Passed = ($failures.Count -eq 0); Failures = $failures.ToArray() }
}

function Assert-WinMintBuildProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$BuildProfile)

    $result = Test-WinMintBuildProfile -BuildProfile $BuildProfile
    if (-not $result.Passed) {
        throw "Build profile validation failed:`n - $($result.Failures -join "`n - ")"
    }
}
