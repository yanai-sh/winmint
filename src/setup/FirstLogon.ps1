#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Auto','UI','Console','Headless')]
    [string]$AgentMode = 'Auto'
)

$ErrorActionPreference = 'Continue'
# Logs land in ProgramData (Administrators-readable) rather than C:\Windows\Setup\Scripts
# (Users-readable). Setup\Scripts holds the staged agent payload; logs do not belong there.
$logDir = Join-Path $env:ProgramData 'WinMint\Logs'
$null = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue
$payloadDir = 'C:\Windows\Setup\Scripts'  # where the staged agent + state file live
"$(Get-Date -Format 'o') FirstLogon.ps1 start" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
try { Start-Transcript -Path (Join-Path $logDir 'FirstLogon_transcript.log') -Append -ErrorAction SilentlyContinue | Out-Null } catch { }

function Write-WinMintFirstLogonError {
    param([string]$Message)
    "$(Get-Date -Format 'o') $Message" | Out-File (Join-Path $logDir 'FirstLogon_errors.log') -Append
}

function Save-WinMintFirstLogonState {
    param([hashtable]$State)
    $path = Join-Path $logDir 'FirstLogonState.json'
    $tmp = "$path.tmp"
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tmp -Encoding UTF8
    $null = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

function Read-WinMintFirstLogonSetupProfile {
    $setupProfilePath = Join-Path $payloadDir 'WinMintSetupProfile.json'
    try {
        if (Test-Path -LiteralPath $setupProfilePath) {
            return Get-Content -LiteralPath $setupProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    }
    catch {
        Write-WinMintFirstLogonError "Setup profile read failed: $_"
    }
    return $null
}

function Get-WinMintFirstLogonNestedProfileValue {
    param(
        [object]$BuildProfile,
        [string]$Section,
        [string]$Nested,
        [string]$Name,
        $Default = $null
    )

    if (-not $BuildProfile) { return $Default }
    $sectionProp = $BuildProfile.PSObject.Properties[$Section]
    if (-not $sectionProp) { return $Default }
    $nestedProp = $sectionProp.Value.PSObject.Properties[$Nested]
    if (-not $nestedProp) { return $Default }
    $valueProp = $nestedProp.Value.PSObject.Properties[$Name]
    if (-not $valueProp) { return $Default }
    return $valueProp.Value
}

function Resolve-WinMintPowerShellHost {
    $pwsh = "$env:ProgramFiles\PowerShell\7\pwsh.exe"
    if (Test-Path -LiteralPath $pwsh) { return $pwsh }
    $sysnative = Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $sysnative) { return $sysnative }
    $system32 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $system32) { return $system32 }
    return 'powershell.exe'
}

function Resolve-WinMintFirstLogonAgentMode {
    param(
        [Parameter(Mandatory)][string]$RequestedMode,
        [Parameter(Mandatory)][string]$AgentUIPath
    )

    $envMode = [string]$env:WINMINT_FIRSTLOGON_MODE
    if (-not [string]::IsNullOrWhiteSpace($envMode)) {
        switch -Regex ($envMode.Trim()) {
            '^(headless|none|no-ui)$' { return 'Headless' }
            '^(console|terminal)$' { return 'Console' }
            '^(ui|wpf|splash)$' { return 'UI' }
        }
    }

    if ($RequestedMode -ne 'Auto') { return $RequestedMode }
    if (Test-Path -LiteralPath $AgentUIPath) { return 'UI' }
    return 'Console'
}

function Invoke-WinMintFirstLogonReg {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure
    )
    $out = & reg.exe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        Write-WinMintFirstLogonError "reg.exe $($Arguments -join ' ') exited $LASTEXITCODE`n$($out | Out-String)"
    }
}

