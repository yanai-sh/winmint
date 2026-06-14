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

function Resolve-WinMintSecondaryInputLanguages {
    # Resolve the regional.secondaryInputLanguages setting to a concrete list of BCP-47 input
    # languages (keyboards) to add, with the display language excluded so it always stays the
    # primary. Accepts:
    #   'Auto' (default) -> replicate the BUILD HOST's current keyboard config (Get-WinUserLanguageList)
    #   'None' or []     -> add no secondary input languages
    #   array of tags    -> use exactly those (e.g. @('he-IL'))
    param(
        $Raw,
        [string]$UILanguage = 'en-US'
    )
    $uiPrimary = (([string]$UILanguage) -split '-')[0].ToLowerInvariant()

    # Gather the candidate tags from the requested mode.
    $tags = @()
    if ($null -ne $Raw -and $Raw -isnot [string] -and $Raw -is [System.Collections.IEnumerable]) {
        $tags = @($Raw)                                  # explicit array
    }
    else {
        $mode = [string]$Raw
        if ([string]::IsNullOrWhiteSpace($mode)) { $mode = 'Auto' }
        if ($mode -ieq 'None') { return @() }
        if ($mode -ieq 'Auto') {
            # Read the build host's preferred-language list straight from the registry. This is
            # the authoritative, context-stable source: Get-WinUserLanguageList is flaky in
            # non-interactive/elevated build contexts (it can return a single blank entry),
            # whereas HKCU\Control Panel\International\User Profile\Languages is consistent
            # (and an elevated build runs under the same user's HKCU).
            try {
                $up = Get-ItemProperty 'HKCU:\Control Panel\International\User Profile' -Name 'Languages' -ErrorAction Stop
                $tags = @($up.Languages)
            }
            catch { return @() }
        }
        else { $tags = @($mode) }                        # a single bare tag, e.g. 'he-IL'
    }

    # Keep only tags whose primary subtag differs from the display language (so the display
    # language is never added as a "secondary"), de-duplicated, order preserved.
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($t in $tags) {
        $tag = ([string]$t).Trim()
        if ([string]::IsNullOrWhiteSpace($tag)) { continue }
        if ((($tag -split '-')[0]).ToLowerInvariant() -eq $uiPrimary) { continue }
        if (-not $result.Contains($tag)) { $result.Add($tag) }
    }
    return @($result)
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
        [object]$Settings
    )

    $raw = [string](Get-WinMintProfileSetting $Settings 'AiPolicy' '')
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $raw = [string](Get-WinMintProfileSetting $Settings 'AIPolicy' '')
    }
    if ([string]::IsNullOrWhiteSpace($raw)) {
        # Subtractive default: full serviceable AI removal on every build.
        $raw = 'ServiceableFull'
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

function Get-WinMintAppxRemovalCatalog {
    $path = Get-WinMintPath -Name ConfigRoot -ChildPath 'appx-removal.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "AppX removal catalog not found: $path"
    }
    Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-WinMintProfileEditorIds {
    param([object]$Settings)

    $editors = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $Settings 'Editors' @()))
    if ($editors.Count -gt 0 -or (Test-WinMintProfileSettingExists -Settings $Settings -Name 'Editors')) {
        return $editors
    }

    $editorFlags = @(
        @('EditorCursor', 'cursor'),
        @('EditorVSCode', 'vscode'),
        @('EditorZed', 'zed'),
        @('EditorAntigravity', 'antigravity'),
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

function Get-WinMintProfileBrowserIds {
    param([object]$Settings)

    $browsers = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $Settings 'Browsers' @()))
    if ($browsers.Count -gt 0 -or (Test-WinMintProfileSettingExists -Settings $Settings -Name 'Browsers')) {
        return @(
            $browsers |
                ForEach-Object {
                    switch -Regex (([string]$_).Trim()) {
                        '^(Zen|Zen Browser|Zen-Browser|ZenBrowser)$' { 'zen-browser'; break }
                        '^(Helium)$' { 'helium'; break }
                        '^(LibreWolf|Librewolf|Libre Wolf)$' { 'librewolf'; break }
                        '^(Brave)$' { 'brave'; break }
                        '^(Edge|Microsoft Edge)$' { 'edge'; break }
                        default { ([string]$_).Trim().ToLowerInvariant() }
                    }
                } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique
        )
    }

    $browserFlags = @(
        @('BrowserZen', 'zen-browser'),
        @('BrowserHelium', 'helium'),
        @('BrowserLibreWolf', 'librewolf'),
        @('BrowserBrave', 'brave'),
        @('BrowserEdge', 'edge')
    )
    $hasExplicitBrowserFlag = @(
        $browserFlags |
            Where-Object { Test-WinMintProfileSettingExists -Settings $Settings -Name $_[0] }
    ).Count -gt 0
    $browsers = @(
        $browserFlags |
            Where-Object { [bool](Get-WinMintProfileSetting $Settings $_[0] $false) } |
            ForEach-Object { $_[1] }
    )
    if ($browsers.Count -gt 0 -or $hasExplicitBrowserFlag) { return $browsers }

    @()
}

