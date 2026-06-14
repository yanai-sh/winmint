#Requires -Version 7.3

function Get-RegistryTweakGroupValue {
    param(
        [Parameter(Mandatory)]$Group,
        [Parameter(Mandatory)][string]$Name
    )

    if ($Group -is [System.Collections.IDictionary]) {
        if ($Group.ContainsKey($Name)) { return $Group[$Name] }
        return $null
    }

    $property = $Group.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Invoke-RegistryTweak {
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir,
        [string[]]$GroupIds = @()
    )
    Write-SectionHeader 'Image: registry tweaks'

    $selected = @(
        @($GroupIds) |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Select-Object -Unique
    )

    Invoke-Action 'Applying offline registry tweaks (TPM / UX / policies)' {
        LogVerbose "Image root: $MountDir"
        $loadedHives = [System.Collections.Generic.List[string]]::new()
        try {
            foreach ($kv in $script:HiveMap.GetEnumerator()) {
                $null = & reg.exe load "HKLM\$($kv.Key)" (Join-Path $MountDir $kv.Value)
                $loadedHives.Add("HKLM\$($kv.Key)")
            }
            foreach ($group in $script:RegistryTweaks) {
                if ($selected.Count -gt 0 -and $selected -notcontains [string]$group.id) {
                    LogVerbose "Skipping tweak group '$($group.description)' (not selected by profile)."
                    if (Get-Command Add-WinMintManifestRegistryTweakEvent -ErrorAction SilentlyContinue) {
                        Add-WinMintManifestRegistryTweakEvent -Group $group -Status 'skipped-not-selected'
                    }
                    continue
                }
                $conditional = Get-RegistryTweakGroupValue -Group $group -Name 'conditional'
                if ($null -ne $conditional -and -not (& $conditional)) {
                    LogVerbose "Skipping tweak group '$($group.description)' (conditional false)."
                    if (Get-Command Add-WinMintManifestRegistryTweakEvent -ErrorAction SilentlyContinue) {
                        Add-WinMintManifestRegistryTweakEvent -Group $group -Status 'skipped-conditional'
                    }
                    continue
                }
                Log "Registry: $($group.description)"
                try {
                    foreach ($e in @(Get-RegistryTweakGroupValue -Group $group -Name 'set')) {
                        $null = & reg.exe add "HKLM\$($e.path)" /v "$($e.name)" /t $e.type /d "$($e.value)" /f
                    }
                    foreach ($e in @(Get-RegistryTweakGroupValue -Group $group -Name 'remove')) {
                        # Best-effort, idempotent removal: a policy key that isn't
                        # present on a clean image is the expected case, not an error.
                        # reg.exe writes "unable to find ..." to stderr (exit 1) then;
                        # redirect stderr so that benign case doesn't print in red. The
                        # catch still absorbs the exit-code throw for any other failure.
                        try { $null = & reg.exe delete "HKLM\$($e.path)" /f 2>$null } catch { Write-Verbose "reg.exe delete skipped for $($e.path): $($_.Exception.Message)" }
                    }
                    if (Get-Command Add-WinMintManifestRegistryTweakEvent -ErrorAction SilentlyContinue) {
                        Add-WinMintManifestRegistryTweakEvent -Group $group -Status 'applied'
                    }
                }
                catch {
                    if (Get-Command Add-WinMintManifestRegistryTweakEvent -ErrorAction SilentlyContinue) {
                        Add-WinMintManifestRegistryTweakEvent -Group $group -Status 'failed' -ErrorMessage $_.Exception.Message
                    }
                    throw
                }
            }
        }
        finally {
            foreach ($h in $loadedHives) { Dismount-OfflineHive -HivePath $h }
        }
    }
}

