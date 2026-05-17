#Requires -Version 7.3

function Get-WinWSProfileSetting {
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

function Test-WinWSProfileSettingExists {
    param(
        [object]$Settings,
        [string]$Name
    )

    if ($null -eq $Settings) { return $false }
    if ($Settings -is [System.Collections.IDictionary]) { return $Settings.Contains($Name) }
    return $null -ne $Settings.PSObject.Properties[$Name]
}

function ConvertTo-WinWSProfileStringArray {
    param($Value)

    @(
        @($Value) |
            ForEach-Object { ([string]$_) -split ',' } |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne 'None' } |
            Select-Object -Unique
    )
}

function Resolve-WinWSRegionGeoId {
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
    try {
        return [int](Get-WinHomeLocation).GeoId
    }
    catch {
        return $Default
    }
}

function Resolve-WinWSDmaInteropSetupRegion {
    $preferred = @{ Country = 'Germany'; Culture = 'de-DE'; FallbackGeoId = 94 }
    $fallback = @{ Country = 'Ireland'; Culture = 'en-IE'; FallbackGeoId = 68 }

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

function ConvertTo-WinWSProfileGroupArray {
    param([object]$Settings)

    $rawGroups = @(ConvertTo-WinWSProfileStringArray (Get-WinWSProfileSetting $Settings 'ProfileGroups' @()))
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

    $setupOption = Get-WinWSProfileSetupOption -Settings $Settings
    if ($setupOption -eq 'CopilotPlus') { $groups.Add('CopilotPlus') | Out-Null }

    if ($groups.Count -eq 0) { $groups.Add('Minimal') | Out-Null }
    return @($groups.ToArray() | Select-Object -Unique)
}

function Test-WinWSProfileGroup {
    param(
        [object]$Settings,
        [Parameter(Mandatory)][string]$Group
    )

    return @(ConvertTo-WinWSProfileGroupArray -Settings $Settings) -contains $Group
}

function Get-WinWSProfileEditorIds {
    param([object]$Settings)

    $editors = @(ConvertTo-WinWSProfileStringArray (Get-WinWSProfileSetting $Settings 'Editors' @()))
    if ($editors.Count -gt 0 -or (Test-WinWSProfileSettingExists -Settings $Settings -Name 'Editors')) {
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
            Where-Object { Test-WinWSProfileSettingExists -Settings $Settings -Name $_[0] }
    ).Count -gt 0
    $editors = @(
        $editorFlags |
            Where-Object { [bool](Get-WinWSProfileSetting $Settings $_[0] $false) } |
            ForEach-Object { $_[1] }
    )
    if ($editors.Count -gt 0 -or $hasExplicitEditorFlag) { return $editors }

    @()
}

function Get-WinWSProfileDesktopLayers {
    param([object]$Settings)

    $layers = [System.Collections.Generic.List[string]]::new()
    if ([bool](Get-WinWSProfileSetting $Settings 'DesktopUiDefault' $false)) {
        $layers.Add('windhawk')
        $layers.Add('yasb')
        $layers.Add('komorebi')
    }
    if ([bool](Get-WinWSProfileSetting $Settings 'InstallWindhawk' $false)) { $layers.Add('windhawk') }
    if ([bool](Get-WinWSProfileSetting $Settings 'InstallYasb' $false)) { $layers.Add('yasb') }
    if ([bool](Get-WinWSProfileSetting $Settings 'InstallKomorebi' $false)) { $layers.Add('komorebi') }
    if ($layers.Count -eq 0) { $layers.Add('standard') }
    return @($layers.ToArray() | Select-Object -Unique)
}

function Get-WinWSAppxBloatwareCategories {
    [ordered]@{
        'Always remove'    = @(
            'Microsoft.GetHelp', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.WindowsFeedbackHub',
            'Microsoft.549981C3F5F10', 'MicrosoftCorporationII.MicrosoftFamily',
            'Microsoft.StartExperiencesApp', 'Microsoft.BingSearch', 'Microsoft.WindowsCalculator',
            'Microsoft.BingWeather', 'Microsoft.Whiteboard', 'Microsoft.Microsoft3DViewer',
            'Microsoft.MixedReality.Portal', 'MicrosoftCorporationII.QuickAssist',
            'Microsoft.WindowsMaps', 'Microsoft.Todos',
            'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo',
            'Microsoft.Office.OneNote',
            'Microsoft.RemoteDesktop', 'Microsoft.RemoteDesktopPreview',
            # OEM/trial provisioned junk (best-effort; names vary by SKU — no-op if absent)
            'McAfee', 'NortonLifeLock', 'NortonSecurity', 'ExpressVPN', 'Surfshark', 'SurfsharkVPN',
            'AVGTechnologies', 'AvastSoftware', 'KasperskyLab', 'DolbyLaboratories', 'Piriform.CCleaner'
        )
        'Advertising & AI' = @(
            'Microsoft.BingNews', 'Microsoft.Windows.DevHome',
            'MicrosoftWindows.Client.WebExperience', 'Microsoft.Copilot'
        )
        'Gaming (Xbox)'    = @(
            'Microsoft.GamingApp', 'Microsoft.XboxApp', 'Microsoft.XboxGameOverlay',
            'Microsoft.XboxGamingOverlay', 'Microsoft.XboxIdentityProvider',
            'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.Xbox.TCUI'
        )
        'Communication'    = @(
            'MSTeams', 'MicrosoftTeams', 'Microsoft.People', 'Microsoft.windowscommunicationsapps'
        )
        'Microsoft apps'   = @(
            'Microsoft.OutlookForWindows', 'Microsoft.PowerAutomateDesktop',
            'Microsoft.MicrosoftSolitaireCollection', 'Clipchamp.Clipchamp'
        )
    }
}

function Get-WinWSEffectiveAppxRemovalPrefix {
    param([object]$Settings)

    $categories = Get-WinWSAppxBloatwareCategories
    $effective = [System.Collections.Generic.List[string]]::new()
    $effective.AddRange([string[]]$categories['Always remove'])
    if ([bool](Get-WinWSProfileSetting $Settings 'RemoveAdvertising' $true)) {
        $effective.AddRange([string[]]$categories['Advertising & AI'])
    }
    if ([bool](Get-WinWSProfileSetting $Settings 'RemoveGaming' $true)) {
        $effective.AddRange([string[]]$categories['Gaming (Xbox)'])
    }
    if ([bool](Get-WinWSProfileSetting $Settings 'RemoveCommunication' $true)) {
        $effective.AddRange([string[]]$categories['Communication'])
    }
    if ([bool](Get-WinWSProfileSetting $Settings 'RemoveMicrosoftApps' $true)) {
        $effective.AddRange([string[]]$categories['Microsoft apps'])
    }
    return @($effective.ToArray() | Sort-Object -Unique)
}

function Get-WinWSProfileAppxRemovalPrefix {
    param([object]$Removals)

    $settings = [ordered]@{
        RemoveAdvertising = [bool](Get-WinWSProfileSetting $Removals 'advertising' $true)
        RemoveGaming = [bool](Get-WinWSProfileSetting $Removals 'gaming' $true)
        RemoveCommunication = [bool](Get-WinWSProfileSetting $Removals 'communication' $true)
        RemoveMicrosoftApps = [bool](Get-WinWSProfileSetting $Removals 'microsoftApps' $true)
    }
    Get-WinWSEffectiveAppxRemovalPrefix -Settings $settings
}

function Get-WinWSProfileSetupOption {
    param([object]$Settings)

    $raw = [string](Get-WinWSProfileSetting $Settings 'SetupOption' 'Minimal')
    switch -Regex ($raw) {
        '^(Minimal|Slim|Core)$' { return 'Minimal' }
        '^(CopilotPlus|Copilot|Microsoft|MicrosoftComplete)$' { return 'CopilotPlus' }
        default { return 'Minimal' }
    }
}

function Get-WinWSProfileEditionMode {
    param([object]$Settings)

    $raw = [string](Get-WinWSProfileSetting $Settings 'EditionMode' 'TargetLicense')
    switch -Regex ($raw) {
        '^(TargetLicense|Target|License|Auto)$' { return 'TargetLicense' }
        '^(Fixed|Forced|Force)$' { return 'Fixed' }
        default { return 'TargetLicense' }
    }
}

function Get-WinWSProfileDiskMode {
    param([object]$Settings)

    $raw = [string](Get-WinWSProfileSetting $Settings 'DiskMode' '')
    if ([string]::IsNullOrWhiteSpace($raw)) {
        if ([bool](Get-WinWSProfileSetting $Settings 'AutoWipeDisk' $false)) { return 'AutoWipeDisk0' }
        return 'Manual'
    }

    switch -Regex ($raw) {
        '^(Manual|Setup|ExistingPartitions)$' { return 'Manual' }
        '^(AutoWipeDisk0|Auto|WindowsOnly|Wipe)$' { return 'AutoWipeDisk0' }
        '^(DualBootReserved|DualBoot|LinuxReserved)$' { return 'DualBootReserved' }
        default { return 'Manual' }
    }
}

function Get-WinWSProfileDualBootPreset {
    param([object]$Settings)

    $raw = [string](Get-WinWSProfileSetting $Settings 'DualBootPreset' '')
    switch -Regex ($raw) {
        '^(WindowsHeavy|MoreWindows|70/30)$' { return 'WindowsHeavy' }
        '^(Balanced|60/40)$' { return 'Balanced' }
        '^(EvenSplit|Even|50/50)$' { return 'EvenSplit' }
        '^(LinuxHeavy|MoreLinux|40/60)$' { return 'LinuxHeavy' }
        default { return '' }
    }
}

function New-WinWSBuildProfile {
    [CmdletBinding()]
    param(
        [object]$Settings = @{},
        [switch]$IncludeSecrets
    )

    $profileName = [string](Get-WinWSProfileSetting $Settings 'Profile' 'Developer')
    $profileGroups = @(ConvertTo-WinWSProfileGroupArray -Settings $Settings)
    $setupOption = if ($profileGroups -contains 'CopilotPlus') { 'CopilotPlus' } else { Get-WinWSProfileSetupOption -Settings $Settings }
    $editionMode = Get-WinWSProfileEditionMode -Settings $Settings
    $diskMode = Get-WinWSProfileDiskMode -Settings $Settings
    $dualBootPreset = Get-WinWSProfileDualBootPreset -Settings $Settings
    if ($diskMode -eq 'DualBootReserved' -and [string]::IsNullOrWhiteSpace($dualBootPreset)) {
        throw 'DualBootPreset must be explicitly selected when DiskMode is DualBootReserved.'
    }
    $driverSource = [string](Get-WinWSProfileSetting $Settings 'DriverSource' 'None')
    $driverPath = [string](Get-WinWSProfileSetting $Settings 'DriverPath' '')
    $hasExplicitWslDistros = Test-WinWSProfileSettingExists -Settings $Settings -Name 'Wsl2Distros'
    $hasExplicitWslDistro = Test-WinWSProfileSettingExists -Settings $Settings -Name 'Wsl2Distro'
    if ($hasExplicitWslDistros) {
        $wslDistros = @(ConvertTo-WinWSProfileStringArray (Get-WinWSProfileSetting $Settings 'Wsl2Distros' @()))
    }
    elseif ($hasExplicitWslDistro) {
        $wslDistros = @(ConvertTo-WinWSProfileStringArray (Get-WinWSProfileSetting $Settings 'Wsl2Distro' 'None'))
    }
    else {
        $wslDistros = @()
    }

    $password = [string](Get-WinWSProfileSetting $Settings 'Password' '')
    $accountMode = [string](Get-WinWSProfileSetting $Settings 'AccountMode' 'Local')
    if ($accountMode -notin @('Local', 'MicrosoftOobe')) { $accountMode = 'Local' }
    $passwordSet = [bool](Get-WinWSProfileSetting $Settings 'PasswordSet' (-not [string]::IsNullOrWhiteSpace($password)))
    $removeAdvertising = [bool](Get-WinWSProfileSetting $Settings 'RemoveAdvertising' $true)
    $removeGaming = [bool](Get-WinWSProfileSetting $Settings 'RemoveGaming' (-not ($profileGroups -contains 'Gaming')))
    $removeCommunication = [bool](Get-WinWSProfileSetting $Settings 'RemoveCommunication' $true)
    $removeMicrosoftApps = [bool](Get-WinWSProfileSetting $Settings 'RemoveMicrosoftApps' $true)
    $userLocale = [string](Get-WinWSProfileSetting $Settings 'UserLocale' '')
    $homeLocationGeoId = [int](Get-WinWSProfileSetting $Settings 'HomeLocationGeoId' (Resolve-WinWSRegionGeoId -CultureName $userLocale))
    $effectiveAppxSettings = [ordered]@{
        RemoveAdvertising = $removeAdvertising
        RemoveGaming = $removeGaming
        RemoveCommunication = $removeCommunication
        RemoveMicrosoftApps = $removeMicrosoftApps
    }
    $identity = [ordered]@{
        computerName     = [string](Get-WinWSProfileSetting $Settings 'ComputerName' '')
        accountName      = [string](Get-WinWSProfileSetting $Settings 'AccountName' '')
        accountMode      = $accountMode
        autoLogon        = [bool](Get-WinWSProfileSetting $Settings 'AutoLogon' $false)
        passwordSet      = $passwordSet
        passwordIncluded = [bool]$IncludeSecrets
    }
    if ($IncludeSecrets) { $identity.password = $password }

    [ordered]@{
        schemaVersion = 1
        createdAt = [DateTimeOffset]::Now.ToString('o')
        profileName = $profileName
        profileGroups = @($profileGroups)
        setupOption = $setupOption
        source = [ordered]@{
            isoPath = [string](Get-WinWSProfileSetting $Settings 'ISOPath' '')
            architecture = [string](Get-WinWSProfileSetting $Settings 'Architecture' '')
        }
        target = [ordered]@{
            device = [string](Get-WinWSProfileSetting $Settings 'TargetDevice' 'DifferentPC')
            editionMode = $editionMode
            edition = [string](Get-WinWSProfileSetting $Settings 'Edition' '')
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
            timeZoneId = [string](Get-WinWSProfileSetting $Settings 'TimeZoneId' '')
            uiLanguage = [string](Get-WinWSProfileSetting $Settings 'UILanguage' '')
            systemLocale = [string](Get-WinWSProfileSetting $Settings 'SystemLocale' '')
            uiLanguageFallback = [string](Get-WinWSProfileSetting $Settings 'UILanguageFallback' '')
            userLocale = $userLocale
            inputLocale = [string](Get-WinWSProfileSetting $Settings 'InputLocale' '')
            homeLocationGeoId = $homeLocationGeoId
        }
        drivers = [ordered]@{
            source = $driverSource
            path = if ($driverSource -eq 'Custom') { $driverPath } else { '' }
            exportHostDrivers = ($driverSource -eq 'Host')
        }
        desktop = [ordered]@{
            cursorPack = 'BreezeXLight'
            layers = @(Get-WinWSProfileDesktopLayers -Settings $Settings)
        }
        development = [ordered]@{
            editors = @(Get-WinWSProfileEditorIds -Settings $Settings)
            wsl = [ordered]@{
                enabled = ($wslDistros.Count -gt 0)
                distros = @($wslDistros)
            }
        }
        removals = [ordered]@{
            advertising = $removeAdvertising
            gaming = $removeGaming
            communication = $removeCommunication
            microsoftApps = $removeMicrosoftApps
            effectiveAppx = @(
                $effectiveAppx = @(Get-WinWSEffectiveAppxRemovalPrefix -Settings $effectiveAppxSettings)
                if ($setupOption -eq 'CopilotPlus') {
                    $effectiveAppx | Where-Object { $_ -notin @('Microsoft.Copilot', 'MicrosoftWindows.Client.WebExperience') }
                } else {
                    $effectiveAppx
                }
            )
        }
        privacy = [ordered]@{
            telemetry = [bool](Get-WinWSProfileSetting $Settings 'PrivTelemetry' $true)
            advertisingId = [bool](Get-WinWSProfileSetting $Settings 'PrivAdvertising' $true)
            location = [bool](Get-WinWSProfileSetting $Settings 'PrivLocation' $false)
            timeline = [bool](Get-WinWSProfileSetting $Settings 'PrivTimeline' $true)
        }
        tweaks = [ordered]@{
            darkMode = [bool](Get-WinWSProfileSetting $Settings 'TweakDarkMode' $true)
            fileExtensions = [bool](Get-WinWSProfileSetting $Settings 'TweakFileExt' $true)
            stickyKeys = [bool](Get-WinWSProfileSetting $Settings 'TweakStickyKeys' $true)
            hardwareBypass = [bool](Get-WinWSProfileSetting $Settings 'TweakHardwareBypass' $false)
        }
    }
}

function Save-WinWSBuildProfile {
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

function Test-WinWSProfileProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    Test-WinWSProfileSettingExists -Settings $Object -Name $Name
}

function Test-WinWSBuildProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$BuildProfile)

    $failures = [System.Collections.Generic.List[string]]::new()
    $add = { param([string]$Message) $failures.Add($Message) | Out-Null }
    $require = {
        param([object]$Object, [string]$Path, [string[]]$Names)
        foreach ($name in $Names) {
            if (-not (Test-WinWSProfileProperty -Object $Object -Name $name)) {
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
        if (-not (Test-WinWSProfileProperty -Object $Object -Name $Name)) { return }
        $Value = Get-WinWSProfileSetting $Object $Name
        if ($Value -isnot [bool]) { & $add "$Path must be a boolean." }
    }

    & $require $BuildProfile 'profile' @(
        'schemaVersion', 'createdAt', 'profileName', 'source', 'target', 'identity',
        'regional', 'drivers', 'desktop', 'development', 'removals', 'privacy', 'tweaks'
    )
    if ($failures.Count -gt 0) { return [pscustomobject]@{ Passed = $false; Failures = $failures.ToArray() } }

    if ([int]$BuildProfile.schemaVersion -lt 1) { & $add 'profile.schemaVersion must be >= 1.' }
    if (Test-WinWSProfileProperty -Object $BuildProfile -Name 'profileGroups') {
        $groups = @(ConvertTo-WinWSProfileStringArray (Get-WinWSProfileSetting $BuildProfile 'profileGroups' @()))
        foreach ($group in $groups) { & $enum $group 'profile.profileGroups[]' @('Minimal', 'Developer', 'CopilotPlus', 'Gaming', 'DesktopUI') }
        if ($groups.Count -ne @($groups | Select-Object -Unique).Count) { & $add 'profile.profileGroups must be unique.' }
    }
    if (Test-WinWSProfileProperty -Object $BuildProfile -Name 'setupOption') {
        & $enum ([string](Get-WinWSProfileSetting $BuildProfile 'setupOption' 'Minimal')) 'profile.setupOption' @('Minimal', 'CopilotPlus')
    }
    $source = Get-WinWSProfileSetting $BuildProfile 'source' @{}
    $target = Get-WinWSProfileSetting $BuildProfile 'target' @{}
    $identity = Get-WinWSProfileSetting $BuildProfile 'identity' @{}
    $regional = Get-WinWSProfileSetting $BuildProfile 'regional' @{}
    $drivers = Get-WinWSProfileSetting $BuildProfile 'drivers' @{}
    $desktop = Get-WinWSProfileSetting $BuildProfile 'desktop' @{}
    $development = Get-WinWSProfileSetting $BuildProfile 'development' @{}
    $removals = Get-WinWSProfileSetting $BuildProfile 'removals' @{}
    $privacy = Get-WinWSProfileSetting $BuildProfile 'privacy' @{}
    $tweaks = Get-WinWSProfileSetting $BuildProfile 'tweaks' @{}

    & $require $source 'profile.source' @('isoPath', 'architecture')
    & $enum ([string](Get-WinWSProfileSetting $source 'architecture' '')) 'profile.source.architecture' @('amd64', 'arm64', 'x86', '')
    & $require $target 'profile.target' @('device', 'editionMode', 'edition', 'diskMode')
    & $enum ([string](Get-WinWSProfileSetting $target 'device' '')) 'profile.target.device' @('ThisPC', 'DifferentPC')
    & $enum ([string](Get-WinWSProfileSetting $target 'editionMode' '')) 'profile.target.editionMode' @('TargetLicense', 'Fixed')
    $diskMode = [string](Get-WinWSProfileSetting $target 'diskMode' '')
    & $enum $diskMode 'profile.target.diskMode' @('Manual', 'AutoWipeDisk0', 'DualBootReserved')
    if (Test-WinWSProfileProperty -Object $target -Name 'diskLayout') {
        $diskLayout = Get-WinWSProfileSetting $target 'diskLayout' @{}
        & $require $diskLayout 'profile.target.diskLayout' @(
            'mode', 'preset', 'roundingGb', 'windowsMinimumGb', 'windowsRecommendedGb',
            'linuxMinimumGb', 'linuxRecommendedGb', 'efiMb', 'msrMb', 'recoveryMb'
        )
        & $enum ([string](Get-WinWSProfileSetting $diskLayout 'mode' '')) 'profile.target.diskLayout.mode' @('Manual', 'AutoWipeDisk0', 'DualBootReserved')
        & $enum ([string](Get-WinWSProfileSetting $diskLayout 'preset' '')) 'profile.target.diskLayout.preset' @('', 'WindowsHeavy', 'Balanced', 'EvenSplit', 'LinuxHeavy')
        if ([string](Get-WinWSProfileSetting $diskLayout 'mode' '') -ne $diskMode) {
            & $add 'profile.target.diskLayout.mode must match profile.target.diskMode.'
        }
        $diskLayoutPreset = [string](Get-WinWSProfileSetting $diskLayout 'preset' '')
        if ($diskMode -eq 'DualBootReserved' -and [string]::IsNullOrWhiteSpace($diskLayoutPreset)) {
            & $add 'profile.target.diskLayout.preset is required when profile.target.diskMode is DualBootReserved.'
        }
        elseif ($diskMode -ne 'DualBootReserved' -and -not [string]::IsNullOrWhiteSpace($diskLayoutPreset)) {
            & $add 'profile.target.diskLayout.preset must be empty unless profile.target.diskMode is DualBootReserved.'
        }
        foreach ($name in @('roundingGb', 'windowsMinimumGb', 'windowsRecommendedGb', 'linuxMinimumGb', 'linuxRecommendedGb', 'efiMb', 'msrMb', 'recoveryMb')) {
            $value = Get-WinWSProfileSetting $diskLayout $name $null
            if ($value -isnot [int] -and $value -isnot [long]) { & $add "profile.target.diskLayout.$name must be an integer." }
        }
    }

    & $require $identity 'profile.identity' @('computerName', 'accountName', 'autoLogon', 'passwordSet', 'passwordIncluded')
    if (Test-WinWSProfileProperty -Object $identity -Name 'accountMode') {
        & $enum ([string](Get-WinWSProfileSetting $identity 'accountMode' 'Local')) 'profile.identity.accountMode' @('Local', 'MicrosoftOobe')
    }
    & $bool $identity 'autoLogon' 'profile.identity.autoLogon'
    & $bool $identity 'passwordSet' 'profile.identity.passwordSet'
    & $bool $identity 'passwordIncluded' 'profile.identity.passwordIncluded'
    if ((Get-WinWSProfileSetting $identity 'passwordIncluded' $false) -and
        -not (Test-WinWSProfileProperty -Object $identity -Name 'password')) {
        & $add 'profile.identity.password is required when passwordIncluded is true.'
    }

    & $require $regional 'profile.regional' @('timeZoneId', 'uiLanguage', 'systemLocale', 'userLocale', 'inputLocale')
    $homeLocationGeoId = Get-WinWSProfileSetting $regional 'homeLocationGeoId' $null
    if ($null -ne $homeLocationGeoId -and $homeLocationGeoId -isnot [int] -and $homeLocationGeoId -isnot [long]) {
        & $add 'profile.regional.homeLocationGeoId must be an integer.'
    }
    & $require $drivers 'profile.drivers' @('source', 'path', 'exportHostDrivers')
    $driverSource = [string](Get-WinWSProfileSetting $drivers 'source' '')
    & $enum $driverSource 'profile.drivers.source' @('None', 'Host', 'Custom')
    & $bool $drivers 'exportHostDrivers' 'profile.drivers.exportHostDrivers'
    $exportHostDrivers = Get-WinWSProfileSetting $drivers 'exportHostDrivers' $null
    if ($exportHostDrivers -is [bool]) {
        if ($driverSource -eq 'Host' -and -not $exportHostDrivers) {
            & $add 'profile.drivers.exportHostDrivers must be true when profile.drivers.source is Host.'
        }
        elseif ($driverSource -ne 'Host' -and $exportHostDrivers) {
            & $add 'profile.drivers.exportHostDrivers must be false unless profile.drivers.source is Host.'
        }
    }

    & $require $desktop 'profile.desktop' @('cursorPack', 'layers')
    & $enum ([string](Get-WinWSProfileSetting $desktop 'cursorPack' '')) 'profile.desktop.cursorPack' @('BreezeXLight')
    $layers = @(ConvertTo-WinWSProfileStringArray (Get-WinWSProfileSetting $desktop 'layers' @()))
    foreach ($layer in $layers) { & $enum $layer 'profile.desktop.layers[]' @('standard', 'windhawk', 'yasb', 'komorebi') }
    if ($layers.Count -ne @($layers | Select-Object -Unique).Count) { & $add 'profile.desktop.layers must be unique.' }

    & $require $development 'profile.development' @('editors', 'wsl')
    $wsl = Get-WinWSProfileSetting $development 'wsl' @{}
    & $require $wsl 'profile.development.wsl' @('enabled', 'distros')
    & $bool $wsl 'enabled' 'profile.development.wsl.enabled'

    & $require $removals 'profile.removals' @('advertising', 'gaming', 'communication', 'microsoftApps')
    foreach ($name in @('advertising', 'gaming', 'communication', 'microsoftApps')) {
        & $bool $removals $name "profile.removals.$name"
    }
    & $require $privacy 'profile.privacy' @('telemetry', 'advertisingId', 'location', 'timeline')
    foreach ($name in @('telemetry', 'advertisingId', 'location', 'timeline')) {
        & $bool $privacy $name "profile.privacy.$name"
    }
    & $require $tweaks 'profile.tweaks' @('darkMode', 'fileExtensions', 'stickyKeys')
    foreach ($name in @('darkMode', 'fileExtensions', 'stickyKeys', 'hardwareBypass')) {
        & $bool $tweaks $name "profile.tweaks.$name"
    }

    [pscustomobject]@{ Passed = ($failures.Count -eq 0); Failures = $failures.ToArray() }
}

function Assert-WinWSBuildProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$BuildProfile)

    $result = Test-WinWSBuildProfile -BuildProfile $BuildProfile
    if (-not $result.Passed) {
        throw "Build profile validation failed:`n - $($result.Failures -join "`n - ")"
    }
}
