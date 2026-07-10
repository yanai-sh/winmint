#Requires -Version 5.1

function Set-WinMintFirstLogonInputLanguages {
    # Set the user language list to [display language] + [secondary input languages], with the
    # display language ALWAYS first (primary) and explicitly pinned as the UI language. This is
    # how a secondary keyboard (e.g. Hebrew) is added without ever changing the display/system
    # language. Uses the official International cmdlets, not registry pokes.
    param(
        [string]$DisplayLanguage = 'en-US',
        [string[]]$SecondaryInputLanguages = @()
    )
    if (-not (Get-Command Set-WinUserLanguageList -ErrorAction SilentlyContinue)) { return }
    if ([string]::IsNullOrWhiteSpace($DisplayLanguage)) { $DisplayLanguage = 'en-US' }
    $displayPrimary = (($DisplayLanguage -split '-')[0]).ToLowerInvariant()
    $list = [System.Collections.Generic.List[string]]::new()
    $list.Add($DisplayLanguage)
    foreach ($lang in @($SecondaryInputLanguages)) {
        $tag = [string]$lang
        if ([string]::IsNullOrWhiteSpace($tag)) { continue }
        if ((($tag -split '-')[0]).ToLowerInvariant() -eq $displayPrimary) { continue }  # never displace the display language
        if ($list -notcontains $tag) { $list.Add($tag) }
    }
    Set-WinUserLanguageList -LanguageList @($list) -Force -ErrorAction Stop
    # Hard-pin the UI/display language so a secondary input language can never become the
    # display language (the user requirement: type Hebrew, but the system stays English).
    try { Set-WinUILanguageOverride -Language $DisplayLanguage -ErrorAction SilentlyContinue } catch { }
    "$(Get-Date -Format 'o') Set user language list to: $(@($list) -join ', ') (display pinned to $DisplayLanguage)." |
        Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
}


function Set-WinMintFirstLogonLocationServicesPolicy {
    param([bool]$Enabled)

    $policyPath = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'
    $findMyDevicePath = 'HKLM\SOFTWARE\Policies\Microsoft\FindMyDevice'
    $machineConsentPath = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
    $userConsentPath = 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
    $sensorOverridePath = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}'
    if ($Enabled) {
        foreach ($name in @('DisableLocation', 'DisableWindowsLocationProvider', 'DisableLocationScripting')) {
            Invoke-WinMintFirstLogonReg -Arguments @('delete', $policyPath, '/v', $name, '/f') -AllowFailure
        }
        Invoke-WinMintFirstLogonReg -Arguments @('delete', $findMyDevicePath, '/v', 'AllowFindMyDevice', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $machineConsentPath, '/v', 'Value', '/t', 'REG_SZ', '/d', 'Allow', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $userConsentPath, '/v', 'Value', '/t', 'REG_SZ', '/d', 'Allow', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $sensorOverridePath, '/v', 'SensorPermissionState', '/t', 'REG_DWORD', '/d', '1', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', 'HKLM\SYSTEM\CurrentControlSet\Services\lfsvc', '/v', 'Start', '/t', 'REG_DWORD', '/d', '3', '/f') -AllowFailure
        try { Set-Service -Name lfsvc -StartupType Manual -ErrorAction SilentlyContinue } catch { }
    }
    else {
        Invoke-WinMintFirstLogonReg -Arguments @('add', $policyPath, '/v', 'DisableLocation', '/t', 'REG_DWORD', '/d', '1', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $policyPath, '/v', 'DisableWindowsLocationProvider', '/t', 'REG_DWORD', '/d', '1', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $policyPath, '/v', 'DisableLocationScripting', '/t', 'REG_DWORD', '/d', '1', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $findMyDevicePath, '/v', 'AllowFindMyDevice', '/t', 'REG_DWORD', '/d', '0', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $machineConsentPath, '/v', 'Value', '/t', 'REG_SZ', '/d', 'Deny', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $userConsentPath, '/v', 'Value', '/t', 'REG_SZ', '/d', 'Deny', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $sensorOverridePath, '/v', 'SensorPermissionState', '/t', 'REG_DWORD', '/d', '0', '/f') -AllowFailure
    }
}