function Enable-WinMintOptionalFeature {
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir,
        [string[]]$Features = @()
    )
    Write-SectionHeader 'Image: optional Windows features'

    $requested = @(
        @($Features) |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Select-Object -Unique
    )
    if ($requested.Count -eq 0) {
        Log 'No optional Windows features selected for this profile.'
        return
    }

    Invoke-Action "Enabling optional Windows feature(s): $($requested -join ', ')" {
        LogVerbose "Mount: $MountDir"
        $featureMap = @{
            'Microsoft-Windows-Subsystem-Linux' = @{ Name = 'Microsoft-Windows-Subsystem-Linux'; Style = 'FeatureName' }
            'VirtualMachinePlatform' = @{ Name = 'VirtualMachinePlatform'; Style = 'FeatureName' }
            'OpenSSH.Client' = @{ Name = 'OpenSSH.Client~~~~0.0.1.0'; Style = 'Capability' }
        }
        foreach ($featureId in $requested) {
            if (-not $featureMap.ContainsKey($featureId)) {
                throw "Unsupported optional Windows feature '$featureId'."
            }
            $feat = $featureMap[$featureId]
            if ($feat.Style -eq 'Capability') {
                Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Add-Capability', "/CapabilityName:$($feat.Name)", '/LimitAccess') | Out-Null
            }
            else {
                Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Enable-Feature', "/FeatureName:$($feat.Name)", '/All', '/NoRestart') | Out-Null
            }
        }
    }
}

function Get-HostUnattendRegionalDefault {
    <# <summary>Time zone + locale/keyboard from this PC for unattended Setup (WinPE + specialize).</summary> #>
    $tz = (Get-TimeZone).Id
    $systemLocaleName = (Get-WinSystemLocale).Name
    $userLocaleName = [System.Globalization.CultureInfo]::CurrentCulture.Name
    if ([string]::IsNullOrWhiteSpace($userLocaleName)) { $userLocaleName = $systemLocaleName }
    $uiLanguageName = [System.Globalization.CultureInfo]::CurrentUICulture.Name
    if ([string]::IsNullOrWhiteSpace($uiLanguageName) -or $uiLanguageName -in @('en', 'en-001')) {
        $uiLanguageName = 'en-US'
    }
    $homeLocationGeoId = Resolve-WinMintRegionGeoId -CultureName $userLocaleName
    $inputLocale = $userLocaleName
    $keyboardLayouts = [System.Collections.Generic.List[string]]::new()
    try {
        $ull = @(Get-WinUserLanguageList -ErrorAction Stop)
        if ($ull.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$ull[0].LanguageTag)) {
            $firstLanguage = [string]$ull[0].LanguageTag
            if ($firstLanguage -notin @('en', 'en-001')) { $uiLanguageName = $firstLanguage }
        }
        foreach ($language in $ull) {
            foreach ($tip in [string[]]@($language.InputMethodTips)) {
                if ([string]::IsNullOrWhiteSpace($tip)) { continue }
                $layout = $tip.Trim()
                if (-not $keyboardLayouts.Contains($layout)) {
                    $keyboardLayouts.Add($layout) | Out-Null
                }
            }
        }
        if ($keyboardLayouts.Count -gt 0) {
            $inputLocale = ($keyboardLayouts.ToArray() -join ';')
        }
    }
    catch {
        Write-Verbose "Get-WinUserLanguageList unavailable; InputLocale defaults to system locale name: $($_.Exception.Message)"
    }
    return [pscustomobject]@{
        TimeZoneId           = $tz
        InputLocale          = $inputLocale
        SystemLocale         = $systemLocaleName
        UILanguage           = $uiLanguageName
        UILanguageFallback   = $uiLanguageName
        UserLocale           = $userLocaleName
        HomeLocationGeoId    = $homeLocationGeoId
    }
}

function Get-KeyboardLayoutChoice {
    <# <summary>All installed keyboard layouts from HKLM, returning friendly labels and internal InputLocale values.</summary> #>
    $list = [System.Collections.Generic.List[object]]::new()
    $regBase = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Keyboard Layouts'
    if (-not (Test-Path -LiteralPath $regBase)) { return @() }
    foreach ($key in Get-ChildItem -LiteralPath $regBase -ErrorAction SilentlyContinue) {
        $kid = $key.PSChildName
        if ($kid -notmatch '^[0-9A-Fa-f]{8}$') { continue }
        try {
            $u = [uint32]::Parse($kid, [System.Globalization.NumberStyles]::HexNumber)
            $langPart = [int]($u -band 0xFFFF)
            $inputLocale = ('{0:x4}:{1}' -f $langPart, $kid).ToLowerInvariant()
        }
        catch {
            Write-Verbose "Skipping keyboard layout id '$kid': $($_.Exception.Message)"
            continue
        }
        $p = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        $text = $p.'Layout Text'
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $cultureLabel = ''
        try {
            $cultureLabel = [System.Globalization.CultureInfo]::GetCultureInfo($langPart).DisplayName
        }
        catch {
            Write-Verbose "No culture display name for keyboard layout '$kid': $($_.Exception.Message)"
        }
        $label = if ([string]::IsNullOrWhiteSpace($cultureLabel) -or $text -like "$cultureLabel*") {
            $text
        } else {
            "$cultureLabel - $text"
        }
        $list.Add([pscustomobject]@{ InputLocale = $inputLocale; Label = $label }) | Out-Null
    }
    return @(
        $list |
            Group-Object InputLocale |
            ForEach-Object { @($_.Group | Sort-Object Label)[0] } |
            Sort-Object Label
    )
}