function Set-WinMintFirstLogonDesktopDefaults {
    $wallpaperPath = 'C:\Windows\Web\Wallpaper\WinMint\WinMint-Bloom-OLED.png'
    $desktopKey = 'HKCU\Control Panel\Desktop'
    $personalizeKey = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $dwmKey = 'HKCU\Software\Microsoft\Windows\DWM'

    Invoke-WinMintFirstLogonReg -Arguments @('add', $personalizeKey, '/v', 'AppsUseLightTheme', '/t', 'REG_DWORD', '/d', '0', '/f') -AllowFailure
    Invoke-WinMintFirstLogonReg -Arguments @('add', $personalizeKey, '/v', 'SystemUsesLightTheme', '/t', 'REG_DWORD', '/d', '0', '/f') -AllowFailure
    Invoke-WinMintFirstLogonReg -Arguments @('add', $dwmKey, '/v', 'ColorPrevalence', '/t', 'REG_DWORD', '/d', '0', '/f') -AllowFailure

    if (Test-Path -LiteralPath $wallpaperPath) {
        Invoke-WinMintFirstLogonReg -Arguments @('add', $desktopKey, '/v', 'Wallpaper', '/t', 'REG_SZ', '/d', $wallpaperPath, '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $desktopKey, '/v', 'WallpaperStyle', '/t', 'REG_SZ', '/d', '10', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $desktopKey, '/v', 'TileWallpaper', '/t', 'REG_SZ', '/d', '0', '/f') -AllowFailure
        Add-Type -Namespace WinMint.Native -Name User32 -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern bool SystemParametersInfo(int uiAction, int uiParam, string pvParam, int fWinIni);
'@ -ErrorAction SilentlyContinue
        [WinMint.Native.User32]::SystemParametersInfo(20, 0, $wallpaperPath, 3) | Out-Null
    }
}

function Set-WinMintFirstLogonRetry {
    $runOnce = 'HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    $exe = Resolve-WinMintPowerShellHost
    $command = "`"$exe`" -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Invoke-WinMintFirstLogonReg -Arguments @('add', $runOnce, '/v', 'WinMintFirstLogonRetry', '/t', 'REG_SZ', '/d', $command, '/f')
}

function Clear-WinMintFirstLogonRetry {
    $runOnce = 'HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    Invoke-WinMintFirstLogonReg -Arguments @('delete', $runOnce, '/v', 'WinMintFirstLogonRetry', '/f') -AllowFailure
}

function Clear-WinMintAutoLogonPassword {
    # Removes the plaintext DefaultPassword and AutoLogonCount from the registry.
    # Called early in this script — Windows already read the password once for the
    # autologon that brought us here, so the value can be deleted now even if the
    # agent later fails. RunOnce drives all subsequent retries on next logon.
    $winlogon = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    foreach ($name in @('DefaultPassword', 'AutoLogonCount')) {
        Invoke-WinMintFirstLogonReg -Arguments @('delete', $winlogon, '/v', $name, '/f') -AllowFailure
    }
}

function Set-WinMintFirstLogonLocationServicesPolicy {
    param([bool]$Enabled)

    $policyPath = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'
    $findMyDevicePath = 'HKLM\SOFTWARE\Policies\Microsoft\FindMyDevice'
    if ($Enabled) {
        foreach ($name in @('DisableLocation', 'DisableWindowsLocationProvider', 'DisableLocationScripting')) {
            Invoke-WinMintFirstLogonReg -Arguments @('delete', $policyPath, '/v', $name, '/f') -AllowFailure
        }
        Invoke-WinMintFirstLogonReg -Arguments @('delete', $findMyDevicePath, '/v', 'AllowFindMyDevice', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', 'HKLM\SYSTEM\CurrentControlSet\Services\lfsvc', '/v', 'Start', '/t', 'REG_DWORD', '/d', '3', '/f') -AllowFailure
        try { Set-Service -Name lfsvc -StartupType Manual -ErrorAction SilentlyContinue } catch { }
    }
    else {
        Invoke-WinMintFirstLogonReg -Arguments @('add', $policyPath, '/v', 'DisableLocation', '/t', 'REG_DWORD', '/d', '1', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $policyPath, '/v', 'DisableWindowsLocationProvider', '/t', 'REG_DWORD', '/d', '1', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $policyPath, '/v', 'DisableLocationScripting', '/t', 'REG_DWORD', '/d', '1', '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $findMyDevicePath, '/v', 'AllowFindMyDevice', '/t', 'REG_DWORD', '/d', '0', '/f') -AllowFailure
    }
}

function Get-WinMintFirstLogonServiceSnapshot {
    param([string]$Name)
    try {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        $start = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -Name Start -ErrorAction SilentlyContinue).Start
        if (-not $svc) { return [ordered]@{ name = $Name; present = $false; status = ''; start = $start } }
        return [ordered]@{ name = $Name; present = $true; status = [string]$svc.Status; startType = [string]$svc.StartType; start = $start }
    }
    catch {
        return [ordered]@{ name = $Name; present = $false; status = ''; startType = ''; start = $null; error = $_.Exception.Message }
    }
}

function Restore-WinMintDmaRegionalDefaults {
    $setupProfile = Read-WinMintFirstLogonSetupProfile
    $dmaInterop = [bool](Get-WinMintFirstLogonNestedProfileValue -BuildProfile $setupProfile -Section 'regional' -Nested 'dmaInterop' -Name 'enabled' -Default $false)
    $reportPath = Join-Path $logDir 'FirstLogon_RegionalRestore.json'
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
                Out-File (Join-Path $logDir 'FirstLogon.log') -Append
        }
        catch {
            $errors.Add("Time zone restore failed for ${restoreTimeZoneId}: $_") | Out-Null
            Write-WinMintFirstLogonError "Time zone restore failed for ${restoreTimeZoneId}: $_"
        }
    }
    try {
        Set-WinHomeLocation -GeoId $restoreGeoId -ErrorAction Stop
        "$(Get-Date -Format 'o') Restored Windows home location GeoID to $restoreGeoId after DMA setup." |
            Out-File (Join-Path $logDir 'FirstLogon.log') -Append
    }
    catch {
        $errors.Add("Home location restore failed for GeoID ${restoreGeoId}: $_") | Out-Null
        Write-WinMintFirstLogonError "Home location restore failed for GeoID ${restoreGeoId}: $_"
    }
    if (-not [string]::IsNullOrWhiteSpace($restoreUserLocale)) {
        try {
            Set-Culture -CultureInfo $restoreUserLocale -ErrorAction Stop
            "$(Get-Date -Format 'o') Restored user culture to $restoreUserLocale after DMA setup." |
                Out-File (Join-Path $logDir 'FirstLogon.log') -Append
        }
        catch {
            $errors.Add("User culture restore failed for ${restoreUserLocale}: $_") | Out-Null
            Write-WinMintFirstLogonError "User culture restore failed for ${restoreUserLocale}: $_"
        }
    }
    try {
        if (Get-Command Copy-UserInternationalSettingsToSystem -ErrorAction SilentlyContinue) {
            Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true -ErrorAction Stop
            "$(Get-Date -Format 'o') Copied restored international settings to system and new-user defaults." |
                Out-File (Join-Path $logDir 'FirstLogon.log') -Append
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
    try {
        Invoke-WinMintFirstLogonReg -Arguments @('add', 'HKLM\SYSTEM\CurrentControlSet\Services\tzautoupdate', '/v', 'Start', '/t', 'REG_DWORD', '/d', '4', '/f') -AllowFailure
        Stop-Service -Name tzautoupdate -ErrorAction SilentlyContinue
        Set-Service -Name tzautoupdate -StartupType Disabled -ErrorAction Stop
        "$(Get-Date -Format 'o') Disabled Auto Time Zone Updater after DMA setup." |
            Out-File (Join-Path $logDir 'FirstLogon.log') -Append
    }
    catch {
        $errors.Add("Auto Time Zone Updater disable failed after DMA setup: $_") | Out-Null
        Write-WinMintFirstLogonError "Auto Time Zone Updater disable failed after DMA setup: $_"
    }

    $observedTimeZone = $null
    $observedHomeLocation = $null
    $observedCulture = $null
    try { $observedTimeZone = Get-TimeZone } catch { $errors.Add("Time zone verification failed: $_") | Out-Null }
    try { $observedHomeLocation = Get-WinHomeLocation } catch { $errors.Add("Home location verification failed: $_") | Out-Null }
    try { $observedCulture = Get-Culture } catch { $errors.Add("Culture verification failed: $_") | Out-Null }

    $observedGeoIdText = if ($observedHomeLocation) { [string]([int]$observedHomeLocation.GeoId) } else { '0' }
    $observedTimeZoneText = if ($observedTimeZone) { [string]$observedTimeZone.Id } else { '' }
    $observedCultureText = if ($observedCulture) { [string]$observedCulture.Name } else { '' }
    if ($restoreGeoId -gt 0 -and (-not $observedHomeLocation -or [int]$observedHomeLocation.GeoId -ne $restoreGeoId)) {
        $errors.Add("Current home location GeoID '$observedGeoIdText' does not match restore GeoID '$restoreGeoId'.") | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($restoreTimeZoneId) -and (-not $observedTimeZone -or [string]$observedTimeZone.Id -ne $restoreTimeZoneId)) {
        $errors.Add("Current time zone '$observedTimeZoneText' does not match restore time zone '$restoreTimeZoneId'.") | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($restoreUserLocale) -and (-not $observedCulture -or [string]$observedCulture.Name -ne $restoreUserLocale)) {
        $errors.Add("Current culture '$observedCultureText' does not match restore culture '$restoreUserLocale'.") | Out-Null
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
    $path = Join-Path $logDir 'FirstLogon_KnownFolders.json'
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    "$(Get-Date -Format 'o') Known folder verification written to $path" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
}

function Invoke-WinMintFirstLogonOneDriveRemoval {
    "$(Get-Date -Format 'o') Removing OneDrive user integration" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
    foreach ($name in @('OneDrive', 'OneDriveSetup')) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    foreach ($setup in @(
            "$env:SystemRoot\System32\OneDriveSetup.exe",
            "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
            "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
        )) {
        if (Test-Path -LiteralPath $setup) {
            try {
                Start-Process -FilePath $setup -ArgumentList '/uninstall' -WindowStyle Hidden -Wait -ErrorAction Stop | Out-Null
            }
            catch {
                Write-WinMintFirstLogonError "OneDrive uninstall failed for ${setup}: $_"
            }
        }
    }

    $setupFiles = @(
        "$env:SystemRoot\System32\OneDriveSetup.exe",
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
        "$env:SystemRoot\System32\OneDriveSetup.exe.bak",
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe.bak",
        "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
    )
    foreach ($setupFile in $setupFiles) {
        if (-not (Test-Path -LiteralPath $setupFile)) { continue }
        try {
            takeown.exe /f $setupFile | Out-Null
            icacls.exe $setupFile /grant '*S-1-5-32-544:F' | Out-Null
            Remove-Item -LiteralPath $setupFile -Force -ErrorAction Stop
        }
        catch {
            Write-WinMintFirstLogonError "OneDrive installer file removal failed for ${setupFile}: $_"
        }
    }

    foreach ($folder in @('Desktop', 'Documents', 'Downloads', 'Pictures', 'Music', 'Videos')) {
        New-Item -ItemType Directory -Path (Join-Path $env:USERPROFILE $folder) -Force -ErrorAction SilentlyContinue | Out-Null
    }

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
    foreach ($known in $knownFolders) {
        $expandValue = "%USERPROFILE%\$($known.Local)"
        $absoluteValue = Join-Path $env:USERPROFILE $known.Local
        Invoke-WinMintFirstLogonReg -Arguments @('add', $userShellFolders, '/v', $known.Name, '/t', 'REG_EXPAND_SZ', '/d', $expandValue, '/f') -AllowFailure
        Invoke-WinMintFirstLogonReg -Arguments @('add', $shellFolders, '/v', $known.Name, '/t', 'REG_SZ', '/d', $absoluteValue, '/f') -AllowFailure
    }

    foreach ($regArgs in @(
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableFileSync', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableFileSyncNGSC', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisablePersonalSync', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive', '/v', 'DisableLibrariesDefaultSaveToOneDrive', '/t', 'REG_DWORD', '/d', '1', '/f'),
            @('add', 'HKCR\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}', '/v', 'System.IsPinnedToNameSpaceTree', '/t', 'REG_DWORD', '/d', '0', '/f'),
            @('add', 'HKCR\WOW6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}', '/v', 'System.IsPinnedToNameSpaceTree', '/t', 'REG_DWORD', '/d', '0', '/f')
        )) {
        Invoke-WinMintFirstLogonReg -Arguments $regArgs -AllowFailure
    }

    foreach ($runKey in @(
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run',
            'HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
            'HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            'HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        )) {
        foreach ($value in @('OneDrive', 'OneDriveSetup')) {
            Invoke-WinMintFirstLogonReg -Arguments @('delete', $runKey, '/v', $value, '/f') -AllowFailure
        }
    }

    foreach ($root in @(
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Active Setup\Installed Components',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Active Setup\Installed Components',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
            'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\App Paths',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
            'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SyncRootManager',
            'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace'
        )) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            $text = @(
                $key.PSChildName
                if ($props) { $props.PSObject.Properties | ForEach-Object { [string]$_.Value } }
            ) -join "`n"
            if ($text -match '(?i)OneDrive|OneDriveSetup\.exe') {
                try {
                    Remove-Item -LiteralPath $key.PSPath -Recurse -Force -ErrorAction Stop
                }
                catch {
                    Write-WinMintFirstLogonError "OneDrive registry residue removal failed for $($key.Name): $_"
                }
            }
        }
    }

    Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object {
            $_.TaskName -match '(?i)OneDrive' -or
            $_.TaskPath -match '(?i)OneDrive' -or
            @($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -match '(?i)OneDrive|OneDriveSetup\.exe'
        } |
        Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue

    Remove-Item -LiteralPath @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive",
        "$env:ProgramData\Microsoft OneDrive",
        "$env:SystemDrive\OneDriveTemp"
    ) -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\OneDrive*.lnk" -Force -ErrorAction SilentlyContinue

    $oneDriveRoots = @(
        Join-Path $env:USERPROFILE 'OneDrive'
        Get-ChildItem -LiteralPath $env:USERPROFILE -Directory -Filter 'OneDrive -*' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
    )
    foreach ($root in @($oneDriveRoots | Where-Object { $_ -and (Test-Path -LiteralPath $_) })) {
        $children = @(Get-ChildItem -LiteralPath $root -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($children.Count -eq 0) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
        else {
            Write-WinMintFirstLogonError "OneDrive folder not removed because it contains files: $root"
        }
    }

    $policy = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' -ErrorAction SilentlyContinue
    $userShell = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
    $shellFolderAudit = @{}
    foreach ($known in $knownFolders) {
        $property = if ($userShell) { $userShell.PSObject.Properties[$known.Name] } else { $null }
        $shellFolderAudit[$known.Name] = if ($property) { $property.Value } else { $null }
    }
    $runResidue = foreach ($runKey in @(
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
            'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run',
            'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\RunOnce',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        )) {
        $props = Get-ItemProperty -LiteralPath $runKey -ErrorAction SilentlyContinue
        foreach ($value in @('OneDrive', 'OneDriveSetup')) {
            $property = if ($props) { $props.PSObject.Properties[$value] } else { $null }
            if ($property) { [ordered]@{ path = $runKey; name = $value; value = $property.Value } }
        }
    }
    $registryResidue = foreach ($root in @(
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Active Setup\Installed Components',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Active Setup\Installed Components',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
            'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\App Paths',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
            'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SyncRootManager',
            'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace'
        )) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            $text = @(
                $key.PSChildName
                if ($props) { $props.PSObject.Properties | ForEach-Object { [string]$_.Value } }
            ) -join "`n"
            if ($text -match '(?i)OneDrive|OneDriveSetup\.exe') {
                [ordered]@{ path = $key.Name }
            }
        }
    }
    $oneDriveAudit = [ordered]@{
        timestamp = Get-Date -Format o
        installerFiles = @($setupFiles | ForEach-Object {
                [ordered]@{ path = $_; exists = [bool](Test-Path -LiteralPath $_) }
            })
        policy = [ordered]@{
            disableFileSync = if ($policy) { $policy.DisableFileSync } else { $null }
            disableFileSyncNGSC = if ($policy) { $policy.DisableFileSyncNGSC } else { $null }
            disablePersonalSync = if ($policy) { $policy.DisablePersonalSync } else { $null }
            disableLibrariesDefaultSaveToOneDrive = if ($policy) { $policy.DisableLibrariesDefaultSaveToOneDrive } else { $null }
        }
        shellFolders = $shellFolderAudit
        namespacePinned = [ordered]@{
            clsid64 = (Get-ItemProperty `
                    -LiteralPath 'Registry::HKEY_CLASSES_ROOT\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' `
                    -Name 'System.IsPinnedToNameSpaceTree' `
                    -ErrorAction SilentlyContinue).'System.IsPinnedToNameSpaceTree'
            clsid32 = (Get-ItemProperty `
                    -LiteralPath 'Registry::HKEY_CLASSES_ROOT\WOW6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' `
                    -Name 'System.IsPinnedToNameSpaceTree' `
                    -ErrorAction SilentlyContinue).'System.IsPinnedToNameSpaceTree'
        }
        scheduledTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.TaskName -match '(?i)OneDrive' -or
                    $_.TaskPath -match '(?i)OneDrive' -or
                    @($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -match '(?i)OneDrive|OneDriveSetup\.exe'
                } |
                ForEach-Object { "$($_.TaskPath)$($_.TaskName)" })
        runResidue = @($runResidue)
        registryResidue = @($registryResidue)
        leftoverFolders = @($oneDriveRoots | Where-Object { $_ } | ForEach-Object {
                [ordered]@{ path = $_; exists = [bool](Test-Path -LiteralPath $_) }
            })
    }
    $oneDriveAudit['compliant'] = (
        @($oneDriveAudit.installerFiles | Where-Object exists).Count -eq 0 -and
        $null -ne $oneDriveAudit.policy.disableFileSync -and [int]$oneDriveAudit.policy.disableFileSync -eq 1 -and
        $null -ne $oneDriveAudit.policy.disableFileSyncNGSC -and [int]$oneDriveAudit.policy.disableFileSyncNGSC -eq 1 -and
        $null -ne $oneDriveAudit.policy.disablePersonalSync -and [int]$oneDriveAudit.policy.disablePersonalSync -eq 1 -and
        $null -ne $oneDriveAudit.policy.disableLibrariesDefaultSaveToOneDrive -and [int]$oneDriveAudit.policy.disableLibrariesDefaultSaveToOneDrive -eq 1 -and
        $null -ne $oneDriveAudit.namespacePinned.clsid64 -and [int]$oneDriveAudit.namespacePinned.clsid64 -eq 0 -and
        $null -ne $oneDriveAudit.namespacePinned.clsid32 -and [int]$oneDriveAudit.namespacePinned.clsid32 -eq 0 -and
        @($oneDriveAudit.scheduledTasks).Count -eq 0 -and
        @($oneDriveAudit.runResidue).Count -eq 0 -and
        @($oneDriveAudit.registryResidue).Count -eq 0
    )
    $oneDriveAuditPath = Join-Path $logDir 'FirstLogon_OneDriveAudit.json'
    $oneDriveAudit | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $oneDriveAuditPath -Encoding UTF8
    "$(Get-Date -Format 'o') OneDrive audit written to $oneDriveAuditPath" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
}