function Get-WinMintProfileWslDistroIds {
    param([object]$Settings)

    function Convert-WinMintWslDistroSelection {
        param([string]$Value)

        switch -Regex (([string]$Value).Trim()) {
            '^(Ubuntu|Ubuntu-\d+\.\d+)$' { 'Ubuntu'; break }
            '^(Fedora|FedoraLinux|FedoraLinux-\d+)$' { 'FedoraLinux'; break }
            '^(Arch(?: Linux)?|archlinux)$' { 'archlinux'; break }
            '^(NixOS-WSL|NixOS|nixos-wsl)$' { 'NixOS-WSL'; break }
            '^(Pengwin|pengwin)$' { 'pengwin'; break }
            default { ([string]$Value).Trim() }
        }
    }

    $wslDistros = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $Settings 'Wsl2Distros' @()))
    if ($wslDistros.Count -gt 0 -or (Test-WinMintProfileSettingExists -Settings $Settings -Name 'Wsl2Distros')) {
        return @(
            $wslDistros |
                ForEach-Object { Convert-WinMintWslDistroSelection ([string]$_) } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique
        )
    }

    $legacyWslDistro = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $Settings 'Wsl2Distro' 'None'))
    if ($legacyWslDistro.Count -gt 0 -or (Test-WinMintProfileSettingExists -Settings $Settings -Name 'Wsl2Distro')) {
        return @(
            $legacyWslDistro |
                ForEach-Object { Convert-WinMintWslDistroSelection ([string]$_) } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique
        )
    }

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
    if ([bool](Get-WinMintProfileSetting $Settings 'InstallNilesoft' $false)) { $layers.Add('nilesoft') }
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

function Get-WinMintDefaultEditionName {
    # Universal default/fallback edition. WinMint's primary target is standard
    # Windows 11 Home. Get-WinMintInstallImagesForBuild treats this name specially:
    # if it is absent from a given ISO it falls back to servicing all editions
    # (rather than failing), while any other explicitly selected edition still
    # fails hard when missing.
    'Windows 11 Home'
}

function Get-WinMintHostEditionName {
    # Map the build host's own Windows edition to the matching install.wim image
    # name, so the default build targets the edition the host's firmware/digital
    # license will activate. Reads registry EditionID (the running SKU, which equals
    # the licensed SKU on virtually all real devices). Returns '' when the edition
    # can't be determined or isn't a known client SKU (e.g. a VM with a generic
    # edition), so callers fall back to Windows 11 Home.
    $skuToImage = @{
        'Core'                    = 'Windows 11 Home'
        'CoreN'                   = 'Windows 11 Home N'
        'CoreSingleLanguage'      = 'Windows 11 Home Single Language'
        'Professional'            = 'Windows 11 Pro'
        'ProfessionalN'           = 'Windows 11 Pro N'
        'ProfessionalEducation'   = 'Windows 11 Pro Education'
        'ProfessionalWorkstation' = 'Windows 11 Pro for Workstations'
        'Education'               = 'Windows 11 Education'
        'EducationN'              = 'Windows 11 Education N'
        'Enterprise'              = 'Windows 11 Enterprise'
        'EnterpriseN'             = 'Windows 11 Enterprise N'
    }
    try {
        $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $editionId = [string]$cv.EditionID
        if ($editionId -and $skuToImage.ContainsKey($editionId)) { return $skuToImage[$editionId] }
    }
    catch { }
    return ''
}