function Get-SpecificCultureChoice {
    <# <summary>All specific cultures for UILanguage / system locale selection.</summary> #>
    return @(
        [System.Globalization.CultureInfo]::GetCultures([System.Globalization.CultureTypes]::SpecificCultures) |
            Where-Object { $_.LCID -ne 127 -and -not [string]::IsNullOrWhiteSpace($_.Name) } |
            Group-Object Name |
            ForEach-Object { @($_.Group)[0] } |
            Sort-Object DisplayName |
            ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; Label = "$($_.DisplayName) — $($_.Name)" }
            }
    )
}

function Get-TimeZoneChoice {
    <# <summary>All IANA-style time zones on this Windows build.</summary> #>
    return @(
        [System.TimeZoneInfo]::GetSystemTimeZones() |
            Sort-Object DisplayName |
            ForEach-Object { [pscustomobject]@{ Id = $_.Id; Label = "$($_.DisplayName) — $($_.Id)" } }
    )
}

function Split-Win11IsoSpectreChoiceEmDashSuffix {
    <# <summary>When Read-SpectreSelection returns a plain label string (not the original choice object), recover the payload after " — " (em dash).</summary> #>
    param([Parameter(Mandatory)][string]$LabelText)
    $sep = [string]::new(@([char]0x0020, [char]0x2014, [char]0x0020))
    $i = $LabelText.LastIndexOf($sep, [StringComparison]::Ordinal)
    if ($i -ge 0) { return $LabelText.Substring($i + $sep.Length).Trim() }
    return $LabelText.Trim()
}

function Invoke-GoldImageRegionalPrompt {
    <# <summary>Searchable lists: time zone, locale, keyboard (WinPE International settings).</summary> #>
    Write-SectionHeader 'Regional defaults (gold image)'
    $pg = $script:Win11IsoSpectrePageSizeList
    $tzSel = Read-SpectreSelection -Message '[bold]Time zone[/] [dim](IANA id · autounattend; search below)[/]' -Choices (Get-TimeZoneChoice) -ChoiceLabelProperty Label -EnableSearch -PageSize $pg
    $cSel = Read-SpectreSelection -Message '[bold]Language & region[/] [dim](culture / locale string · Setup + OOBE)[/]' -Choices (Get-SpecificCultureChoice) -ChoiceLabelProperty Label -EnableSearch -PageSize $pg
    $kSel = Read-SpectreSelection -Message '[bold]Default keyboard[/] [dim](layout identifier · WinPE + first boot)[/]' -Choices (Get-KeyboardLayoutChoice) -ChoiceLabelProperty Label -EnableSearch -PageSize $pg

    $tzId = if ($null -eq $tzSel) {
        throw 'Time zone selection returned null.'
    }
    elseif ($tzSel -is [string]) {
        Split-Win11IsoSpectreChoiceEmDashSuffix -LabelText $tzSel
    }
    elseif ('Id' -in @($tzSel.PSObject.Properties.Name)) {
        [string]$tzSel.Id
    }
    else {
        throw "Unexpected time zone selection type: $($tzSel.GetType().FullName)"
    }
    if ([string]::IsNullOrWhiteSpace($tzId)) { throw 'Could not resolve a time zone id from the selection.' }

    $cultureName = if ($null -eq $cSel) {
        throw 'Locale selection returned null.'
    }
    elseif ($cSel -is [string]) {
        Split-Win11IsoSpectreChoiceEmDashSuffix -LabelText $cSel
    }
    elseif ('Name' -in @($cSel.PSObject.Properties.Name)) {
        [string]$cSel.Name
    }
    else {
        throw "Unexpected locale selection type: $($cSel.GetType().FullName)"
    }
    if ([string]::IsNullOrWhiteSpace($cultureName)) { throw 'Could not resolve a culture name from the selection.' }

    $inputLocale = if ($null -eq $kSel) {
        throw 'Keyboard selection returned null.'
    }
    elseif ($kSel -is [string]) {
        Split-Win11IsoSpectreChoiceEmDashSuffix -LabelText $kSel
    }
    elseif ('InputLocale' -in @($kSel.PSObject.Properties.Name)) {
        [string]$kSel.InputLocale
    }
    else {
        throw "Unexpected keyboard selection type: $($kSel.GetType().FullName)"
    }
    if ([string]::IsNullOrWhiteSpace($inputLocale)) { throw 'Could not resolve an input locale from the selection.' }

    return [pscustomobject]@{
        TimeZoneId           = $tzId
        InputLocale          = $inputLocale
        SystemLocale         = $cultureName
        UILanguage           = $cultureName
        UILanguageFallback   = $cultureName
        UserLocale           = $cultureName
        HomeLocationGeoId    = Resolve-WinMintRegionGeoId -CultureName $cultureName
    }
}