function Disable-WinMintAutoAdminLogon {
    $winlogon = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Invoke-WinMintFirstLogonReg -Arguments @('add', $winlogon, '/v', 'AutoAdminLogon', '/t', 'REG_SZ', '/d', '0', '/f')
}

function Remove-WinMintResidualPayload {
    # Pristine cleanup after a successful agent run. Keep only the profile that explains setup;
    # scripts and agents are one-shot payload and should not linger on the installed machine.
    $keep = @('WinMintSetupProfile.json')
    $self = [IO.Path]::GetFileName($PSCommandPath)
    foreach ($entry in @(Get-ChildItem -LiteralPath $payloadDir -Force -ErrorAction SilentlyContinue)) {
        if ($keep -contains $entry.Name) { continue }
        if ($entry.Name -ieq $self) { continue }   # this script can't delete itself while running
        try { Remove-Item -LiteralPath $entry.FullName -Recurse -Force -ErrorAction Stop }
        catch { Write-WinMintFirstLogonError "Cleanup failed for $($entry.FullName): $_" }
    }
    # Schedule a delayed self-delete via cmd.exe so this PowerShell host can release the script handle first.
    try {
        $self = $PSCommandPath
        Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', "timeout /t 3 /nobreak > nul && del /q /f `"$self`"") -WindowStyle Hidden | Out-Null
    } catch { Write-WinMintFirstLogonError "Self-delete schedule failed: $_" }
}