function Resolve-WinMintEditionSelection {
    <#
    <summary>
    Maps the friendly -Edition selector (and legacy -EditionMode) into the
    (Mode, Name) the build profile stores. The default (and the Host/Auto token)
    detects the build host's edition so the image targets the license the host
    will activate, falling back to Windows 11 Home when it can't be detected.
    'All' (or an explicit -EditionMode TargetLicense) services every edition so
    Windows Setup can pick the target device's edition.
    </summary>
    #>
    param(
        [string]$Edition = '',
        [string]$EditionMode = '',
        [bool]$EditionSpecified = $false,
        [bool]$EditionModeSpecified = $false
    )
    $autoName = {
        $detected = Get-WinMintHostEditionName
        if ([string]::IsNullOrWhiteSpace($detected)) { Get-WinMintDefaultEditionName } else { $detected }
    }
    if ($EditionSpecified) {
        switch -Regex (([string]$Edition).Trim()) {
            '^(All|TargetLicense|Target|License|Any)$' { return [pscustomobject]@{ Mode = 'TargetLicense'; Name = '' } }
            '^(Host|Auto|Detect|Match)$' { return [pscustomobject]@{ Mode = 'Fixed'; Name = (& $autoName) } }
            '^(SingleLanguage|HomeSingleLanguage|HomeSL|SingleLang|SL)$' { return [pscustomobject]@{ Mode = 'Fixed'; Name = 'Windows 11 Home Single Language' } }
            '^(Home)$' { return [pscustomobject]@{ Mode = 'Fixed'; Name = 'Windows 11 Home' } }
            '^(Pro|Professional)$' { return [pscustomobject]@{ Mode = 'Fixed'; Name = 'Windows 11 Pro' } }
            '^(Enterprise|Ent)$' { return [pscustomobject]@{ Mode = 'Fixed'; Name = 'Windows 11 Enterprise' } }
            '^(Education|Edu)$' { return [pscustomobject]@{ Mode = 'Fixed'; Name = 'Windows 11 Education' } }
            '^\s*$' { return [pscustomobject]@{ Mode = 'Fixed'; Name = (& $autoName) } }
            default { return [pscustomobject]@{ Mode = 'Fixed'; Name = ([string]$Edition).Trim() } }
        }
    }
    if ($EditionModeSpecified -and ([string]$EditionMode) -match '^(TargetLicense|Target|License)$') {
        return [pscustomobject]@{ Mode = 'TargetLicense'; Name = '' }
    }
    return [pscustomobject]@{ Mode = 'Fixed'; Name = (& $autoName) }
}

function Get-WinMintGenericProductKey {
    # Public per-edition "generic" / KMS-client setup keys. These do NOT activate;
    # they let an unattended install select the edition and skip the Setup product-
    # key page — used for VM/container test ISOs, or when the build host has no
    # firmware/OEM key. Returns '' for an edition without a known generic key.
    param([Parameter(Mandatory)][string]$EditionName)
    $keys = @{
        'Windows 11 Home'                 = 'YTMG3-N6DKC-DKB77-7M9GH-8HVX7'
        'Windows 11 Home N'               = '4CPRK-NM3K3-X6XXQ-RHX7B-X9R93'
        'Windows 11 Home Single Language' = 'BT79Q-G7N6G-PGBYW-4YWX6-6F4BT'
        'Windows 11 Pro'                  = 'VK7JG-NPHTM-C97JM-9MPGT-3V66T'
        'Windows 11 Pro N'                = '2B87N-8KFHP-DKV6R-Y2C8J-PKCKT'
        'Windows 11 Pro Education'        = '8PTT6-RNW4C-6V7J2-C2D3X-MHBPB'
        'Windows 11 Pro for Workstations' = 'DXG7C-N36C4-C4HTG-X4T3X-2YV77'
        'Windows 11 Education'            = 'YNMGQ-8RYV3-4PGQ3-C8XTP-7CFBY'
        'Windows 11 Education N'          = '84NGF-MHBT6-FXBX8-QWJK7-DRR8H'
        'Windows 11 Enterprise'           = 'XGVPP-NMH47-7TTHJ-W3FW7-8HV2C'
        'Windows 11 Enterprise N'         = 'WGGHN-J84D6-QYCPR-T7PJ7-X766F'
    }
    if ($keys.ContainsKey($EditionName)) { return $keys[$EditionName] }
    return ''
}