function Merge-UnattendInternationalXml {
    param(
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNamespaceManager]$NsMgr,
        [string]$InputLocale,
        [string]$SystemLocale,
        [string]$UILanguage,
        [string]$UILanguageFallback,
        [string]$UserLocale
    )
    $wpe = $XmlDoc.SelectSingleNode('//u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-International-Core-WinPE"]', $NsMgr)
    if ($wpe) {
        foreach ($pair in @(
                @{ El = 'InputLocale'; V = $InputLocale }
                @{ El = 'SystemLocale'; V = $SystemLocale }
                @{ El = 'UILanguage'; V = $UILanguage }
                @{ El = 'UILanguageFallback'; V = $UILanguageFallback }
                @{ El = 'UserLocale'; V = $UserLocale }
            )) {
            if ([string]::IsNullOrWhiteSpace($pair.V)) { continue }
            $xn = $wpe.SelectSingleNode("u:$($pair.El)", $NsMgr)
            if ($null -ne $xn) { $xn.InnerText = $pair.V }
        }
    }
    else {
        LogWarn 'autounattend.xml: no WinPE International-Core block; locale/keyboard might still prompt in WinPE.'
    }

    # specialize and oobeSystem both carry an International-Core block. The
    # oobeSystem block is what suppresses the Windows 11 OOBE region/keyboard
    # page; without it the otherwise-unattended install stops there. Both use the
    # same setup-region locales (the DMA latch when enabled); FirstLogon restores
    # the user's configured region afterward.
    foreach ($pass in @('specialize', 'oobeSystem')) {
        $node = $XmlDoc.SelectSingleNode("//u:settings[@pass=`"$pass`"]/u:component[@name=`"Microsoft-Windows-International-Core`"]", $NsMgr)
        if (-not $node) {
            LogWarn "autounattend.xml: no $pass International-Core block (locale merge may be incomplete; OOBE could prompt for region)."
            continue
        }
        foreach ($pair in @(
                @{ El = 'InputLocale'; V = $InputLocale }
                @{ El = 'SystemLocale'; V = $SystemLocale }
                @{ El = 'UILanguage'; V = $UILanguage }
                @{ El = 'UILanguageFallback'; V = $UILanguageFallback }
                @{ El = 'UserLocale'; V = $UserLocale }
            )) {
            if ([string]::IsNullOrWhiteSpace($pair.V)) { continue }
            $xn = $node.SelectSingleNode("u:$($pair.El)", $NsMgr)
            if ($null -ne $xn) { $xn.InnerText = $pair.V }
        }
    }
}

function Get-Win11IsoDiskLayoutExtraMarkup {
    <# <summary>Second-line Spectre markup for configuration review.</summary> #>
    param([bool]$AutoWipeDisk)
    if (-not $AutoWipeDisk) { return '' }
    return @(
        '[silver]Primary disk layout —[/]'
        '[dim]EFI (1 GB) · MSR (16 MB) · Windows C: · WinRE Recovery (1 GB).[/]'
        '[dim]Push-button reset and Windows Recovery Environment are fully functional.[/]'
    ) -join ' '
}