$state = @{
    startedAt = Get-Date -Format o
    agentExitCode = $null
    status = 'running'
}
try { Save-WinMintFirstLogonState -State $state } catch { Write-WinMintFirstLogonError "FirstLogon state write failed: $_" }
try { Set-WinMintFirstLogonRetry } catch { Write-WinMintFirstLogonError "FirstLogon retry registration failed: $_" }
# Clear the plaintext DefaultPassword from the registry now that we have signed in.
# RunOnce handles all retries from this point — leaving the password in HKLM until
# the agent eventually succeeds is unnecessary and exposes it to any local admin.
try { Clear-WinMintAutoLogonPassword } catch { Write-WinMintFirstLogonError "AutoLogon password clear failed: $_" }

$dmaRestore = Restore-WinMintDmaRegionalDefaults
if ($dmaRestore.Enabled -and -not $dmaRestore.Compliant) {
    $state['status'] = 'failed'
    $state['failedAt'] = Get-Date -Format o
    $state['criticalStep'] = 'dmaInteropRestore'
    $state['error'] = "DMA regional restore failed. Report: $($dmaRestore.Report)"
    $state['errors'] = @($dmaRestore.Errors)
    try { Save-WinMintFirstLogonState -State $state } catch { Write-WinMintFirstLogonError "FirstLogon state write failed: $_" }
    Write-WinMintFirstLogonError "DMA regional restore failed; optional FirstLogon modules were not launched. Report: $($dmaRestore.Report)"
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
    exit 1
}