function Test-WinMintHostHasFirmwareKey {
    # True when the build host has an embedded OEM/firmware product key (ACPI MSDM).
    # A host without one is typically a VM/CI builder, where the unattended install
    # should skip the product-key prompt via a generic key. Best-effort; a read
    # failure is treated as "no firmware key" (lean toward injecting for VMs).
    try {
        $sls = Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction Stop
        return -not [string]::IsNullOrWhiteSpace([string]$sls.OA3xOriginalProductKey)
    }
    catch { return $false }
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

function Resolve-WinMintProfileUpdateConfig {
    param([object]$Settings)

    $mode = [string](Get-WinMintProfileSetting $Settings 'UpdateImage' (Get-WinMintProfileSetting $Settings 'UpdateMode' 'None'))
    switch -Regex ($mode) {
        '^(None|Off|Disabled)$' { $mode = 'None'; break }
        '^(Stable25H2|LatestStable25H2|25H2)$' { $mode = 'Stable25H2'; break }
        default { throw "Unsupported update image mode '$mode'." }
    }

    $provisionedApps = [string](Get-WinMintProfileSetting $Settings 'UpdateProvisionedApps' 'On')
    if ($provisionedApps -notin @('On', 'Off')) {
        throw "UpdateProvisionedApps must be On or Off."
    }

    [ordered]@{
        mode = $mode
        targetFeatureVersion = '25H2'
        releaseCadence = 'BRelease'
        includeOptionalPreviews = $false
        payloadRoot = [string](Get-WinMintProfileSetting $Settings 'UpdatePayloadRoot' '')
        qualitySecurity = [bool](Get-WinMintProfileSetting $Settings 'UpdateQualitySecurity' $true)
        dynamicUpdate = [bool](Get-WinMintProfileSetting $Settings 'UpdateDynamicUpdate' $true)
        defender = [bool](Get-WinMintProfileSetting $Settings 'UpdateDefender' $true)
        dotnet = [bool](Get-WinMintProfileSetting $Settings 'UpdateDotNet' $true)
        provisionedApps = ($provisionedApps -eq 'On')
    }
}

function New-WinMintBuildProfile {
    [CmdletBinding()]
    param(
        [object]$Settings = @{},
        [switch]$IncludeSecrets
    )

    $profileName = [string](Get-WinMintProfileSetting $Settings 'Profile' 'WinMint')
    # Subtractive model: the default build removes everything; opt-in keep flags
    # suppress a domain's removal.
    $keepEdge = [bool](Get-WinMintProfileSetting $Settings 'KeepEdge' $false)
    $keepGaming = [bool](Get-WinMintProfileSetting $Settings 'KeepGaming' $false)
    $keepCopilot = [bool](Get-WinMintProfileSetting $Settings 'KeepCopilot' $false)
    $editionMode = Get-WinMintProfileEditionMode -Settings $Settings
    $edition = [string](Get-WinMintProfileSetting $Settings 'Edition' '')
    if ($editionMode -eq 'Fixed' -and [string]::IsNullOrWhiteSpace($edition)) {
        $edition = 'Windows 11 Home'
    }
    # Optional generic product key (resolved by the caller). Empty = keyless, which
    # is the default for real-hardware ISOs (defer to the device firmware license).
    $productKey = [string](Get-WinMintProfileSetting $Settings 'ProductKey' '')
    $diskMode = Get-WinMintProfileDiskMode -Settings $Settings
    $dualBootPreset = Get-WinMintProfileDualBootPreset -Settings $Settings
    if ($diskMode -eq 'DualBootReserved' -and [string]::IsNullOrWhiteSpace($dualBootPreset)) {
        throw 'DualBootPreset must be explicitly selected when DiskMode is DualBootReserved.'
    }
    $driverSource = [string](Get-WinMintProfileSetting $Settings 'DriverSource' 'None')
    $driverPath = [string](Get-WinMintProfileSetting $Settings 'DriverPath' '')
    $selectedBrowsers = @(Get-WinMintProfileBrowserIds -Settings $Settings)
    if ($selectedBrowsers -contains 'edge') {
        $keepEdge = $true
    }
    $wslDistros = @(Get-WinMintProfileWslDistroIds -Settings $Settings)

    $password = [string](Get-WinMintProfileSetting $Settings 'Password' '')
    $accountMode = [string](Get-WinMintProfileSetting $Settings 'AccountMode' 'Local')
    if ($accountMode -notin @('Local', 'MicrosoftOobe')) { $accountMode = 'Local' }
    $passwordSet = [bool](Get-WinMintProfileSetting $Settings 'PasswordSet' (-not [string]::IsNullOrWhiteSpace($password)))
    $removeAdvertising = [bool](Get-WinMintProfileSetting $Settings 'RemoveAdvertising' $true)
    $removeGaming = [bool](Get-WinMintProfileSetting $Settings 'RemoveGaming' (-not $keepGaming))
    $removeCommunication = [bool](Get-WinMintProfileSetting $Settings 'RemoveCommunication' $true)
    $removeMicrosoftApps = [bool](Get-WinMintProfileSetting $Settings 'RemoveMicrosoftApps' $true)
    $aiPolicy = Get-WinMintProfileAiPolicy -Settings $Settings
    $updateConfig = Resolve-WinMintProfileUpdateConfig -Settings $Settings
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
        schemaVersion = 3
        createdAt = [DateTimeOffset]::Now.ToString('o')
        profileName = $profileName
        source = [ordered]@{
            isoPath = [string](Get-WinMintProfileSetting $Settings 'ISOPath' '')
            architecture = [string](Get-WinMintProfileSetting $Settings 'Architecture' '')
        }
        target = [ordered]@{
            device = [string](Get-WinMintProfileSetting $Settings 'TargetDevice' 'DifferentPC')
            formFactor = [string](Get-WinMintProfileSetting $Settings 'FormFactor' 'Auto')
            editionMode = $editionMode
            edition = $edition
            productKey = $productKey
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
            secondaryInputLanguages = Get-WinMintProfileSetting $Settings 'SecondaryInputLanguages' 'Auto'
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
            browsers = @($selectedBrowsers)
            wsl = [ordered]@{
                # WSL2 is a baseline platform feature on every build; distro
                # selection stays explicit, but the feature itself is always on.
                enabled = $true
                distros = @($wslDistros)
            }
        }
        features = [ordered]@{
            launcher = [string](Get-WinMintProfileSetting $Settings 'Launcher' $(if ([bool](Get-WinMintProfileSetting $Settings 'InstallFlowEverything' $false)) { 'FlowEverything' } else { 'None' }))
            liveInstallAudit = [bool](Get-WinMintProfileSetting $Settings 'LiveInstallAudit' $false)
            phoneLink = [bool](Get-WinMintProfileSetting $Settings 'PhoneLink' $false)
        }
        updates = $updateConfig
        keep = [ordered]@{
            edge = $keepEdge
            gaming = $keepGaming
            copilot = $keepCopilot
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

    if ([int]$BuildProfile.schemaVersion -ne 3) { & $add 'profile.schemaVersion must be 3.' }
    $source = Get-WinMintProfileSetting $BuildProfile 'source' @{}
    $target = Get-WinMintProfileSetting $BuildProfile 'target' @{}
    $identity = Get-WinMintProfileSetting $BuildProfile 'identity' @{}
    $regional = Get-WinMintProfileSetting $BuildProfile 'regional' @{}
    $drivers = Get-WinMintProfileSetting $BuildProfile 'drivers' @{}
    $desktop = Get-WinMintProfileSetting $BuildProfile 'desktop' @{}
    $development = Get-WinMintProfileSetting $BuildProfile 'development' @{}
    $features = Get-WinMintProfileSetting $BuildProfile 'features' @{}
    $updates = Get-WinMintProfileSetting $BuildProfile 'updates' @{ mode = 'None' }
    $removals = Get-WinMintProfileSetting $BuildProfile 'removals' @{}
    $privacy = Get-WinMintProfileSetting $BuildProfile 'privacy' @{}
    $tweaks = Get-WinMintProfileSetting $BuildProfile 'tweaks' @{}

    & $require $source 'profile.source' @('isoPath', 'architecture')
    & $enum ([string](Get-WinMintProfileSetting $source 'architecture' '')) 'profile.source.architecture' @('amd64', 'arm64', 'x86', '')
    & $require $target 'profile.target' @('device', 'editionMode', 'edition', 'diskMode')
    & $enum ([string](Get-WinMintProfileSetting $target 'device' '')) 'profile.target.device' @('ThisPC', 'DifferentPC')
    if (Test-WinMintProfileProperty -Object $target -Name 'formFactor') {
        & $enum ([string](Get-WinMintProfileSetting $target 'formFactor' '')) 'profile.target.formFactor' @('Auto', 'Laptop', 'Desktop')
    }
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
    foreach ($layer in $layers) { & $enum $layer 'profile.desktop.layers[]' @('standard', 'windhawk', 'yasb', 'komorebi', 'nilesoft') }
    if ($layers.Count -ne @($layers | Select-Object -Unique).Count) { & $add 'profile.desktop.layers must be unique.' }

    & $require $development 'profile.development' @('editors', 'browsers', 'wsl')
    $editors = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $development 'editors' @()))
    foreach ($editor in $editors) {
        & $enum ([string]$editor) 'profile.development.editors[]' @('cursor', 'vscode', 'zed', 'antigravity', 'neovim')
    }
    if ($editors.Count -ne @($editors | Select-Object -Unique).Count) {
        & $add 'profile.development.editors must be unique.'
    }
    $browserValues = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $development 'browsers' @()))
    foreach ($browser in $browserValues) {
        & $enum ([string]$browser) 'profile.development.browsers[]' @('zen-browser', 'helium', 'librewolf', 'brave', 'edge')
    }
    if ($browserValues.Count -ne @($browserValues | Select-Object -Unique).Count) {
        & $add 'profile.development.browsers must be unique.'
    }
    $wsl = Get-WinMintProfileSetting $development 'wsl' @{}
    & $require $wsl 'profile.development.wsl' @('enabled', 'distros')
    & $bool $wsl 'enabled' 'profile.development.wsl.enabled'
    if (-not [bool](Get-WinMintProfileSetting $wsl 'enabled' $false)) {
        & $add 'profile.development.wsl.enabled must be true; WSL is baseline on every build.'
    }

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

    if (Test-WinMintProfileProperty -Object $BuildProfile -Name 'updates') {
        & $require $updates 'profile.updates' @(
            'mode', 'targetFeatureVersion', 'releaseCadence', 'includeOptionalPreviews',
            'payloadRoot', 'qualitySecurity', 'dynamicUpdate', 'defender', 'dotnet',
            'provisionedApps'
        )
        & $enum ([string](Get-WinMintProfileSetting $updates 'mode' 'None')) 'profile.updates.mode' @('None', 'Stable25H2')
        & $enum ([string](Get-WinMintProfileSetting $updates 'targetFeatureVersion' '25H2')) 'profile.updates.targetFeatureVersion' @('25H2')
        & $enum ([string](Get-WinMintProfileSetting $updates 'releaseCadence' 'BRelease')) 'profile.updates.releaseCadence' @('BRelease')
        foreach ($name in @('includeOptionalPreviews', 'qualitySecurity', 'dynamicUpdate', 'defender', 'dotnet', 'provisionedApps')) {
            & $bool $updates $name "profile.updates.$name"
        }
        if ([bool](Get-WinMintProfileSetting $updates 'includeOptionalPreviews' $false)) {
            & $add 'profile.updates.includeOptionalPreviews must remain false for Stable25H2 builds.'
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
    if (Test-WinMintProfileProperty -Object $BuildProfile -Name 'keep') {
        $keep = Get-WinMintProfileSetting $BuildProfile 'keep' @{}
        foreach ($name in @('edge', 'gaming', 'copilot')) {
            & $bool $keep $name "profile.keep.$name"
        }
        if ($browserValues -contains 'edge' -and -not [bool](Get-WinMintProfileSetting $keep 'edge' $false)) {
            & $add 'profile.keep.edge must be true when Edge is selected in profile.development.browsers.'
        }
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
