#Requires -Version 7.6

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
                        '^(Firefox Developer Edition|Firefox Dev|FirefoxDeveloperEdition|FirefoxDev|FDE)$' { 'firefox-developer-edition'; break }
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
        @('BrowserFirefoxDeveloperEdition', 'firefox-developer-edition'),
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

    $wslDistros = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $Settings 'Wsl2Distros' @()))
    if ($wslDistros.Count -gt 0 -or (Test-WinMintProfileSettingExists -Settings $Settings -Name 'Wsl2Distros')) {
        return @((ConvertTo-WinMintWslSelection -Values $wslDistros).ProfileTokens)
    }

    $legacyWslDistro = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $Settings 'Wsl2Distro' 'None'))
    if ($legacyWslDistro.Count -gt 0 -or (Test-WinMintProfileSettingExists -Settings $Settings -Name 'Wsl2Distro')) {
        return @((ConvertTo-WinMintWslSelection -Values $legacyWslDistro).ProfileTokens)
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
    if ([bool](Get-WinMintProfileSetting $Settings 'InstallThide' $false)) { $layers.Add('thide') }
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

function Get-WinMintProfileAppxRemovalPrefixFromKeep {
    param([object]$Keep)

    $settings = Get-WinMintProfileRemovalSettingsFromKeep -Keep $Keep
    Get-WinMintEffectiveAppxRemovalPrefix -Settings $settings
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

function Get-WinMintAppxSystemExemptPrefixes {
    $catalog = Get-WinMintAppxRemovalCatalog
    if ($catalog.PSObject.Properties['systemExemptPrefixes']) {
        return @($catalog.systemExemptPrefixes | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }
    return @()
}

function Resolve-WinMintBuildAppxRemovalPrefixes {
    param(
        [Parameter(Mandatory)][string[]]$BasePrefixes,
        [string[]]$AiPrefixes = @(),
        [bool]$KeepCopilot = $false,
        [bool]$PhoneLink = $false
    )

    $prefixes = @($BasePrefixes + @($AiPrefixes) | Where-Object { $_ } | Sort-Object -Unique)
    $systemExempt = @(Get-WinMintAppxSystemExemptPrefixes)
    if ($systemExempt.Count -gt 0) {
        $prefixes = @($prefixes | Where-Object { $_ -notin $systemExempt })
    }
    if ($KeepCopilot) {
        $prefixes = @($prefixes | Where-Object {
                $_ -notin @('Microsoft.Copilot', 'Microsoft.Windows.Copilot', 'Microsoft.Windows.AIHub')
            })
    }
    if (-not $PhoneLink) {
        $catalog = Get-WinMintAppxRemovalCatalog
        if ($catalog.PSObject.Properties['optInKeep'] -and $catalog.optInKeep.PSObject.Properties['phoneLink']) {
            $prefixes = @($prefixes + @($catalog.optInKeep.phoneLink | ForEach-Object { [string]$_ }) | Sort-Object -Unique)
        }
    }
    return @($prefixes)
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

function Get-WinMintDefaultUpdatePayloadRoot {
    $temp = [System.IO.Path]::GetTempPath()
    if ([string]::IsNullOrWhiteSpace($temp)) {
        $temp = $env:TEMP
    }
    if ([string]::IsNullOrWhiteSpace($temp)) {
        return ''
    }
    Join-Path ($temp.TrimEnd([char]'\', [char]'/')) 'Win11ISO_dependency_cache\updates\25H2-BRelease'
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
    $payloadRoot = [string](Get-WinMintProfileSetting $Settings 'UpdatePayloadRoot' '')
    if ($mode -eq 'Stable25H2' -and [string]::IsNullOrWhiteSpace($payloadRoot)) {
        $payloadRoot = Get-WinMintDefaultUpdatePayloadRoot
    }

    [ordered]@{
        mode = $mode
        targetFeatureVersion = '25H2'
        releaseCadence = 'BRelease'
        includeOptionalPreviews = $false
        payloadRoot = $payloadRoot
        qualitySecurity = [bool](Get-WinMintProfileSetting $Settings 'UpdateQualitySecurity' $true)
        dynamicUpdate = [bool](Get-WinMintProfileSetting $Settings 'UpdateDynamicUpdate' $true)
        defender = [bool](Get-WinMintProfileSetting $Settings 'UpdateDefender' $true)
        dotnet = [bool](Get-WinMintProfileSetting $Settings 'UpdateDotNet' $true)
        provisionedApps = ($provisionedApps -eq 'On')
    }
}

function Complete-WinMintBuildProfileUpdates {
    param([Parameter(Mandatory)][object]$BuildProfile)

    $mode = 'None'
    if (Test-WinMintProfileProperty -Object $BuildProfile -Name 'updates') {
        $mode = [string](Get-WinMintProfileSetting $BuildProfile.updates 'mode' 'None')
    }

    $defaults = Resolve-WinMintProfileUpdateConfig -Settings @{ UpdateMode = $mode }
    if (-not (Test-WinMintProfileProperty -Object $BuildProfile -Name 'updates')) {
        $BuildProfile | Add-Member -NotePropertyName 'updates' -NotePropertyValue (
            $defaults | ConvertTo-Json -Depth 6 | ConvertFrom-Json
        ) -Force
        return
    }

    $updates = $BuildProfile.updates
    foreach ($name in @($defaults.Keys)) {
        if (-not (Test-WinMintProfileProperty -Object $updates -Name $name)) {
            $updates | Add-Member -NotePropertyName $name -NotePropertyValue $defaults[$name] -Force
        }
    }
}

function New-WinMintBuildProfile {
    [CmdletBinding()]
    param(
        [object]$Settings = @{},
        [switch]$IncludeSecrets
    )

    $profileName = [string](Get-WinMintProfileSetting $Settings 'Profile' 'WinMint')
    # Subtractive model for gaming/copilot; Edge is always kept (debloat-only).
    # -KeepEdge is accepted but ignored — not a user product choice.
    $keepEdge = $true
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
    $wslDistros = @(Get-WinMintProfileWslDistroIds -Settings $Settings)

    $password = [string](Get-WinMintProfileSetting $Settings 'Password' '')
    $accountMode = [string](Get-WinMintProfileSetting $Settings 'AccountMode' 'Local')
    if ($accountMode -notin @('Local', 'MicrosoftOobe')) { $accountMode = 'Local' }
    $passwordSet = [bool](Get-WinMintProfileSetting $Settings 'PasswordSet' (-not [string]::IsNullOrWhiteSpace($password)))
    $aiPolicy = Get-WinMintProfileAiPolicy -Settings $Settings
    $updateConfig = Resolve-WinMintProfileUpdateConfig -Settings $Settings
    $userLocale = Get-WinMintProfileStringSetting -Settings $Settings -Name 'UserLocale' -Default 'en-US'
    $homeLocationGeoId = [int](Get-WinMintProfileSetting $Settings 'HomeLocationGeoId' (Resolve-WinMintRegionGeoId -CultureName $userLocale))
    $tweakDarkMode = [bool](Get-WinMintProfileSetting $Settings 'TweakDarkMode' $true)
    $tweakFileExt = [bool](Get-WinMintProfileSetting $Settings 'TweakFileExt' $true)
    $tweakStickyKeysOff = [bool](Get-WinMintProfileSetting $Settings 'TweakStickyKeys' $true)
    $tweakHardwareBypass = [bool](Get-WinMintProfileSetting $Settings 'TweakHardwareBypass' $false)
    $tweakDmaInterop = [bool](Get-WinMintProfileSetting $Settings 'TweakDmaInterop' $true)
    $privLocation = [bool](Get-WinMintProfileSetting $Settings 'PrivLocation' $true)
    $privTelemetryHardening = [bool](Get-WinMintProfileSetting $Settings 'PrivTelemetry' $true)
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
        schemaVersion = 4
        createdAt = [DateTimeOffset]::Now.ToString('o')
        profileName = $profileName
        keep = [ordered]@{
            edge = $keepEdge
            gaming = $keepGaming
            copilot = $keepCopilot
        }
        source = [ordered]@{
            isoPath = [string](Get-WinMintProfileSetting $Settings 'ISOPath' '')
            architecture = [string](Get-WinMintProfileSetting $Settings 'Architecture' '')
        }
        target = [ordered]@{
            device = [string](Get-WinMintProfileSetting $Settings 'TargetDevice' 'DifferentPC')
            formFactor = [string](Get-WinMintProfileSetting $Settings 'FormFactor' 'Auto')
            powerPlan = [string](Get-WinMintProfileSetting $Settings 'PowerPlan' 'Balanced')
            editionMode = $editionMode
            edition = $edition
            productKey = $productKey
            diskMode = $diskMode
            diskLayout = [ordered]@{
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
            path = if ((Test-WinMintDriverSourceUsesPath -Source $driverSource) -or (Test-WinMintDriverSourceUsesSurfaceCatalog -Source $driverSource)) { $driverPath } else { '' }
            exportHostDrivers = (Test-WinMintDriverSourceUsesHostExport -Source $driverSource)
        }
        desktop = [ordered]@{
            cursorPack = 'Windows11Modern'
            layers = @(Get-WinMintProfileDesktopLayers -Settings $Settings)
        }
        development = [ordered]@{
            editors = @(Get-WinMintProfileEditorIds -Settings $Settings)
            browsers = @($selectedBrowsers)
            wsl = [ordered]@{
                distros = @($wslDistros)
            }
        }
        features = [ordered]@{
            launcher = [string](Get-WinMintProfileSetting $Settings 'Launcher' 'None')
            liveInstallAudit = [bool](Get-WinMintProfileSetting $Settings 'LiveInstallAudit' $false)
            phoneLink = [bool](Get-WinMintProfileSetting $Settings 'PhoneLink' $false)
        }
        updates = $updateConfig
        removals = [ordered]@{
            aiPolicy = $aiPolicy
        }
        posture = [ordered]@{
            appearance = [ordered]@{
                theme = if ($tweakDarkMode) { 'dark' } else { 'light' }
            }
            explorer = [ordered]@{
                showFileExtensions = $tweakFileExt
                showHiddenFiles = $tweakFileExt
            }
            accessibility = [ordered]@{
                stickyKeys = if ($tweakStickyKeysOff) { 'disabled' } else { 'enabled' }
            }
            setup = [ordered]@{
                dmaInterop = $tweakDmaInterop
                hardwareBypass = $tweakHardwareBypass
            }
        }
        privacy = [ordered]@{
            locationServices = if ($privLocation) { 'enabled' } else { 'disabled' }
            telemetryTracing = if ($privTelemetryHardening) { 'disabled' } else { 'default' }
            advertisingId = 'disabled'
            activityHistory = 'disabled'
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

    Complete-WinMintBuildProfileUpdates -BuildProfile $BuildProfile

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
    $enumStr = {
        param([string]$Value, [string]$Path, [string[]]$Allowed)
        if ($Allowed -notcontains $Value) {
            & $add "$Path must be one of: $($Allowed -join ', ')."
        }
    }
    $options = Get-WinMintOptionCatalog

    & $require $BuildProfile 'profile' @(
        'schemaVersion', 'createdAt', 'profileName', 'keep', 'source', 'target', 'identity',
        'regional', 'drivers', 'desktop', 'development', 'removals', 'posture', 'privacy'
    )
    if ($failures.Count -gt 0) { return [pscustomobject]@{ Passed = $false; Failures = $failures.ToArray() } }

    $schemaVersion = [int]$BuildProfile.schemaVersion
    if ($schemaVersion -eq 3) {
        & $add 'profile.schemaVersion 3 is no longer supported; migrate to schemaVersion 4.'
        return [pscustomobject]@{ Passed = $false; Failures = $failures.ToArray() }
    }
    if ($schemaVersion -ne 4) { & $add 'profile.schemaVersion must be 4.' }

    $keep = Get-WinMintProfileSetting $BuildProfile 'keep' @{}
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
    $posture = Get-WinMintProfileSetting $BuildProfile 'posture' @{}
    $privacy = Get-WinMintProfileSetting $BuildProfile 'privacy' @{}

    & $require $keep 'profile.keep' @('edge', 'gaming', 'copilot')
    foreach ($name in @('edge', 'gaming', 'copilot')) {
        & $bool $keep $name "profile.keep.$name"
    }

    & $require $source 'profile.source' @('isoPath', 'architecture')
    & $enum ([string](Get-WinMintProfileSetting $source 'architecture' '')) 'profile.source.architecture' @($options['ProfileArchitecture'])
    & $require $target 'profile.target' @('device', 'editionMode', 'edition', 'diskMode')
    & $enum ([string](Get-WinMintProfileSetting $target 'device' '')) 'profile.target.device' @($options['TargetDevice'])
    if (Test-WinMintProfileProperty -Object $target -Name 'formFactor') {
        & $enum ([string](Get-WinMintProfileSetting $target 'formFactor' '')) 'profile.target.formFactor' @($options['FormFactor'])
    }
    if (Test-WinMintProfileProperty -Object $target -Name 'powerPlan') {
        & $enum ([string](Get-WinMintProfileSetting $target 'powerPlan' '')) 'profile.target.powerPlan' @($options['PowerPlan'])
    }
    & $enum ([string](Get-WinMintProfileSetting $target 'editionMode' '')) 'profile.target.editionMode' @($options['EditionMode'])
    $diskMode = [string](Get-WinMintProfileSetting $target 'diskMode' '')
    & $enum $diskMode 'profile.target.diskMode' @($options['DiskMode'])
    if (Test-WinMintProfileProperty -Object $target -Name 'diskLayout') {
        $diskLayout = Get-WinMintProfileSetting $target 'diskLayout' @{}
        & $require $diskLayout 'profile.target.diskLayout' @(
            'preset', 'roundingGb', 'windowsMinimumGb', 'windowsRecommendedGb',
            'linuxMinimumGb', 'linuxRecommendedGb', 'efiMb', 'msrMb', 'recoveryMb'
        )
        & $enumStr ([string](Get-WinMintProfileSetting $diskLayout 'preset' '')) 'profile.target.diskLayout.preset' @($options['DiskLayoutPreset'])
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
        & $enum ([string](Get-WinMintProfileSetting $identity 'accountMode' 'Local')) 'profile.identity.accountMode' @($options['AccountMode'])
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
    & $enum $driverSource 'profile.drivers.source' @($options['DriverSource'])
    & $bool $drivers 'exportHostDrivers' 'profile.drivers.exportHostDrivers'
    $exportHostDrivers = Get-WinMintProfileSetting $drivers 'exportHostDrivers' $null
    if ($exportHostDrivers -is [bool]) {
        if ((Test-WinMintDriverSourceUsesHostExport -Source $driverSource) -and -not $exportHostDrivers) {
            & $add 'profile.drivers.exportHostDrivers must be true when profile.drivers.source is Host or HostExport.'
        }
        elseif ($exportHostDrivers -and $driverSource -eq 'None') {
            & $add 'profile.drivers.exportHostDrivers requires a driver source or Host/HostExport.'
        }
    }
    $hostMirrorFilter = [string](Get-WinMintProfileSetting $drivers 'hostMirrorFilter' '')
    if (-not [string]::IsNullOrWhiteSpace($hostMirrorFilter)) {
        if ($hostMirrorFilter -notin @('full', 'setup-critical')) {
            & $add 'profile.drivers.hostMirrorFilter must be full or setup-critical.'
        }
        elseif (-not $exportHostDrivers) {
            & $add 'profile.drivers.hostMirrorFilter requires profile.drivers.exportHostDrivers=true.'
        }
    }
    if ((Test-WinMintDriverSourceUsesPath -Source $driverSource) -and [string]::IsNullOrWhiteSpace([string](Get-WinMintProfileSetting $drivers 'path' ''))) {
        & $add "profile.drivers.path is required when profile.drivers.source is $driverSource."
    }
    if ((Test-WinMintDriverSourceUsesSurfaceCatalog -Source $driverSource) -and [string]::IsNullOrWhiteSpace([string](Get-WinMintProfileSetting $drivers 'path' ''))) {
        & $add 'profile.drivers.path is required when profile.drivers.source is SurfaceCatalog and must contain a Surface catalog device id.'
    }

    & $require $desktop 'profile.desktop' @('cursorPack', 'layers')
    & $enum ([string](Get-WinMintProfileSetting $desktop 'cursorPack' '')) 'profile.desktop.cursorPack' @($options['DesktopCursorPack'])
    $layers = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $desktop 'layers' @()))
    foreach ($layer in $layers) { & $enum $layer 'profile.desktop.layers[]' @($options['DesktopLayer']) }
    if ($layers.Count -ne @($layers | Select-Object -Unique).Count) { & $add 'profile.desktop.layers must be unique.' }

    & $require $development 'profile.development' @('editors', 'browsers', 'wsl')
    $editors = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $development 'editors' @()))
    foreach ($editor in $editors) {
        & $enum ([string]$editor) 'profile.development.editors[]' @($options['Editor'])
    }
    if ($editors.Count -ne @($editors | Select-Object -Unique).Count) {
        & $add 'profile.development.editors must be unique.'
    }
    $browserValues = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $development 'browsers' @()))
    foreach ($browser in $browserValues) {
        & $enum ([string]$browser) 'profile.development.browsers[]' @($options['Browser'])
    }
    if ($browserValues.Count -ne @($browserValues | Select-Object -Unique).Count) {
        & $add 'profile.development.browsers must be unique.'
    }
    $wsl = Get-WinMintProfileSetting $development 'wsl' @{}
    & $require $wsl 'profile.development.wsl' @('distros')
    $wslDistros = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $wsl 'distros' @()))
    foreach ($distro in $wslDistros) {
        & $enum ([string]$distro) 'profile.development.wsl.distros[]' @($options['WslDistro'])
    }
    if ($wslDistros.Count -ne @($wslDistros | Select-Object -Unique).Count) {
        & $add 'profile.development.wsl.distros must be unique.'
    }
    $dotfiles = Get-WinMintProfileSetting $development 'dotfiles' $null
    if ($null -ne $dotfiles) {
        $repo = [string](Get-WinMintProfileSetting $dotfiles 'repository' '')
        if ([string]::IsNullOrWhiteSpace($repo)) {
            & $add 'profile.development.dotfiles.repository is required when dotfiles is present.'
        }
        elseif ($repo -notmatch '^https://') {
            & $add 'profile.development.dotfiles.repository must be an https:// git URL (v1).'
        }
    }

    if (Test-WinMintProfileProperty -Object $BuildProfile -Name 'features') {
        & $require $features 'profile.features' @('launcher')
        & $enum ([string](Get-WinMintProfileSetting $features 'launcher' '')) 'profile.features.launcher' @($options['Launcher'])
        if (Test-WinMintProfileProperty -Object $features -Name 'liveInstallAudit') {
            & $bool $features 'liveInstallAudit' 'profile.features.liveInstallAudit'
        }
        if (Test-WinMintProfileProperty -Object $features -Name 'phoneLink') {
            & $bool $features 'phoneLink' 'profile.features.phoneLink'
        }
    }

    if (Test-WinMintProfileProperty -Object $BuildProfile -Name 'updates') {
        & $require $updates 'profile.updates' @(
            'mode', 'targetFeatureVersion', 'releaseCadence', 'includeOptionalPreviews',
            'payloadRoot', 'qualitySecurity', 'dynamicUpdate', 'defender', 'dotnet',
            'provisionedApps'
        )
        & $enum ([string](Get-WinMintProfileSetting $updates 'mode' 'None')) 'profile.updates.mode' @($options['UpdateMode'])
        & $enum ([string](Get-WinMintProfileSetting $updates 'targetFeatureVersion' '25H2')) 'profile.updates.targetFeatureVersion' @($options['UpdateTargetFeatureVersion'])
        & $enum ([string](Get-WinMintProfileSetting $updates 'releaseCadence' 'BRelease')) 'profile.updates.releaseCadence' @($options['UpdateReleaseCadence'])
        foreach ($name in @('includeOptionalPreviews', 'qualitySecurity', 'dynamicUpdate', 'defender', 'dotnet', 'provisionedApps')) {
            & $bool $updates $name "profile.updates.$name"
        }
        if ([bool](Get-WinMintProfileSetting $updates 'includeOptionalPreviews' $false)) {
            & $add 'profile.updates.includeOptionalPreviews must remain false for Stable25H2 builds.'
        }
    }

    & $require $removals 'profile.removals' @('aiPolicy')
    if (Test-WinMintProfileProperty -Object $removals -Name 'aiPolicy') {
        & $enum ([string](Get-WinMintProfileSetting $removals 'aiPolicy' 'Core')) 'profile.removals.aiPolicy' @($options['AiPolicy'])
        if ([string](Get-WinMintProfileSetting $removals 'aiPolicy' 'Core') -eq 'AggressiveExperimental' -and
            [string]$env:WINMINT_ENABLE_EXPERIMENTAL_AI_REMOVAL -ne '1') {
            & $add 'profile.removals.aiPolicy AggressiveExperimental requires WINMINT_ENABLE_EXPERIMENTAL_AI_REMOVAL=1.'
        }
    }
    if (Test-WinMintProfileProperty -Object $removals -Name 'effectiveAppx') {
        & $add 'profile.removals.effectiveAppx is build output only; remove it from authored profiles.'
    }
    foreach ($legacy in @('advertising', 'gaming', 'communication', 'microsoftApps')) {
        if (Test-WinMintProfileProperty -Object $removals -Name $legacy) {
            & $add "profile.removals.$legacy is no longer authored; use profile.keep instead."
        }
    }

    & $require $posture 'profile.posture' @('appearance', 'explorer', 'accessibility', 'setup')
    $appearance = Get-WinMintProfileSetting $posture 'appearance' @{}
    & $require $appearance 'profile.posture.appearance' @('theme')
    & $enumStr ([string](Get-WinMintProfileSetting $appearance 'theme' '')) 'profile.posture.appearance.theme' @('dark', 'light')
    $explorer = Get-WinMintProfileSetting $posture 'explorer' @{}
    foreach ($name in @('showFileExtensions', 'showHiddenFiles')) {
        & $bool $explorer $name "profile.posture.explorer.$name"
    }
    $accessibility = Get-WinMintProfileSetting $posture 'accessibility' @{}
    & $enumStr ([string](Get-WinMintProfileSetting $accessibility 'stickyKeys' '')) 'profile.posture.accessibility.stickyKeys' @('enabled', 'disabled')
    $setup = Get-WinMintProfileSetting $posture 'setup' @{}
    foreach ($name in @('dmaInterop', 'hardwareBypass')) {
        & $bool $setup $name "profile.posture.setup.$name"
    }

    & $require $privacy 'profile.privacy' @('locationServices', 'telemetryTracing', 'advertisingId', 'activityHistory')
    & $enumStr ([string](Get-WinMintProfileSetting $privacy 'locationServices' '')) 'profile.privacy.locationServices' @('enabled', 'disabled')
    & $enumStr ([string](Get-WinMintProfileSetting $privacy 'telemetryTracing' '')) 'profile.privacy.telemetryTracing' @('default', 'disabled')
    & $enumStr ([string](Get-WinMintProfileSetting $privacy 'advertisingId' '')) 'profile.privacy.advertisingId' @('enabled', 'disabled')
    & $enumStr ([string](Get-WinMintProfileSetting $privacy 'activityHistory' '')) 'profile.privacy.activityHistory' @('enabled', 'disabled')
    foreach ($legacy in @('telemetry', 'location', 'timeline')) {
        if (Test-WinMintProfileProperty -Object $privacy -Name $legacy) {
            & $add "profile.privacy.$legacy is schema v3; use the v4 privacy enums."
        }
    }
    if (Test-WinMintProfileProperty -Object $BuildProfile -Name 'tweaks') {
        & $add 'profile.tweaks is schema v3; use profile.posture instead.'
    }

    if ($browserValues -contains 'edge' -and -not [bool](Get-WinMintProfileSetting $keep 'edge' $false)) {
        & $add 'profile.keep.edge must be true when Edge is selected in profile.development.browsers.'
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

function Get-WinMintProfileV4Defaults {
    [ordered]@{
        keep = [ordered]@{
            edge    = $true
            gaming  = $false
            copilot = $false
        }
        posture = [ordered]@{
            appearance = [ordered]@{ theme = 'dark' }
            explorer = [ordered]@{
                showFileExtensions = $true
                showHiddenFiles    = $true
            }
            accessibility = [ordered]@{ stickyKeys = 'disabled' }
            setup = [ordered]@{
                dmaInterop      = $true
                hardwareBypass  = $false
            }
        }
        privacy = [ordered]@{
            locationServices = 'enabled'
            telemetryTracing = 'disabled'
            advertisingId    = 'disabled'
            activityHistory  = 'disabled'
        }
    }
}

function Get-WinMintProfileNestedSetting {
    param(
        [object]$Root,
        [string[]]$Path,
        $Default
    )

    $current = $Root
    foreach ($segment in $Path) {
        if ($null -eq $current) { return $Default }
        if (-not (Test-WinMintProfileSettingExists -Settings $current -Name $segment)) { return $Default }
        $current = Get-WinMintProfileSetting $current $segment
    }
    if ($null -eq $current) { return $Default }
    return $current
}

function Get-WinMintProfileKeepBlock {
    param([object]$BuildProfile)

    $defaults = (Get-WinMintProfileV4Defaults).keep
    $keep = Get-WinMintProfileSetting $BuildProfile 'keep' @{}
    [pscustomobject]@{
        Edge    = $true
        Gaming  = [bool](Get-WinMintProfileSetting $keep 'gaming' $defaults.gaming)
        Copilot = [bool](Get-WinMintProfileSetting $keep 'copilot' $defaults.copilot)
    }
}

function Get-WinMintProfileRemovalSettingsFromKeep {
    param([object]$Keep)

    [ordered]@{
        RemoveAdvertising    = $true
        RemoveGaming         = -not [bool]$Keep.Gaming
        RemoveCommunication  = $true
        RemoveMicrosoftApps  = $true
    }
}

function Resolve-WinMintBuildTweaksFromProfile {
    param([object]$BuildProfile)

    $posture = Get-WinMintProfileSetting $BuildProfile 'posture' @{}
    $defaults = (Get-WinMintProfileV4Defaults).posture
    $theme = [string](Get-WinMintProfileNestedSetting -Root $posture -Path @('appearance', 'theme') -Default $defaults.appearance.theme)
    if ($theme -notin @('dark', 'light')) { $theme = 'dark' }
    $showFileExtensions = [bool](Get-WinMintProfileNestedSetting -Root $posture -Path @('explorer', 'showFileExtensions') -Default $defaults.explorer.showFileExtensions)
    $stickyKeys = [string](Get-WinMintProfileNestedSetting -Root $posture -Path @('accessibility', 'stickyKeys') -Default $defaults.accessibility.stickyKeys)
    if ($stickyKeys -notin @('enabled', 'disabled')) { $stickyKeys = 'disabled' }
    $hardwareBypass = [bool](Get-WinMintProfileNestedSetting -Root $posture -Path @('setup', 'hardwareBypass') -Default $defaults.setup.hardwareBypass)
    $dmaInterop = [bool](Get-WinMintProfileNestedSetting -Root $posture -Path @('setup', 'dmaInterop') -Default $defaults.setup.dmaInterop)

    [pscustomobject]@{
        DarkMode         = ($theme -eq 'dark')
        FileExtensions   = $showFileExtensions
        StickyKeysOff    = ($stickyKeys -eq 'disabled')
        HardwareBypass   = $hardwareBypass
        DmaInterop       = $dmaInterop
        UpdatePolicy     = 'All'
    }
}

function Resolve-WinMintBuildPrivacyFromProfile {
    param([object]$BuildProfile)

    $privacy = Get-WinMintProfileSetting $BuildProfile 'privacy' @{}
    $defaults = (Get-WinMintProfileV4Defaults).privacy
    $locationServices = [string](Get-WinMintProfileSetting $privacy 'locationServices' $defaults.locationServices)
    if ($locationServices -notin @('enabled', 'disabled')) { $locationServices = 'enabled' }
    $telemetryTracing = [string](Get-WinMintProfileSetting $privacy 'telemetryTracing' $defaults.telemetryTracing)
    if ($telemetryTracing -notin @('default', 'disabled')) { $telemetryTracing = 'disabled' }
    $advertisingId = [string](Get-WinMintProfileSetting $privacy 'advertisingId' $defaults.advertisingId)
    if ($advertisingId -notin @('enabled', 'disabled')) { $advertisingId = 'disabled' }
    $activityHistory = [string](Get-WinMintProfileSetting $privacy 'activityHistory' $defaults.activityHistory)
    if ($activityHistory -notin @('enabled', 'disabled')) { $activityHistory = 'disabled' }

    [pscustomobject]@{
        Location                 = ($locationServices -eq 'enabled')
        TelemetryHardening       = ($telemetryTracing -eq 'disabled')
        AdvertisingIdDisabled    = ($advertisingId -eq 'disabled')
        ActivityHistoryDisabled  = ($activityHistory -eq 'disabled')
    }
}

function Convert-WinMintBuildProfileV3ToV4 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$BuildProfile,
        [switch]$PassThru
    )

    $warnings = [System.Collections.Generic.List[string]]::new()
    $keep = Get-WinMintProfileSetting $BuildProfile 'keep' @{}
    $removals = Get-WinMintProfileSetting $BuildProfile 'removals' @{}
    $tweaks = Get-WinMintProfileSetting $BuildProfile 'tweaks' @{}
    $privacy = Get-WinMintProfileSetting $BuildProfile 'privacy' @{}

    $keepEdge = $true
    $keepGaming = [bool](Get-WinMintProfileSetting $keep 'gaming' $false)
    $keepCopilot = [bool](Get-WinMintProfileSetting $keep 'copilot' $false)
    if (Test-WinMintProfileProperty -Object $removals -Name 'gaming') {
        $removeGaming = [bool](Get-WinMintProfileSetting $removals 'gaming' $true)
        if ($keepGaming -and $removeGaming) {
            $warnings.Add('keep.gaming=true overrides removals.gaming=true.') | Out-Null
        }
        elseif (-not $keepGaming -and -not $removeGaming) {
            $keepGaming = $true
            $warnings.Add('removals.gaming=false promoted to keep.gaming=true.') | Out-Null
        }
    }

    $development = Get-WinMintProfileSetting $BuildProfile 'development' @{}
    $browsers = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $development 'browsers' @()))

    $stickyKeys = if ([bool](Get-WinMintProfileSetting $tweaks 'stickyKeys' $true)) { 'disabled' } else { 'enabled' }
    $theme = if ([bool](Get-WinMintProfileSetting $tweaks 'darkMode' $true)) { 'dark' } else { 'light' }
    $showExplorer = [bool](Get-WinMintProfileSetting $tweaks 'fileExtensions' $true)

    $locationServices = if ([bool](Get-WinMintProfileSetting $privacy 'location' $true)) { 'enabled' } else { 'disabled' }
    $telemetryTracing = if ([bool](Get-WinMintProfileSetting $privacy 'telemetry' $true)) { 'disabled' } else { 'default' }
    $advertisingId = 'disabled'
    $activityHistory = 'disabled'

    $target = Get-WinMintProfileSetting $BuildProfile 'target' @{}
    $diskMode = [string](Get-WinMintProfileSetting $target 'diskMode' 'Manual')
    $diskLayout = Get-WinMintProfileSetting $target 'diskLayout' @{}
    if (Test-WinMintProfileProperty -Object $diskLayout -Name 'mode') {
        $diskLayout = [ordered]@{
            preset               = [string](Get-WinMintProfileSetting $diskLayout 'preset' '')
            roundingGb           = [int](Get-WinMintProfileSetting $diskLayout 'roundingGb' 64)
            windowsMinimumGb     = [int](Get-WinMintProfileSetting $diskLayout 'windowsMinimumGb' 256)
            windowsRecommendedGb = [int](Get-WinMintProfileSetting $diskLayout 'windowsRecommendedGb' 384)
            linuxMinimumGb       = [int](Get-WinMintProfileSetting $diskLayout 'linuxMinimumGb' 128)
            linuxRecommendedGb   = [int](Get-WinMintProfileSetting $diskLayout 'linuxRecommendedGb' 256)
            efiMb                = [int](Get-WinMintProfileSetting $diskLayout 'efiMb' 1024)
            msrMb                = [int](Get-WinMintProfileSetting $diskLayout 'msrMb' 16)
            recoveryMb           = [int](Get-WinMintProfileSetting $diskLayout 'recoveryMb' 1024)
        }
    }
    else {
        $diskLayout = [ordered]@{
            preset               = if ($diskMode -eq 'DualBootReserved') { [string](Get-WinMintProfileSetting $diskLayout 'preset' '') } else { '' }
            roundingGb           = 64
            windowsMinimumGb     = 256
            windowsRecommendedGb = 384
            linuxMinimumGb       = 128
            linuxRecommendedGb   = 256
            efiMb                = 1024
            msrMb                = 16
            recoveryMb           = 1024
        }
    }

    $wsl = Get-WinMintProfileSetting $development 'wsl' @{}
    $wslDistros = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $wsl 'distros' @()))

    $v4 = [ordered]@{
        schemaVersion = 4
        createdAt     = [string](Get-WinMintProfileSetting $BuildProfile 'createdAt' ([DateTimeOffset]::Now.ToString('o')))
        profileName   = [string](Get-WinMintProfileSetting $BuildProfile 'profileName' 'WinMint')
        keep          = [ordered]@{
            edge    = $keepEdge
            gaming  = $keepGaming
            copilot = $keepCopilot
        }
        source        = Get-WinMintProfileSetting $BuildProfile 'source' @{}
        target        = [ordered]@{
            device       = [string](Get-WinMintProfileSetting $target 'device' 'DifferentPC')
            editionMode  = [string](Get-WinMintProfileSetting $target 'editionMode' 'TargetLicense')
            edition      = [string](Get-WinMintProfileSetting $target 'edition' '')
            diskMode     = $diskMode
            diskLayout   = $diskLayout
        }
        identity      = Get-WinMintProfileSetting $BuildProfile 'identity' @{}
        regional      = Get-WinMintProfileSetting $BuildProfile 'regional' @{}
        drivers       = Get-WinMintProfileSetting $BuildProfile 'drivers' @{}
        desktop       = Get-WinMintProfileSetting $BuildProfile 'desktop' @{}
        development   = $({
            $developmentBlock = [ordered]@{
                editors  = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $development 'editors' @()))
                browsers = @($browsers)
                wsl      = [ordered]@{ distros = @($wslDistros) }
            }
            if (Test-WinMintProfileProperty -Object $development -Name 'dotfiles') {
                $developmentBlock.dotfiles = Get-WinMintProfileSetting $development 'dotfiles' @{}
            }
            $developmentBlock
        }.Invoke())
        features      = Get-WinMintProfileSetting $BuildProfile 'features' @{}
        updates       = Get-WinMintProfileSetting $BuildProfile 'updates' @{ mode = 'None' }
        removals      = [ordered]@{
            aiPolicy = [string](Get-WinMintProfileSetting $removals 'aiPolicy' 'ServiceableFull')
        }
        posture       = [ordered]@{
            appearance    = [ordered]@{ theme = $theme }
            explorer      = [ordered]@{
                showFileExtensions = $showExplorer
                showHiddenFiles    = $showExplorer
            }
            accessibility = [ordered]@{ stickyKeys = $stickyKeys }
            setup         = [ordered]@{
                dmaInterop     = [bool](Get-WinMintProfileSetting $tweaks 'dmaInterop' $true)
                hardwareBypass = [bool](Get-WinMintProfileSetting $tweaks 'hardwareBypass' $false)
            }
        }
        privacy       = [ordered]@{
            locationServices = $locationServices
            telemetryTracing = $telemetryTracing
            advertisingId    = $advertisingId
            activityHistory  = $activityHistory
        }
    }

    foreach ($name in @('formFactor', 'powerPlan', 'productKey')) {
        if (Test-WinMintProfileProperty -Object $target -Name $name) {
            $v4.target[$name] = Get-WinMintProfileSetting $target $name
        }
    }
    if (Test-WinMintProfileProperty -Object $BuildProfile -Name 'diagnostics') {
        $v4.diagnostics = Get-WinMintProfileSetting $BuildProfile 'diagnostics' @{}
    }

    if ($PassThru) {
        return [pscustomobject]@{
            Profile  = $v4
            Warnings = @($warnings)
        }
    }
    return $v4
}