function Restore-WinMintDmaRegionalDefaults {
    $setupProfile = Read-WinMintFirstLogonSetupProfile
    $dmaInterop = [bool](Get-WinMintFirstLogonNestedProfileValue -BuildProfile $setupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'enabled' -Default $false)
    $reportPath = Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon_RegionalRestore.json'
    if (-not $dmaInterop) {
        $report = [ordered]@{
            enabled = $false
            compliant = $true
            errors = @()
        }
        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
        return [pscustomobject]@{ Enabled = $false; Compliant = $true; Report = $reportPath }
    }

    $errors = [System.Collections.Generic.List[string]]::new()
    $setupCountry = [string](Get-WinMintFirstLogonNestedProfileValue -BuildProfile $setupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'setupCountry' -Default 'Ireland')
    $setupUserLocale = [string](Get-WinMintFirstLogonNestedProfileValue -BuildProfile $setupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'setupUserLocale' -Default 'en-IE')
    $setupGeoId = [int](Get-WinMintFirstLogonNestedProfileValue -BuildProfile $setupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'setupHomeLocationGeoId' -Default 68)
    $restoreTimeZoneId = [string](Get-WinMintFirstLogonNestedProfileValue -BuildProfile $setupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'restoreTimeZoneId' -Default '')
    $restoreGeoId = [int](Get-WinMintFirstLogonNestedProfileValue -BuildProfile $setupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'restoreHomeLocationGeoId' -Default 244)
    $restoreUserLocale = [string](Get-WinMintFirstLogonNestedProfileValue -BuildProfile $setupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'restoreUserLocale' -Default '')
    $restoreLocationServices = [bool](Get-WinMintFirstLogonNestedProfileValue -BuildProfile $setupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'restoreLocationServices' -Default $true)
    if ([string]::IsNullOrWhiteSpace($restoreTimeZoneId) -and $setupProfile -and $setupProfile.PSObject.Properties['regional']) {
        $regionalTimeZoneProp = $setupProfile.regional.PSObject.Properties['timeZoneId']
        if ($regionalTimeZoneProp) { $restoreTimeZoneId = [string]$regionalTimeZoneProp.Value }
    }
    if (-not [string]::IsNullOrWhiteSpace($restoreTimeZoneId)) {
        try {
            Set-TimeZone -Id $restoreTimeZoneId -ErrorAction Stop
            "$(Get-Date -Format 'o') Restored Windows time zone to $restoreTimeZoneId after DMA setup." |
                Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
        }
        catch {
            $errors.Add("Time zone restore failed for ${restoreTimeZoneId}: $_") | Out-Null
            Write-WinMintFirstLogonError "Time zone restore failed for ${restoreTimeZoneId}: $_"
        }
    }
    try {
        Set-WinHomeLocation -GeoId $restoreGeoId -ErrorAction Stop
        "$(Get-Date -Format 'o') Restored Windows home location GeoID to $restoreGeoId after DMA setup." |
            Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
    }
    catch {
        $errors.Add("Home location restore failed for GeoID ${restoreGeoId}: $_") | Out-Null
        Write-WinMintFirstLogonError "Home location restore failed for GeoID ${restoreGeoId}: $_"
    }
    if (-not [string]::IsNullOrWhiteSpace($restoreUserLocale)) {
        try {
            Set-Culture -CultureInfo $restoreUserLocale -ErrorAction Stop
            "$(Get-Date -Format 'o') Restored user culture to $restoreUserLocale after DMA setup." |
                Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
        }
        catch {
            $errors.Add("User culture restore failed for ${restoreUserLocale}: $_") | Out-Null
            Write-WinMintFirstLogonError "User culture restore failed for ${restoreUserLocale}: $_"
        }
        # Rebuild the user language list as [display language] + [secondary input languages].
        # This drops the DMA en-IE entry AND adds any configured secondary keyboards (e.g.
        # he-IL), with the display language pinned so it can never switch. Done BEFORE the
        # system/new-user copy below so the result propagates to the welcome screen + new-user
        # defaults.
        $secondaryInputLanguages = @()
        if ($setupProfile -and $setupProfile.PSObject.Properties['regional'] -and $setupProfile.regional.PSObject.Properties['secondaryInputLanguages']) {
            $secondaryInputLanguages = @($setupProfile.regional.secondaryInputLanguages)
        }
        try {
            Set-WinMintFirstLogonInputLanguages -DisplayLanguage $restoreUserLocale -SecondaryInputLanguages $secondaryInputLanguages
        }
        catch {
            $errors.Add("Language list rebuild failed: $_") | Out-Null
            Write-WinMintFirstLogonError "Language list rebuild failed: $_"
        }
    }
    try {
        if (Get-Command Copy-UserInternationalSettingsToSystem -ErrorAction SilentlyContinue) {
            Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true -ErrorAction Stop
            "$(Get-Date -Format 'o') Copied restored international settings to system and new-user defaults." |
                Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
        }
    }
    catch {
        $errors.Add("International settings copy failed: $_") | Out-Null
        Write-WinMintFirstLogonError "International settings copy failed: $_"
    }
    try { Set-WinMintFirstLogonLocationServicesPolicy -Enabled $restoreLocationServices }
    catch {
        $errors.Add("Location services policy restore failed: $_") | Out-Null
        Write-WinMintFirstLogonError "Location services policy restore failed: $_"
    }
    if (-not $restoreLocationServices) {
        try {
            Invoke-WinMintFirstLogonReg -Arguments @('add', 'HKLM\SYSTEM\CurrentControlSet\Services\tzautoupdate', '/v', 'Start', '/t', 'REG_DWORD', '/d', '4', '/f') -AllowFailure
            Stop-Service -Name tzautoupdate -ErrorAction SilentlyContinue
            Set-Service -Name tzautoupdate -StartupType Disabled -ErrorAction Stop
            "$(Get-Date -Format 'o') Disabled Auto Time Zone Updater because location services are off." |
                Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
        }
        catch {
            $errors.Add("Auto Time Zone Updater disable failed after DMA setup: $_") | Out-Null
            Write-WinMintFirstLogonError "Auto Time Zone Updater disable failed after DMA setup: $_"
        }
    }
    else {
        try {
            Invoke-WinMintFirstLogonReg -Arguments @('add', 'HKLM\SYSTEM\CurrentControlSet\Services\tzautoupdate', '/v', 'Start', '/t', 'REG_DWORD', '/d', '3', '/f') -AllowFailure
            Set-Service -Name tzautoupdate -StartupType Manual -ErrorAction Stop
        }
        catch {
            $errors.Add("Auto Time Zone Updater enable failed after DMA setup: $_") | Out-Null
            Write-WinMintFirstLogonError "Auto Time Zone Updater enable failed after DMA setup: $_"
        }
        "$(Get-Date -Format 'o') Enabled Auto Time Zone Updater because location services are on." |
            Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
    }

    $observedTimeZone = $null
    $observedHomeLocation = $null
    $observedCulture = $null
    $observedPrimaryLanguageTag = ''
    $observedUiLanguageOverride = ''
    try { $observedTimeZone = Get-TimeZone } catch { $errors.Add("Time zone verification failed: $_") | Out-Null }
    try { $observedHomeLocation = Get-WinHomeLocation } catch { $errors.Add("Home location verification failed: $_") | Out-Null }
    try { $observedCulture = Get-Culture } catch { $errors.Add("Culture verification failed: $_") | Out-Null }
    try {
        if (Get-Command Get-WinUserLanguageList -ErrorAction SilentlyContinue) {
            $languageList = @(Get-WinUserLanguageList -ErrorAction Stop)
            if ($languageList.Count -gt 0) {
                $observedPrimaryLanguageTag = [string]$languageList[0].LanguageTag
            }
        }
    }
    catch {
        $errors.Add("Primary language list verification failed: $_") | Out-Null
    }
    try {
        if (Get-Command Get-WinUILanguageOverride -ErrorAction SilentlyContinue) {
            $uiOverride = Get-WinUILanguageOverride -ErrorAction Stop
            if ($uiOverride) { $observedUiLanguageOverride = [string]$uiOverride }
        }
    }
    catch {
        $errors.Add("UI language override verification failed: $_") | Out-Null
    }

    $observedGeoIdText = if ($observedHomeLocation) { [string]([int]$observedHomeLocation.GeoId) } else { '0' }
    $observedTimeZoneText = if ($observedTimeZone) { [string]$observedTimeZone.Id } else { '' }
    $observedCultureText = if ($observedCulture) { [string]$observedCulture.Name } else { '' }
    if ($restoreGeoId -gt 0 -and (-not $observedHomeLocation -or [int]$observedHomeLocation.GeoId -ne $restoreGeoId)) {
        $errors.Add("Current home location GeoID '$observedGeoIdText' does not match restore GeoID '$restoreGeoId'.") | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($restoreTimeZoneId) -and (-not $observedTimeZone -or [string]$observedTimeZone.Id -ne $restoreTimeZoneId)) {
        $errors.Add("Current time zone '$observedTimeZoneText' does not match restore time zone '$restoreTimeZoneId'.") | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($restoreUserLocale)) {
        $languageConfigured = (-not [string]::IsNullOrWhiteSpace($observedPrimaryLanguageTag) -and $observedPrimaryLanguageTag -eq $restoreUserLocale)
        $overrideConfigured = (-not [string]::IsNullOrWhiteSpace($observedUiLanguageOverride) -and $observedUiLanguageOverride -eq $restoreUserLocale)
        if (-not $languageConfigured -and -not $overrideConfigured) {
            $errors.Add("Configured display language '$observedPrimaryLanguageTag' / UI override '$observedUiLanguageOverride' does not match restore culture '$restoreUserLocale'.") | Out-Null
        }
    }

    $report = [ordered]@{
        enabled = $true
        requested = [ordered]@{
            setupCountry = $setupCountry
            setupUserLocale = $setupUserLocale
            setupHomeLocationGeoId = $setupGeoId
            restoreTimeZoneId = $restoreTimeZoneId
            restoreUserLocale = $restoreUserLocale
            restoreHomeLocationGeoId = $restoreGeoId
            restoreLocationServices = $restoreLocationServices
        }
        observed = [ordered]@{
            timeZoneId = if ($observedTimeZone) { [string]$observedTimeZone.Id } else { '' }
            culture = if ($observedCulture) { [string]$observedCulture.Name } else { '' }
            primaryLanguageTag = $observedPrimaryLanguageTag
            uiLanguageOverride = $observedUiLanguageOverride
            homeLocationGeoId = if ($observedHomeLocation) { [int]$observedHomeLocation.GeoId } else { 0 }
            homeLocation = if ($observedHomeLocation) { [string]$observedHomeLocation.HomeLocation } else { '' }
            tzautoupdate = Get-WinMintFirstLogonServiceSnapshot -Name 'tzautoupdate'
            locationService = Get-WinMintFirstLogonServiceSnapshot -Name 'lfsvc'
        }
        compliant = ($errors.Count -eq 0)
        errors = $errors.ToArray()
    }
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    return [pscustomobject]@{ Enabled = $true; Compliant = [bool]$report.compliant; Report = $reportPath; Errors = $errors.ToArray() }
}