try { Repair-WinMintFirstLogonKnownFolders } catch { Write-WinMintFirstLogonError "Known folder repair failed: $_" }
try { Set-WinMintFirstLogonDesktopDefaults } catch { Write-WinMintFirstLogonError "Desktop defaults failed: $_" }
try { Invoke-WinMintFirstLogonOneDriveRemoval } catch { Write-WinMintFirstLogonError "OneDrive user cleanup failed: $_" }

$agentExitCode = 0
$agentRoot = Join-Path $payloadDir 'WinMintAgent'
$agent     = Join-Path $agentRoot 'Start-WinMintAgent.ps1'
$agentUI   = Join-Path $agentRoot 'Start-WinMintFirstLogonUI.ps1'
if (Test-Path -LiteralPath $agent) {
    try {
        $exe = Resolve-WinMintPowerShellHost
        # The agent is the source of truth and can run without any GUI. UI and
        # console modes are observers over state.json and WinMintAgent-events.jsonl.
        $mode = Resolve-WinMintFirstLogonAgentMode -RequestedMode $AgentMode -AgentUIPath $agentUI
        "$(Get-Date -Format 'o') Launching WinMintAgent in $mode mode" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
        if ($mode -eq 'UI') {
            $agentProcess = Start-Process -FilePath $exe -ArgumentList @(
                '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', "`"$agentUI`""
            ) -WindowStyle Normal -Wait -PassThru
            if ([int]$agentProcess.ExitCode -eq 2) {
                $mode = 'Console'
            }
            else {
                $agentExitCode = [int]$agentProcess.ExitCode
            }
        }
        if ($mode -eq 'Console') {
            $agentProcess = Start-Process -FilePath $exe -ArgumentList @(
                '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', "`"$agent`"", '-InteractiveFirstLogon'
            ) -WindowStyle Normal -Wait -PassThru
            $agentExitCode = [int]$agentProcess.ExitCode
        }
        elseif ($mode -eq 'Headless') {
            $agentProcess = Start-Process -FilePath $exe -ArgumentList @(
                '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', "`"$agent`""
            ) -WindowStyle Hidden -Wait -PassThru
            $agentExitCode = [int]$agentProcess.ExitCode
        }
        if ($agentExitCode -ne 0) { Write-WinMintFirstLogonError "WinMintAgent exited with code $agentExitCode" }
    }
    catch {
        $agentExitCode = 1
        Write-WinMintFirstLogonError "WinMintAgent launch failed: $_"
    }
}
else {
    $agentExitCode = 1
    Write-WinMintFirstLogonError "WinMintAgent script was not found: $agent"
}

$state['agentExitCode'] = $agentExitCode
$state['completedAt'] = Get-Date -Format o
if ($agentExitCode -eq 0) {
    $state['status'] = 'ok'
    try {
        Clear-WinMintFirstLogonRetry
        Disable-WinMintAutoAdminLogon
    }
    catch {
        Write-WinMintFirstLogonError "AutoLogon cleanup failed: $_"
    }
    try { Remove-WinMintResidualPayload }
    catch { Write-WinMintFirstLogonError "Residual cleanup failed: $_" }
}
else {
    $state['status'] = 'failed'
    Write-WinMintFirstLogonError 'AutoAdminLogon left enabled so the next sign-in can retry; the password value has already been cleared.'
}
try { Save-WinMintFirstLogonState -State $state } catch { Write-WinMintFirstLogonError "FirstLogon state write failed: $_" }
"$(Get-Date -Format 'o') FirstLogon.ps1 end" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
if ($agentExitCode -ne 0) { exit $agentExitCode }