function Repair-WinMintFirstLogonKnownFolders {
    $errors = [System.Collections.Generic.List[string]]::new()
    $userShellFolders = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $shellFolders = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'
    $knownFolders = @(
        @{ Name = 'Desktop'; Local = 'Desktop' },
        @{ Name = 'Personal'; Local = 'Documents' },
        @{ Name = 'My Pictures'; Local = 'Pictures' },
        @{ Name = 'My Music'; Local = 'Music' },
        @{ Name = 'My Video'; Local = 'Videos' },
        @{ Name = '{374DE290-123F-4565-9164-39C4925E467B}'; Local = 'Downloads' }
    )

    foreach ($folder in @('Desktop', 'Documents', 'Downloads', 'Pictures', 'Music', 'Videos')) {
        New-Item -ItemType Directory -Path (Join-Path $env:USERPROFILE $folder) -Force -ErrorAction SilentlyContinue | Out-Null
    }

    foreach ($known in $knownFolders) {
        $expandValue = "%USERPROFILE%\$($known.Local)"
        $absoluteValue = Join-Path $env:USERPROFILE $known.Local
        try {
            Invoke-WinMintFirstLogonReg -Arguments @('add', $userShellFolders, '/v', $known.Name, '/t', 'REG_EXPAND_SZ', '/d', $expandValue, '/f') -AllowFailure
            Invoke-WinMintFirstLogonReg -Arguments @('add', $shellFolders, '/v', $known.Name, '/t', 'REG_SZ', '/d', $absoluteValue, '/f') -AllowFailure
        }
        catch {
            $errors.Add("Known folder repair failed for $($known.Name): $_") | Out-Null
        }
    }

    $userShell = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
    $shell = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' -ErrorAction SilentlyContinue
    $observed = [ordered]@{}
    foreach ($known in $knownFolders) {
        $userProp = if ($userShell) { $userShell.PSObject.Properties[$known.Name] } else { $null }
        $shellProp = if ($shell) { $shell.PSObject.Properties[$known.Name] } else { $null }
        $observed[$known.Name] = [ordered]@{
            userShellFolder = if ($userProp) { [string]$userProp.Value } else { '' }
            shellFolder = if ($shellProp) { [string]$shellProp.Value } else { '' }
        }
    }

    $report = [ordered]@{
        timestamp = Get-Date -Format o
        expectedRoot = '%USERPROFILE%'
        observed = $observed
        compliant = ($errors.Count -eq 0)
        errors = $errors.ToArray()
    }
    $path = Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon_KnownFolders.json'
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    "$(Get-Date -Format 'o') Known folder verification written to $path" | Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
}


